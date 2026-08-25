import 'package:flutter/material.dart';

import '../../core/services/theme_controller.dart';

/// Resolves which palette is ACTIVE for a given preference + platform
/// brightness. Pure function so the resolution rule is unit-testable.
MatrixPalette effectivePalette(MatrixThemeMode mode, Brightness platform) {
  return switch (mode) {
    MatrixThemeMode.dark => MatrixPalette.dark,
    MatrixThemeMode.light => MatrixPalette.light,
    MatrixThemeMode.system =>
      platform == Brightness.dark ? MatrixPalette.dark : MatrixPalette.light,
  };
}

/// Per-theme color tokens for the mood-dependent part of the MATRIX
/// identity (brand blues are shared and stay in [AppColors]).
///
/// `dark` is the original cyberpunk MATRIX look; `light` is a designed
/// light variant — white surfaces, dark text and the same blue accent,
/// with borders/shadows tuned for a bright background (not an inversion).
class MatrixPalette {
  const MatrixPalette({
    required this.scaffold,
    required this.surface,
    required this.surfaceDeep,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.navBar,
    required this.glowAlpha,
  });

  final Color scaffold;
  final Color surface;
  final Color surfaceDeep;
  final Color border;
  final Color text;
  final Color textMuted;
  final Color navBar;

  /// Alpha of the neon glow emphasis: strong on dark, subtle on light.
  final double glowAlpha;

  static const dark = MatrixPalette(
    scaffold: Color(0xFF000000),
    surface: Color(0xFF050914),
    surfaceDeep: Color(0xFF00142E),
    border: Color(0xFF003B8F),
    text: Color(0xFFEAF4FF),
    textMuted: Color(0xFF6EB6FF),
    navBar: Color(0xF2000512),
    glowAlpha: 1.0,
  );

  static const light = MatrixPalette(
    scaffold: Color(0xFFF4F7FC),
    surface: Color(0xFFFFFFFF),
    surfaceDeep: Color(0xFFE3EDFA),
    border: Color(0xFFB9CCE8),
    text: Color(0xFF0B1524),
    textMuted: Color(0xFF3A4F6B),
    navBar: Color(0xF2FFFFFF),
    glowAlpha: 0.25,
  );
}
