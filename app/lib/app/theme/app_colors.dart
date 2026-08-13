import 'package:flutter/material.dart';

/// Centralized MATRIX design tokens.
///
/// Cyber Blue palette. Distribution target: ~70% black/deep dark,
/// ~20% deep blue, ~10% neon blue / white.
class AppColors {
  AppColors._();

  // Brand blues
  static const Color primaryBlue = Color(0xFF0066FF);
  static const Color electricBlue = Color(0xFF008CFF);
  static const Color deepBlue = Color(0xFF003B8F);
  static const Color nightBlue = Color(0xFF00142E);

  // Surfaces
  static const Color absoluteBlack = Color(0xFF000000);
  static const Color bluishBlack = Color(0xFF050914);

  // Text
  static const Color techWhite = Color(0xFFEAF4FF);
  static const Color holographicBlue = Color(0xFF6EB6FF);

  // Status
  static const Color success = Color(0xFF00FF88);
  static const Color error = Color(0xFFFF304F);

  // Glow presets (rgba of primary/electric blue).
  static const Color glowSmall = Color(0x730066FF); // 0.45 alpha
  static const Color glowMedium = Color(0x8C0066FF); // 0.55 alpha
  static const Color glowStrong = Color(0xBF008CFF); // 0.75 alpha

  // Convenience surface helpers.
  static const Color cardSurface = bluishBlack;
  static const Color scaffoldBackground = absoluteBlack;
  static const Color navBarBackground = Color(0xF2000512);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryBlue, deepBlue],
  );

  static const LinearGradient deepGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [nightBlue, absoluteBlack],
  );

  static const LinearGradient akameGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [electricBlue, holographicBlue],
  );
}
