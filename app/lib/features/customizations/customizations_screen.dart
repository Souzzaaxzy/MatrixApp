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
/// The screen is a MENU OF CATEGORIES — nothing stays open all at once:
///
///   PERSONALIZAÇÕES
///    ┌ 🎨 Cor do nickname            › ┐  → palette submenu
///    └ 🖼️ Molduras                    › ┘  → frames submenu
///
/// Tapping a category opens its own section (in-place, no new route — so
/// navigation can never break) with a clear "‹ Voltar" that returns to the
/// category menu. Selections update the PREVIEW immediately but are NOT
/// persisted until the user taps "SALVAR ALTERAÇÕES", which sends the whole
/// pending configuration in ONE consolidated operation ({nameColorId}).
/// Leaving without saving discards the pending selection (the server state
/// is restored on the next open). "Padrão" clears the color (null).
class CustomizationsScreen extends StatefulWidget {
  const CustomizationsScreen({super.key});

  @override
  State<CustomizationsScreen> createState() => _CustomizationsScreenState();
}

/// Which section is visible: the category menu or one open category.
enum _Section { menu, colors, frames }

class _CustomizationsScreenState extends State<CustomizationsScreen> {
  bool _requested = false;

  _Section _section = _Section.menu;

  /// Local pending selection: catalog item id, or null for "Padrão".
  /// Initialized from the equipped state on first build; [_dirty] tracks
  /// unsaved changes.
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

  void _selectColor(String? colorId) {
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
      // ONE consolidated operation with the whole pending customization.
      await state.saveCosmetics(nameColorId: _selectedColorId);
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

    // Preview reflects the LOCAL pending selection immediately.
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

    final inMenu = _section == _Section.menu;
    final title = switch (_section) {
      _Section.menu => 'PERSONALIZAÇÕES',
      _Section.colors => 'COR DO NICKNAME',
      _Section.frames => 'MOLDURAS',
    };

    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDimensions.spaceLg),
          children: [
            _Header(
              title: title,
              // Inside a category "‹" returns to the menu; in the menu it
              // pops the screen. Never a broken route either way.
              onBack: inMenu
                  ? () => Navigator.of(context).pop()
                  : () => setState(() => _section = _Section.menu),
            ),
            const SizedBox(height: AppDimensions.spaceLg),
            ProfileCustomizationPreview(
              user: user,
              cosmetics: state.myCosmetics,
              nameColorOverride: previewColor,
            ),
            const SizedBox(height: AppDimensions.spaceLg),
            switch (_section) {
              _Section.menu => _CategoryMenu(
                  onOpenColors: () => setState(() => _section = _Section.colors),
                  onOpenFrames: () => setState(() => _section = _Section.frames),
                ),
              _Section.colors => _NameColorSection(
                  catalog: state.nameColorCatalog,
                  selectedId: _selectedColorId,
                  onSelect: _selectColor,
                ),
              _Section.frames => const _FramesSection(),
            },
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
          ],
        ),
      ),
    );
  }
}

/// Screen/section header: back arrow + title. The same widget serves the
/// menu (pops the screen) and the submenus (returns to the menu).
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: AppColors.techWhite,
          tooltip: 'Voltar',
          onPressed: onBack,
        ),
        const SizedBox(width: AppDimensions.spaceXs),
        Expanded(child: Text(title, style: AppTextStyles.title)),
      ],
    );
  }
}

/// The category menu: one tappable button per customization category.
class _CategoryMenu extends StatelessWidget {
  const _CategoryMenu({required this.onOpenColors, required this.onOpenFrames});

  final VoidCallback onOpenColors;
  final VoidCallback onOpenFrames;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CategoryButton(
          icon: Icons.palette_rounded,
          title: 'Cor do nickname',
          subtitle: 'Personalize a cor do seu nome',
          onTap: onOpenColors,
        ),
        const SizedBox(height: AppDimensions.spaceMd),
        _CategoryButton(
          icon: Icons.crop_free_rounded,
          title: 'Molduras',
          subtitle: 'Personalize a moldura do seu perfil',
          onTap: onOpenFrames,
        ),
      ],
    );
  }
}

/// A category button: icon + name + short description + chevron, styled
/// like a real settings entry of the MATRIX design system.
class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardSurface,
      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppDimensions.spaceLg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            border: Border.all(color: AppColors.deepBlue),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.electricBlue, size: 24),
              const SizedBox(width: AppDimensions.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.h3),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppTextStyles.caption),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.holographicBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 🖼️ Molduras — prepared section. New frames are NOT part of this change:
/// the section exists so the frame picker can land here later. The equipped
/// AVATAR_FRAME (if any) keeps rendering in the preview above.
class _FramesSection extends StatelessWidget {
  const _FramesSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.spaceLg),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(color: AppColors.deepBlue),
      ),
      child: Column(
        children: [
          Icon(Icons.crop_free_rounded,
              color: AppColors.holographicBlue, size: 32),
          const SizedBox(height: AppDimensions.spaceMd),
          Text('Molduras', style: AppTextStyles.h3),
          const SizedBox(height: AppDimensions.spaceSm),
          Text(
            'Em breve você poderá escolher molduras para o seu perfil aqui.',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),
        ],
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

/// The "Padrão" tile — clears the name color back to the MATRIX default.
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
                  // Check stays readable on any swatch.
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
