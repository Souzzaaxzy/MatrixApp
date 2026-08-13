import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import 'matrix_button.dart';

/// Reusable visual error block. Red is reserved for destructive alerts.
class MatrixError extends StatelessWidget {
  const MatrixError({
    super.key,
    required this.message,
    this.title = 'SYSTEM ERROR',
    this.onRetry,
  });

  final String message;
  final String title;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spaceXxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.error, size: 48),
            const SizedBox(height: AppDimensions.spaceLg),
            Text(title, style: AppTextStyles.hud.copyWith(color: AppColors.error)),
            const SizedBox(height: AppDimensions.spaceSm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMuted,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppDimensions.spaceXl),
              MatrixButton(
                label: 'Tentar novamente',
                variant: MatrixButtonVariant.outline,
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
