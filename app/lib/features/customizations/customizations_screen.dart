import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/app_state_scope.dart';
import 'widgets/profile_customization_preview.dart';

/// Profile customizations screen (Personalizações).
///
/// Infrastructure phase: the preview and the slot structure are live and
/// driven by the server-owned cosmetic state, but the cosmetic catalog
/// itself (frames, name effects, badges) ships in the next update — each
/// section shows "Em breve" until then.
class CustomizationsScreen extends StatefulWidget {
  const CustomizationsScreen({super.key});

  @override
  State<CustomizationsScreen> createState() => _CustomizationsScreenState();
}

class _CustomizationsScreenState extends State<CustomizationsScreen> {
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppStateScope.of() cannot run in initState (inherited dependency),
    // and loadMyCosmetics notifies listeners — so schedule it post-frame,
    // never during the build phase.
    if (!_requested) {
      _requested = true;
      final state = AppStateScope.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        state.loadMyCosmetics();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final user = state.currentUser;
    if (user == null) {
      return Scaffold(backgroundColor: AppColors.absoluteBlack);
    }
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
            ),
            const SizedBox(height: AppDimensions.spaceLg),
            const Divider(height: AppDimensions.spaceXxl),
            const _CosmeticSection(
              icon: Icons.crop_free_rounded,
              title: 'Moldura',
            ),
            const _CosmeticSection(
              icon: Icons.auto_awesome_rounded,
              title: 'Nome',
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

/// A cosmetic category row. Placeholder ("Em breve") until the catalog
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
