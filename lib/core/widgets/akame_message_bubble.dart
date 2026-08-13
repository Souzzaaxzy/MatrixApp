import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import 'glow_container.dart';

/// Chat bubble used in the Akame conversation.
///
/// User messages align right (primary blue), Akame messages align left
/// (holographic blue) with a glow.
class AkameMessageBubble extends StatelessWidget {
  const AkameMessageBubble({
    super.key,
    required this.text,
    required this.fromUser,
    this.timestamp,
  });

  final String text;
  final bool fromUser;
  final String? timestamp;

  @override
  Widget build(BuildContext context) {
    final alignment =
        fromUser ? Alignment.centerRight : Alignment.centerLeft;
    final bubble = Column(
      crossAxisAlignment:
          fromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlowContainer(
          glow: fromUser ? Glow.none : Glow.small,
          color: fromUser ? AppColors.glowSmall : AppColors.glowSmall,
          background: fromUser ? AppColors.primaryBlue : AppColors.nightBlue,
          border: fromUser
              ? null
              : Border.all(
                  color: AppColors.electricBlue.withValues(alpha: 0.4),
                  width: AppDimensions.borderWidthThin,
                ),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppDimensions.radiusLg),
            topRight: const Radius.circular(AppDimensions.radiusLg),
            bottomLeft: Radius.circular(fromUser ? AppDimensions.radiusLg : 4),
            bottomRight: Radius.circular(fromUser ? 4 : AppDimensions.radiusLg),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spaceLg,
            vertical: AppDimensions.spaceMd,
          ),
          child: Text(
            text,
            style: AppTextStyles.body.copyWith(
              color: AppColors.techWhite,
              height: 1.4,
            ),
          ),
        ),
        if (timestamp != null) ...[
          const SizedBox(height: AppDimensions.spaceXs),
          Text(timestamp!, style: AppTextStyles.hud.copyWith(fontSize: 10)),
        ],
      ],
    );

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: bubble,
      ),
    );
  }
}
