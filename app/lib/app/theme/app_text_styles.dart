import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Centralized text styles for MATRIX.
///
/// UI uses Inter (bundled), technical/HUD elements use JetBrains Mono
/// (bundled). Fonts are shipped as assets so the app renders identically
/// offline and in tests.
class AppTextStyles {
  AppTextStyles._();

  static const String uiFont = 'Inter';
  static const String monoFont = 'JetBrainsMono';

  static const TextStyle display = TextStyle(
    fontFamily: uiFont,
    fontWeight: FontWeight.w900,
    color: AppColors.techWhite,
    letterSpacing: 4,
    fontSize: 32,
  );

  static const TextStyle h1 = TextStyle(
    fontFamily: uiFont,
    fontWeight: FontWeight.w800,
    color: AppColors.techWhite,
    fontSize: 26,
    letterSpacing: 0.5,
  );

  static const TextStyle h2 = TextStyle(
    fontFamily: uiFont,
    fontWeight: FontWeight.w700,
    color: AppColors.techWhite,
    fontSize: 20,
  );

  static const TextStyle h3 = TextStyle(
    fontFamily: uiFont,
    fontWeight: FontWeight.w700,
    color: AppColors.techWhite,
    fontSize: 17,
  );

  static const TextStyle title = TextStyle(
    fontFamily: uiFont,
    fontWeight: FontWeight.w800,
    color: AppColors.techWhite,
    fontSize: 18,
    letterSpacing: 2,
  );

  static const TextStyle body = TextStyle(
    fontFamily: uiFont,
    fontWeight: FontWeight.w400,
    color: AppColors.techWhite,
    fontSize: 15,
    height: 1.5,
  );

  static const TextStyle bodyMuted = TextStyle(
    fontFamily: uiFont,
    fontWeight: FontWeight.w400,
    color: AppColors.holographicBlue,
    fontSize: 14,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: uiFont,
    fontWeight: FontWeight.w500,
    color: AppColors.holographicBlue,
    fontSize: 12,
  );

  static const TextStyle label = TextStyle(
    fontFamily: uiFont,
    fontWeight: FontWeight.w600,
    color: AppColors.holographicBlue,
    fontSize: 13,
    letterSpacing: 0.5,
  );

  /// HUD / technical uppercase labels.
  static const TextStyle hud = TextStyle(
    fontFamily: monoFont,
    fontWeight: FontWeight.w600,
    color: AppColors.holographicBlue,
    fontSize: 11,
    letterSpacing: 2,
  );

  static const TextStyle hudActive = TextStyle(
    fontFamily: monoFont,
    fontWeight: FontWeight.w700,
    color: AppColors.electricBlue,
    fontSize: 11,
    letterSpacing: 2,
  );

  static const TextStyle hudMono = TextStyle(
    fontFamily: monoFont,
    fontWeight: FontWeight.w500,
    color: AppColors.techWhite,
    fontSize: 13,
  );

  static const TextStyle button = TextStyle(
    fontFamily: uiFont,
    fontWeight: FontWeight.w700,
    color: AppColors.techWhite,
    fontSize: 15,
    letterSpacing: 1.5,
  );
}
