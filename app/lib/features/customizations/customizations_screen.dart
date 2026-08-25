import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/name_colors.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/matrix_button.dart';
import '../../models/cosmetic_item.dart';
import 'widgets/profile_customization_preview.dart';

/// Profile customizations screen (Personalizações).
///
/// The first live category is 🎨 COR DO NICKNAME: a solid text color from
/// the SERVER-OWNED palette (the app never hardcodes which colors exist).
/// Selecting a swatch updates the preview immediately; saving sends only
/// the color ID to the server, which validates id/active/type — a client
/// can never equip an arbitrary hex. "Padrão" unequips the slot (null).
class CustomizationsScreen extends StatefulWidget {
  const CustomizationsScreen({super.key});

  @override
  State<CustomizationsScreen> createState() => _CustomizationsScreenState();
}

class _CustomizationsScreenState extends State<CustomizationsScreen> {
  bool _requested = false;

  /// Local selection: the catalog item id, or null for "Padrão". Initialized
  /// from the equipped state on first build; [_dirty] tracks changes.
  String? _selectedColorId;
  bool _selectionReady = false;
  bool _dirty = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppStateScope.of() cannot run in initState (inherited dependency),
    // and the loads notify listeners — so schedule them post-frame, never
    // during the build phase.
    if (!_requested) {
      _requested = true;
      final state = AppStateScope.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        state.loadMyCosmetics();
        state.loadNameColorCatalog();
      });
    }
  }

  void _initSelection(CosmeticMap equipped) {
    if (_selectionReady) return;
    _selectionReady = true;
    _selectedColorId = equipped[CosmeticItem.nameColor]?.id;
  }

  void _select(String? colorId) {
    setState(() {
      _selectedColorId = colorId;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final state = AppStateScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final selected = _selectedColorId;
      if (selected == null) {
        await state.unequipCosmetic(CosmeticItem.nameColor);
      } else {
        await state.equipCosmetic(selected);
      }
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Cor do nickname atualizada.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível salvar a cor. Tente novamente.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final user = state.currentUser;
    if (user == null) {
      return Scaffold(backgroundColor: AppColors.absoluteBlack);
    }
    _initSelection(state.myCosmetics);

    // Preview reflects the LOCAL selection immediately (before saving):
    // the selected hex, or an empty string for the explicit default.
    final selectedItem = _selectedColorId == null
        ? null
        : state.nameColorCatalog
            .where((c) => c.id == _selectedColorId)
            .firstOrNull;
    final previewOverride = !_selectionReady
        ? null
        : (_selectedColorId == null
            ? ''
            : (selectedItem?.hexColor ??
                state.myCosmetics[CosmeticItem.nameColor]?.hexColor ??
                user.nameColor));

    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDimensions.spaceLg),
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: AppColors.techWhite,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: AppDimensions.spaceXs),
                Text('PERSONALIZAÇÕES', style: AppTextStyles.title),
              ],
            ),
            const SizedBox(height: AppDimensions.spaceLg),
            ProfileCustomizationPreview(
              user: user,
              cosmetics: state.myCosmetics,
              nameColorOverride: previewOverride,
            ),
            const SizedBox(height: AppDimensions.spaceLg),
            _NameColorSection(
              catalog: state.nameColorCatalog,
              selectedId: _selectedColorId,
              onSelect: _select,
            ),
            if (_dirty) ...[
              const SizedBox(height: AppDimensions.spaceMd),
              MatrixButton(
                label: 'Salvar',
                icon: Icons.check_rounded,
                expanded: true,
                isLoading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
            const Divider(height: AppDimensions.spaceXxl),
            const _CosmeticSection(
              icon: Icons.crop_free_rounded,
              title: 'Moldura',
            ),
            const _CosmeticSection(
              icon: Icons.auto_awesome_rounded,
              title: 'Efeito de nome',
            ),
            const _CosmeticSection(
              icon: Icons.verified_user_outlined,
              title: 'Badge',
            ),
          ],
        ),
      ),
    );
  }
}

/// 🎨 Cor do nickname — the server-owned palette grouped by category, plus
/// the "Padrão" option that removes the customization (nameColor = null).
class _NameColorSection extends StatelessWidget {
  const _NameColorSection({
    required this.catalog,
    required this.selectedId,
    required this.onSelect,
  });

