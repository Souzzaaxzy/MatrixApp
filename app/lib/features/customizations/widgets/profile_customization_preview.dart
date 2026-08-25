import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/cosmetic_badge.dart';
import '../../../core/widgets/framed_avatar.dart';
import '../../../core/widgets/styled_username.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../models/cosmetic_item.dart';
import '../../../models/matrix_user.dart';

/// Live profile preview used by the customizations screen.
///
/// Renders the user exactly the way the (future) real cosmetics pipeline
/// will: every cosmetic slot maps to an isolated renderer component —
///
///   ProfileCustomizationPreview
///    ├── FramedAvatar        (AVATAR_FRAME slot → frame overlay)
///    │    └── UserAvatar
///    ├── StyledUsername      (PROFILE_EFFECT slot → name style/effect)
///    └── CosmeticBadgeView   (BADGE slot)
///
/// With no cosmetics equipped the preview shows the default profile look.
class ProfileCustomizationPreview extends StatelessWidget {
  const ProfileCustomizationPreview({
    super.key,
    required this.user,
    this.cosmetics = const {},
    this.nameColorOverride,
  });

  final MatrixUser user;

  /// Equipped cosmetics keyed by slot (empty = all defaults).
  final CosmeticMap cosmetics;

  /// Preview-only nickname color (hex) for a selection that was not saved
  /// yet. When null, the equipped NAME_COLOR (or the user's own color) is
  /// used. Pass an empty string to preview the DEFAULT color explicitly.
  final String? nameColorOverride;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: AppDimensions.spaceXxl,
        horizontal: AppDimensions.spaceLg,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
        border: Border.all(color: AppColors.deepBlue),
        boxShadow: [
          BoxShadow(color: AppColors.glowSmall, blurRadius: 18),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('PRÉ-VISUALIZAÇÃO', style: AppTextStyles.hud),
          const SizedBox(height: AppDimensions.spaceLg),
          FramedAvatar(
            frame: cosmetics[CosmeticItem.avatarFrame],
            size: 110,
            child: UserAvatar(
              name: user.name,
              seed: user.avatarSeed ?? user.username,
              imageUrl: user.avatarUrl,
              size: 98,
            ),
          ),
          const SizedBox(height: AppDimensions.spaceMd),
          StyledUsername(
            user.name,
            effect: cosmetics[CosmeticItem.profileEffect],
            nameColor: nameColorOverride != null
                ? (nameColorOverride!.isEmpty ? null : nameColorOverride)
                : (cosmetics[CosmeticItem.nameColor]?.hexColor ??
                    user.nameColor),
          ),
          const SizedBox(height: AppDimensions.spaceXs),
          Text('@${user.username}', style: AppTextStyles.caption),
          const SizedBox(height: AppDimensions.spaceSm),
          CosmeticBadgeView(badge: cosmetics[CosmeticItem.badge]),
        ],
      ),
    );
  }
}
