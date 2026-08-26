import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../models/cosmetic_item.dart';

/// Renders the equipped BADGE cosmetic next to a nickname.
///
/// Returns an empty box when [badge] is null (nothing equipped), so call
/// sites can place it unconditionally. Real badge art (Founder, Verified,
/// MATRIX+, ...) plugs in via [CosmeticItem.assetUrl]; until then a neon
/// chip with the item name is shown.
class CosmeticBadgeView extends StatelessWidget {
  const CosmeticBadgeView({super.key, this.badge});

  final CosmeticItem? badge;

  @override
  Widget build(BuildContext context) {
    final badge = this.badge;
    if (badge == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spaceSm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.nightBlue,
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        border: Border.all(color: AppColors.electricBlue),
        boxShadow: [
          BoxShadow(color: AppColors.glowSmall, blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_rounded,
              size: 12, color: AppColors.electricBlue),
          const SizedBox(width: 4),
          Text(
            badge.name.toUpperCase(),
            style: AppTextStyles.hud.copyWith(fontSize: 9),
          ),
        ],
      ),
    );
  }
}
