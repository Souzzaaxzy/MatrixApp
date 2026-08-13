import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import 'glow_container.dart';

/// Primary MATRIX button with neon glow.
///
/// Use [variant] to switch between filled, outline and ghost styles.
class MatrixButton extends StatefulWidget {
  const MatrixButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = MatrixButtonVariant.filled,
    this.isLoading = false,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final MatrixButtonVariant variant;
  final bool isLoading;
  final bool expanded;

  @override
  State<MatrixButton> createState() => _MatrixButtonState();
}

class _MatrixButtonState extends State<MatrixButton> {
  bool _hovering = false;
  bool _pressing = false;

  bool get _disabled => widget.onPressed == null || widget.isLoading;

  @override
  Widget build(BuildContext context) {
    final isOutline = widget.variant == MatrixButtonVariant.outline;
    final isGhost = widget.variant == MatrixButtonVariant.ghost;

    final borderColor = isGhost
        ? Colors.transparent
        : _disabled
            ? AppColors.deepBlue
            : AppColors.primaryBlue;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressing = true),
        onTapUp: (_) => setState(() => _pressing = false),
        onTapCancel: () => setState(() => _pressing = false),
        onTap: _disabled ? null : widget.onPressed,
        child: AnimatedScale(
          scale: _pressing ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: GlowContainer(
            glow: (_hovering && !_disabled) ? Glow.medium : Glow.none,
            background: isOutline || isGhost
                ? Colors.transparent
                : _disabled
                    ? AppColors.deepBlue.withValues(alpha: 0.5)
                    : AppColors.primaryBlue,
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            border: isGhost
                ? null
                : Border.all(color: borderColor, width: AppDimensions.borderWidthActive),
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.spaceXl,
              vertical: AppDimensions.spaceLg,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: widget.expanded ? double.infinity : 0,
              ),
              child: Row(
                mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 18, color: AppColors.techWhite),
                    const SizedBox(width: AppDimensions.spaceSm),
                  ],
                  if (widget.isLoading)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(AppColors.techWhite),
                      ),
                    )
                  else
                    Text(
                      widget.label.toUpperCase(),
                      style: AppTextStyles.button,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum MatrixButtonVariant { filled, outline, ghost }
