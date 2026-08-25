import 'package:flutter/material.dart';

/// Nickname color resolution.
///
/// The server owns the palette (NAME_COLOR catalog items carry the hex in
/// their assetUrl); the app only parses and renders it. A color is NEVER
/// swapped for another color and never "fixed" with shadows/glow — the
/// only accessibility rule is a contrast guard: when the chosen color
/// would be nearly invisible against the current surface, the nickname
/// falls back to the theme default text color for THAT surface.
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var value = hex.trim();
  if (value.startsWith('#')) value = value.substring(1);
  if (value.length == 6) value = 'FF$value';
  if (value.length != 8) return null;
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}

/// Minimum WCAG contrast ratio between the nickname color and the surface
/// behind it. Below this the nickname would be hard to read (e.g. white on
/// the light theme, pure black on the dark theme).
const double kMinNameContrast = 1.6;

/// Resolves the color a nickname should use on [background].
///
/// Returns null when there is no customization OR when the customized
/// color fails the contrast guard — in both cases the caller keeps its
/// default theme color. The chosen color itself is never altered.
Color? resolveNameColor(String? hex, Color background) {
  final color = parseHexColor(hex);
  if (color == null) return null;
  final ratio = (color.computeLuminance() + 0.05) /
      (background.computeLuminance() + 0.05);
  final contrast = ratio >= 1 ? ratio : 1 / ratio;
  return contrast < kMinNameContrast ? null : color;
}
