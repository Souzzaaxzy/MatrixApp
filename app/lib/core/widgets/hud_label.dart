import 'package:flutter/widgets.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import 'glow_container.dart';

/// Small uppercase HUD label with an optional status dot.
class HudLabel extends StatelessWidget {
  const HudLabel({
    super.key,
    required this.text,
    this.color,
    this.dot = false,
    this.glow = false,
  });

  final String text;
  final Color? color;
  final bool dot;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? AppColors.holographicBlue;
    final style = AppTextStyles.hud.copyWith(color: color);
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color, blurRadius: 6),
              ],
            ),
          ),
          const SizedBox(width: AppDimensions.spaceSm),
        ],
        Text(text.toUpperCase(), style: style),
      ],
    );

    if (!glow) return label;

    return GlowContainer(
      glow: Glow.small,
      color: color.withValues(alpha: 0.25),
      background: color.withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spaceMd,
        vertical: AppDimensions.spaceXs,
      ),
      borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
      child: label,
    );
  }
}
