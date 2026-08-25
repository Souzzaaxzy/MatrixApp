import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Centralized text styles for MATRIX.
///
/// UI uses Inter (bundled), technical/HUD elements use JetBrains Mono
/// (bundled). Fonts are shipped as assets so the app renders identically
/// offline and in tests.
///
/// Colors follow the ACTIVE palette (see [AppColors.setActive]) so the same
/// style names render correctly in both dark and light themes.
class AppTextStyles {
  AppTextStyles._();

  static const String uiFont = 'Inter';
  static const String monoFont = 'JetBrainsMono';

  static TextStyle get display => TextStyle(
        fontFamily: uiFont,
        fontWeight: FontWeight.w900,
        color: AppColors.techWhite,
        letterSpacing: 4,
        fontSize: 32,
      );

  static TextStyle get h1 => TextStyle(
        fontFamily: uiFont,
        fontWeight: FontWeight.w800,
        color: AppColors.techWhite,
        fontSize: 26,
        letterSpacing: 0.5,
      );

  static TextStyle get h2 => TextStyle(
        fontFamily: uiFont,
        fontWeight: FontWeight.w700,
        color: AppColors.techWhite,
        fontSize: 20,
      );

  static TextStyle get h3 => TextStyle(
        fontFamily: uiFont,
        fontWeight: FontWeight.w700,
        color: AppColors.techWhite,
        fontSize: 17,
      );

  static TextStyle get title => TextStyle(
        fontFamily: uiFont,
        fontWeight: FontWeight.w800,
        color: AppColors.techWhite,
        fontSize: 18,
        letterSpacing: 2,
      );

  static TextStyle get body => TextStyle(
        fontFamily: uiFont,
        fontWeight: FontWeight.w400,
        color: AppColors.techWhite,
        fontSize: 15,
        height: 1.5,
      );

  static TextStyle get bodyMuted => TextStyle(
        fontFamily: uiFont,
        fontWeight: FontWeight.w400,
        color: AppColors.holographicBlue,
        fontSize: 14,
      );

  static TextStyle get caption => TextStyle(
        fontFamily: uiFont,
        fontWeight: FontWeight.w500,
        color: AppColors.holographicBlue,
        fontSize: 12,
      );

  static TextStyle get label => TextStyle(
        fontFamily: uiFont,
        fontWeight: FontWeight.w600,
        color: AppColors.holographicBlue,
        fontSize: 13,
        letterSpacing: 0.5,
      );

  /// HUD / technical uppercase labels.
  static TextStyle get hud => TextStyle(
        fontFamily: monoFont,
        fontWeight: FontWeight.w600,
        color: AppColors.holographicBlue,
        fontSize: 11,
        letterSpacing: 2,
      );

  static TextStyle get hudActive => const TextStyle(
        fontFamily: monoFont,
        fontWeight: FontWeight.w700,
        color: AppColors.electricBlue,
        fontSize: 11,
        letterSpacing: 2,
      );

  static TextStyle get hudMono => TextStyle(
        fontFamily: monoFont,
        fontWeight: FontWeight.w500,
        color: AppColors.techWhite,
        fontSize: 13,
      );

  static TextStyle get button => TextStyle(
        fontFamily: uiFont,
        fontWeight: FontWeight.w700,
        color: AppColors.techWhite,
        fontSize: 15,
        letterSpacing: 1.5,
      );
}
