import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import 'glow_container.dart';

/// Decorative MATRIX empty state.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.grid_view_rounded,
    this.hud,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String? hud;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spaceXxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlowContainer(
              glow: Glow.medium,
              color: AppColors.glowSmall,
              background: AppColors.primaryBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
              padding: const EdgeInsets.all(AppDimensions.spaceXl),
              child: Icon(icon, color: AppColors.electricBlue, size: 40),
            ),
            const SizedBox(height: AppDimensions.spaceXl),
            if (hud != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppDimensions.spaceSm),
                child: Text(hud!, style: AppTextStyles.hud),
              ),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.h2,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppDimensions.spaceSm),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
