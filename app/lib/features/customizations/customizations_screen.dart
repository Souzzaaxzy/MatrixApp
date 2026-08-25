import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/name_colors.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/nickname_renderer.dart';
import '../../models/cosmetic_item.dart';
import '../../models/name_effect.dart';
import 'widgets/profile_customization_preview.dart';

/// Profile customizations screen (Personalizações).
///
/// Two INDEPENDENT categories, both from the server-owned catalog:
///  🎨 Cor do nickname   (NAME_COLOR — solid text color)
///  ✨ Efeito do nickname (NAME_EFFECT — visual effect + render config)
///
/// Selections update the PREVIEW immediately but are NOT persisted until
/// the user taps "SALVAR ALTERAÇÕES", which sends the whole pending
/// configuration in ONE consolidated operation ({nameColorId, nameEffectId}).
/// Leaving without saving discards the pending selection (the server state
/// is restored on the next open). "Padrão"/"Nenhum" clear their slot (null).
class CustomizationsScreen extends StatefulWidget {
  const CustomizationsScreen({super.key});

  @override
  State<CustomizationsScreen> createState() => _CustomizationsScreenState();
}

class _CustomizationsScreenState extends State<CustomizationsScreen> {
  bool _requested = false;

  /// Local pending selections: catalog item ids, or null for "Padrão"/
  /// "Nenhum". Initialized from the equipped state on first build; [_dirty]
  /// tracks unsaved changes.
  String? _selectedColorId;
  String? _selectedEffectId;
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
        state.loadNameEffectCatalog();
      });
    }
  }

  void _initSelection(CosmeticMap equipped) {
    if (_selectionReady) return;
    _selectionReady = true;
    _selectedColorId = equipped[CosmeticItem.nameColor]?.id;
    _selectedEffectId = equipped[CosmeticItem.nameEffect]?.id;
  }

  void _selectColor(String? colorId) {
    setState(() {
      _selectedColorId = colorId;
      _dirty = true;
    });
  }

  void _selectEffect(String? effectId) {
    setState(() {
      _selectedEffectId = effectId;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final state = AppStateScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // ONE consolidated operation: color + effect together.
      await state.saveCosmetics(
        nameColorId: _selectedColorId,
        nameEffectId: _selectedEffectId,
      );
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Personalizações salvas.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível salvar. Tente novamente.'),
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

    // Preview reflects the LOCAL pending selection immediately — color and
    // effect resolve independently (any color + any effect).
    final selectedColor = _selectedColorId == null
        ? null
        : state.nameColorCatalog
            .where((c) => c.id == _selectedColorId)
            .firstOrNull;
    final previewColor = !_selectionReady
        ? null
        : (_selectedColorId == null
            ? ''
            : (selectedColor?.hexColor ??
                state.myCosmetics[CosmeticItem.nameColor]?.hexColor ??
                user.nameColor));
    final selectedEffect = _selectedEffectId == null
        ? null
        : state.nameEffectCatalog
            .where((e) => e.id == _selectedEffectId)
            .firstOrNull;
    final previewEffect = !_selectionReady
        ? null
        : (_selectedEffectId == null
            ? const NameEffect(id: '') // sentinel: explicit "Nenhum"
            : (selectedEffect == null
                ? null
                : NameEffect(
                    id: selectedEffect.id,
                    name: selectedEffect.name,
                    config: selectedEffect.config,
                  )));

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
              nameColorOverride: previewColor,
              nameEffectOverride: previewEffect,
            ),
            const SizedBox(height: AppDimensions.spaceLg),
            _NameColorSection(
              catalog: state.nameColorCatalog,
              selectedId: _selectedColorId,
              onSelect: _selectColor,
            ),
            const SizedBox(height: AppDimensions.spaceMd),
            _NameEffectSection(
              catalog: state.nameEffectCatalog,
              selectedId: _selectedEffectId,
              colorHex: previewColor == null || previewColor.isEmpty
                  ? null
                  : previewColor,
              onSelect: _selectEffect,
            ),
            if (_dirty) ...[
              const SizedBox(height: AppDimensions.spaceMd),
              MatrixButton(
                label: 'Salvar alterações',
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
              icon: Icons.verified_user_outlined,
              title: 'Badge',
            ),
          ],
        ),
      ),
    );
  }
}

/// ✨ Efeito do nickname — the server-owned effect catalog grouped by
/// category, plus the "Nenhum" option (nameEffectId = null). Each tile
/// renders a live mini-preview of the effect through the SAME renderer used
/// everywhere else (NicknameRenderer), so what you see is what you get.
class _NameEffectSection extends StatelessWidget {
  const _NameEffectSection({
    required this.catalog,
    required this.selectedId,
    required this.colorHex,
    required this.onSelect,
  });

  final List<CosmeticItem> catalog;
  final String? selectedId;

  /// The pending/equipped color, so tiles preview color + effect combined.
  final String? colorHex;
  final ValueChanged<String?> onSelect;

  static const Map<String, String> _categoryLabels = {
    'glow': '✨ EFEITOS DE BRILHO',
    'animated': '⚡ EFEITOS ANIMADOS',
    'glitch': '👾 EFEITOS GLITCH',
    'color': '🌈 EFEITOS DE COR',
    'elemental': '🔥 EFEITOS ELEMENTAIS',
    'premium': '💎 EFEITOS PREMIUM',
    'cyberpunk': '🧬 EFEITOS CYBERPUNK',
    'dark': '🌑 EFEITOS DARK',
    'visual': '🎭 EFEITOS VISUAIS',
  };

  @override
  Widget build(BuildContext context) {
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
              Icon(Icons.auto_awesome_rounded,
                  color: AppColors.electricBlue, size: 22),
              const SizedBox(width: AppDimensions.spaceMd),
              Expanded(
                child: Text('Efeito do nickname', style: AppTextStyles.h3),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.spaceMd),
          if (catalog.isEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: AppDimensions.spaceLg),
              child: Center(
                child:
                    Text('Carregando efeitos…', style: AppTextStyles.caption),
              ),
            )
          else ...[
            // 🚫 Nenhum — nameEffectId = null; the color keeps working.
            _NoneEffectTile(
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
                    _EffectChip(
                      item: item,
                      selected: item.id == selectedId,
                      colorHex: colorHex,
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

/// The "🚫 Nenhum" tile — clears the effect (nameEffectId = null).
class _NoneEffectTile extends StatelessWidget {
  const _NoneEffectTile({required this.selected, required this.onTap});

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
            Icon(Icons.block_rounded,
                color: AppColors.holographicBlue, size: 18),
            const SizedBox(width: AppDimensions.spaceSm),
            Text('Nenhum', style: AppTextStyles.body),
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

/// A single effect tile with a LIVE mini-preview: the effect's own name
/// rendered through NicknameRenderer (lightweight mode — dozens of tiles
/// animate without hurting scroll).
class _EffectChip extends StatelessWidget {
  const _EffectChip({
    required this.item,
    required this.selected,
    required this.colorHex,
    required this.onTap,
  });

  final CosmeticItem item;
  final bool selected;
  final String? colorHex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: item.name,
      child: GestureDetector(
        onTap: onTap,
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
          child: NicknameRenderer(
            item.name,
            nameColor: colorHex,
            effect: NameEffect(
              id: item.id,
              name: item.name,
              config: item.config,
            ),
            background: AppColors.nightBlue,
            baseStyle: AppTextStyles.body,
            lightweight: true,
          ),
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
