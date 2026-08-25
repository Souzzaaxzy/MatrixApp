import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/services/theme_controller.dart';
import '../../core/widgets/app_state_scope.dart';

/// Settings bottom sheet shown ONLY on the session user's own profile.
///
/// Contains the global theme (Escuro / Claro / Sistema, persisted),
/// "Sair da conta" (with confirmation) and "Excluir conta" (strong
/// confirmation + nickname re-entry, the hard server delete).
class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key});

  static void open(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const SettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ThemeController.instance;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimensions.spaceXl,
          AppDimensions.spaceMd,
          AppDimensions.spaceXl,
          AppDimensions.spaceXl,
        ),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.holographicBlue.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.spaceLg),
            Text('CONFIGURAÇÕES', style: AppTextStyles.title.copyWith(fontSize: 16)),
            const SizedBox(height: AppDimensions.spaceLg),
            Text('TEMA', style: AppTextStyles.hud),
            const SizedBox(height: AppDimensions.spaceSm),
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => Column(
                children: [
                  _ThemeOption(
                    icon: Icons.dark_mode_rounded,
                    label: 'Escuro',
                    mode: MatrixThemeMode.dark,
                    active: controller.mode == MatrixThemeMode.dark,
                    onSelected: () => controller.setMode(MatrixThemeMode.dark),
                  ),
                  _ThemeOption(
                    icon: Icons.light_mode_rounded,
                    label: 'Claro',
                    mode: MatrixThemeMode.light,
                    active: controller.mode == MatrixThemeMode.light,
                    onSelected: () => controller.setMode(MatrixThemeMode.light),
                  ),
                  _ThemeOption(
                    icon: Icons.smartphone_rounded,
                    label: 'Sistema',
                    mode: MatrixThemeMode.system,
                    active: controller.mode == MatrixThemeMode.system,
                    onSelected: () => controller.setMode(MatrixThemeMode.system),
                  ),
                ],
              ),
            ),
            const Divider(height: AppDimensions.spaceXxl),
            _SettingsRow(
              icon: Icons.logout_rounded,
              accent: false,
              label: 'Sair da conta',
              onTap: () => _confirmLogout(context),
            ),
            _SettingsRow(
              icon: Icons.delete_forever_rounded,
              accent: true,
              label: 'Excluir conta',
              onTap: () => _confirmDelete(context),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        title: Text('Sair da conta?', style: AppTextStyles.h3),
        content: Text(
          'Tem certeza que deseja sair da conta?',
          style: AppTextStyles.bodyMuted,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancelar', style: AppTextStyles.label),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Sair',
              style: AppTextStyles.label.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await AppStateScope.of(context).logout();
    if (!context.mounted) return;
    await _exitToLogin(context);
  }

  /// Destructive flow: dialog #1 warns that the action is permanent;
  /// dialog #2 forces re-entering the exact nickname of the session user.
  Future<void> _confirmDelete(BuildContext context) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        title: Text('Excluir conta?', style: AppTextStyles.h3),
        content: Text(
          'Essa ação é permanente. Todos os seus dados poderão ser removidos '
          'de acordo com a política do MATRIX.',
          style: AppTextStyles.bodyMuted,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancelar', style: AppTextStyles.label),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Excluir minha conta',
              style: AppTextStyles.label.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;

    final state = AppStateScope.of(context);
    final username = state.currentUser?.username;
    if (username == null) return;

    String typed = '';
    final confirmedName = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.cardSurface,
            title: Text('Digite seu nickname para confirmar',
                style: AppTextStyles.h3),
            content: TextField(
              autofocus: true,
              onChanged: (value) => typed = value,
              decoration: InputDecoration(
                hintText: username,
                hintStyle: AppTextStyles.bodyMuted,
              ),
              style: AppTextStyles.body,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text('Cancelar', style: AppTextStyles.label),
              ),
              TextButton(
                onPressed: () {
                  final ok = typed.trim().replaceAll('@', '').toLowerCase() ==
                      username.toLowerCase();
                  Navigator.of(dialogContext).pop(ok);
                },
                child: Text(
                  'Excluir',
                  style: AppTextStyles.label.copyWith(color: AppColors.error),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmedName || !context.mounted) return;

    if (!context.mounted) return;
    try {
      await state.deleteAccount();
      if (!context.mounted) return;
      await _exitToLogin(context);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Não foi possível excluir a conta. Tente novamente.')),
      );
    }
  }

  Future<void> _exitToLogin(BuildContext context) async {
    // Every stack below login is removed — a session user leaving the app
    // must NEVER keep private state behind the back button.
    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.mode,
    required this.active,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final MatrixThemeMode mode;
  final bool active;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spaceSm,
          vertical: AppDimensions.spaceMd,
        ),
        child: Row(
          children: [
            Icon(icon,
                color: active ? AppColors.electricBlue : AppColors.holographicBlue,
                size: 20),
            const SizedBox(width: AppDimensions.spaceMd),
            Expanded(child: Text(label, style: AppTextStyles.body)),
            if (active)
              const Icon(Icons.check_rounded,
                  color: AppColors.electricBlue, size: 18),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = accent ? AppColors.error : AppColors.techWhite;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spaceSm,
          vertical: AppDimensions.spaceLg,
        ),
        child: Row(
          children: [
            Icon(icon, color: accent ? AppColors.error : AppColors.holographicBlue, size: 22),
            const SizedBox(width: AppDimensions.spaceMd),
            Expanded(child: Text(label, style: AppTextStyles.body.copyWith(color: color))),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.holographicBlue, size: 20),
          ],
        ),
      ),
    );
  }
}