  final List<CosmeticItem> catalog;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  static const Map<String, String> _categoryLabels = {
    'basic': 'CORES BÁSICAS',
    'reds': 'VERMELHOS',
    'oranges': 'LARANJAS',
    'yellows': 'AMARELOS',
    'greens': 'VERDES',
    'blues': 'AZUIS',
    'purples': 'ROXOS',
    'pinks': 'ROSAS',
    'cyans': 'CIANOS',
    'grays': 'CINZAS',
    'browns': 'MARRONS',
    'special': 'TONS ESPECIAIS',
  };

  @override
  Widget build(BuildContext context) {
    // Group by the server-provided category, keeping the server's curated
    // order (sortOrder) inside and across groups.
    final groups = <String?, List<CosmeticItem>>{};
    for (final item in catalog) {
      groups.putIfAbsent(item.category, () => []).add(item);
    }
    final orderedKeys = groups.keys.toList()
      ..sort((a, b) {
        if (a == null) return -1;
        if (b == null) return 1;
        return groups[a]!.first.sortOrder
            .compareTo(groups[b]!.first.sortOrder);
      });

    return Container(
      padding: const EdgeInsets.all(AppDimensions.spaceLg),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(color: AppColors.deepBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_rounded,
                  color: AppColors.electricBlue, size: 22),
              const SizedBox(width: AppDimensions.spaceMd),
              Expanded(
                child: Text('Cor do nickname', style: AppTextStyles.h3),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.spaceMd),
          if (catalog.isEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: AppDimensions.spaceLg),
              child: Center(
                child: Text('Carregando cores…', style: AppTextStyles.caption),
              ),
            )
          else ...[
            // Default option: removes the customization (server stores
            // nameColorId = null → the default MATRIX nickname color).
            _DefaultColorTile(
              selected: selectedId == null,
              onTap: () => onSelect(null),
            ),
            for (final key in orderedKeys) ...[
              const SizedBox(height: AppDimensions.spaceMd),
              Text(
                _categoryLabels[key] ?? (key ?? '').toUpperCase(),
                style: AppTextStyles.hud.copyWith(fontSize: 11),
              ),
              const SizedBox(height: AppDimensions.spaceSm),
              Wrap(
                spacing: AppDimensions.spaceSm,
                runSpacing: AppDimensions.spaceSm,
                children: [
                  for (final item in groups[key]!)
                    _ColorSwatch(
                      item: item,
                      selected: item.id == selectedId,
                      onTap: () => onSelect(item.id),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// The "🎨 Padrão" tile — clears the name color back to the MATRIX default.
class _DefaultColorTile extends StatelessWidget {
  const _DefaultColorTile({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spaceMd,
          vertical: AppDimensions.spaceSm,
        ),
        decoration: BoxDecoration(
          color: AppColors.nightBlue,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          border: Border.all(
            color: selected ? AppColors.electricBlue : AppColors.deepBlue,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.format_color_reset_rounded,
                color: AppColors.holographicBlue, size: 18),
            const SizedBox(width: AppDimensions.spaceSm),
            Text('Padrão', style: AppTextStyles.body),
            if (selected) ...[
              const SizedBox(width: AppDimensions.spaceSm),
              Icon(Icons.check_circle_rounded,
                  color: AppColors.electricBlue, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}

/// A single palette swatch. The selected color gets a subtle border + check
/// — no exaggerated design.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final CosmeticItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(item.hexColor) ?? AppColors.holographicBlue;
    return Tooltip(
      message: item.name,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.techWhite : AppColors.deepBlue,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  size: 20,
                  // Check stays readable on any swatch without adding
                  // effects to the nickname itself.
                  color: color.computeLuminance() > 0.4
                      ? Colors.black
                      : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}

/// A cosmetic category row. Placeholder ("Em breve") until the category
/// ships; the row already knows its slot so wiring the picker later is a
/// local change.
class _CosmeticSection extends StatelessWidget {
  const _CosmeticSection({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimensions.spaceMd),
      child: Container(
        padding: const EdgeInsets.all(AppDimensions.spaceLg),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          border: Border.all(color: AppColors.deepBlue),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.electricBlue, size: 22),
            const SizedBox(width: AppDimensions.spaceMd),
            Expanded(child: Text(title, style: AppTextStyles.h3)),
            Text('Em breve', style: AppTextStyles.caption),
          ],
        ),
      ),
    );
  }
}
