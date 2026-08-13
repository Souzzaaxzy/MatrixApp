import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

/// Global MATRIX theme applied to the whole app.
class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primaryBlue,
        onPrimary: AppColors.techWhite,
        secondary: AppColors.electricBlue,
        onSecondary: AppColors.techWhite,
        error: AppColors.error,
        surface: AppColors.bluishBlack,
        onSurface: AppColors.techWhite,
      ),
      scaffoldBackgroundColor: AppColors.absoluteBlack,
      canvasColor: AppColors.bluishBlack,
      splashFactory: InkSparkle.splashFactory,
      textTheme: base.textTheme.copyWith(
        bodyLarge: AppTextStyles.body,
        bodyMedium: AppTextStyles.body,
        bodySmall: AppTextStyles.caption,
        titleLarge: AppTextStyles.h2,
        titleMedium: AppTextStyles.h3,
        labelLarge: AppTextStyles.button,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.absoluteBlack,
        foregroundColor: AppColors.techWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTextStyles.h2,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bluishBlack,
        hintStyle: AppTextStyles.bodyMuted,
        labelStyle: AppTextStyles.label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: _border(AppColors.deepBlue),
        enabledBorder: _border(AppColors.deepBlue),
        focusedBorder: _border(AppColors.primaryBlue),
        errorBorder: _border(AppColors.error),
        focusedErrorBorder: _border(AppColors.error),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: AppColors.techWhite,
          textStyle: AppTextStyles.button,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.techWhite),
      dividerColor: AppColors.deepBlue.withValues(alpha: 0.4),
      splashColor: AppColors.primaryBlue.withValues(alpha: 0.12),
      highlightColor: AppColors.primaryBlue.withValues(alpha: 0.06),
    );
  }

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: 1),
      );
}
