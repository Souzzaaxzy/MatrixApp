import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

/// Surface card used for feed, chat and profile blocks.
class MatrixCard extends StatelessWidget {
  const MatrixCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppDimensions.spaceLg),
    this.margin,
    this.borderRadius,
    this.background,
    this.border,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final Color? background;
  final Border? border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius =
        borderRadius ?? BorderRadius.circular(AppDimensions.radiusLg);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: background ?? AppColors.bluishBlack,
        borderRadius: radius,
        border: border ??
            Border.all(
              color: AppColors.deepBlue.withValues(alpha: 0.5),
              width: AppDimensions.borderWidthThin,
            ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
