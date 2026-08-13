import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

/// Circular icon button with a subtle neon border.
class NeonIconButton extends StatelessWidget {
  const NeonIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 44,
    this.color = AppColors.electricBlue,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Semantics(
      label: semanticLabel,
      button: true,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.bluishBlack,
              border: Border.all(
                color: disabled ? AppColors.deepBlue : color,
                width: AppDimensions.borderWidthThin,
              ),
              boxShadow: disabled
                  ? null
                  : [
                      BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: AppDimensions.glowSmallBlur,
                      ),
                    ],
            ),
            child: Icon(icon, color: disabled ? AppColors.deepBlue : color, size: size * 0.45),
          ),
        ),
      ),
    );
  }
}
