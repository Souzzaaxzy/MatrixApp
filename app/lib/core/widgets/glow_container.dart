import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

/// A container that adds a soft neon glow via [BoxShadow].
///
/// Glow intensity follows the MATRIX spec and should be reserved for
/// important elements only.
class GlowContainer extends StatelessWidget {
  const GlowContainer({
    super.key,
    required this.child,
    this.glow = Glow.small,
    this.color,
    this.padding,
    this.borderRadius,
    this.border,
    this.background,
    this.gradient,
  });

  final Widget child;
  final Glow glow;
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Border? border;
  final Color? background;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final glowColor = color ?? _defaultColor();
    final blur = switch (glow) {
      Glow.small => AppDimensions.glowSmallBlur,
      Glow.medium => AppDimensions.glowMediumBlur,
      Glow.strong => AppDimensions.glowStrongBlur,
      Glow.none => 0.0,
    };

    final radius = borderRadius ?? BorderRadius.circular(AppDimensions.radiusMd);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        gradient: gradient,
        borderRadius: radius,
        border: border,
        boxShadow: glow == Glow.none
            ? null
            : [
                BoxShadow(
                  color: glowColor,
                  blurRadius: blur,
                  spreadRadius: 0,
                ),
              ],
      ),
      child: child,
    );
  }

  Color _defaultColor() => switch (glow) {
        Glow.small => AppColors.glowSmall,
        Glow.medium => AppColors.glowMedium,
        Glow.strong => AppColors.glowStrong,
        Glow.none => Colors.transparent,
      };
}

enum Glow { none, small, medium, strong }
