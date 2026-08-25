import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Centralized MATRIX design tokens.
///
/// Brand colors are theme-independent statics. Mood-dependent tokens
/// (backgrounds, surfaces, text) resolve through the currently ACTIVE
/// palette, swapped by [setActive] when the theme resolves (dark/light).
/// Widgets keep reading `AppColors.x` exactly as before — the palette swap
/// rebuilds the tree because [ThemeController] notifies the root.
class AppColors {
  AppColors._();

  // Active palette (theme-dependent). Defaults to dark, the classic MATRIX.
  static MatrixPalette _active = MatrixPalette.dark;

  static void setActive(MatrixPalette palette) {
    if (_active != palette) _active = palette;
  }

  /// Currently active palette (used by tests to verify theme resolution).
  static MatrixPalette get activePalette => _active;

  // Brand blues — same across themes.
  static const Color primaryBlue = Color(0xFF0066FF);
  static const Color electricBlue = Color(0xFF008CFF);
  static const Color success = Color(0xFF00FF88);
  static const Color error = Color(0xFFFF304F);

  // Theme-dependent tokens.
  static Color get absoluteBlack => _active.scaffold;
  static Color get bluishBlack => _active.surface;
  static Color get nightBlue => _active.surfaceDeep;
  static Color get deepBlue => _active.border;
  static Color get techWhite => _active.text;
  static Color get holographicBlue => _active.textMuted;
  static Color get cardSurface => _active.surface;
  static Color get scaffoldBackground => _active.scaffold;
  static Color get navBarBackground => _active.navBar;

  // Glow presets. Translucent brand blue; softer on the light theme.
  static Color get glowSmall => primaryBlue.withValues(alpha: 0.45 * _active.glowAlpha);
  static Color get glowMedium => primaryBlue.withValues(alpha: 0.55 * _active.glowAlpha);
  static Color get glowStrong => electricBlue.withValues(alpha: 0.75 * _active.glowAlpha);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryBlue, Color(0xFF003B8F)],
  );

  static LinearGradient get deepGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_active.surfaceDeep, _active.scaffold],
      );

  static const LinearGradient akameGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [electricBlue, Color(0xFF6EB6FF)],
  );
}
