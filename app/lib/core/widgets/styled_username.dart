import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../../models/cosmetic_item.dart';
import '../utils/name_colors.dart';

/// Display-name renderer with optional name cosmetics applied.
///
/// NAME_COLOR: a solid text color owned by the server palette — rendered
/// directly by the text component (no shadows/glow/effects). A contrast
/// guard keeps the nickname readable on the active theme surface; when the
/// color would be nearly invisible the default theme color is used.
///
/// PROFILE_EFFECT (future): the equipped [effect] adds a neon glow today;
/// the style pipeline is a single place ([_styleFor]) so new effects are a
/// data + style entry, not a refactor of the profile screens.
class StyledUsername extends StatelessWidget {
  const StyledUsername(
    this.text, {
    super.key,
    this.effect,
    this.nameColor,
    this.baseStyle,
    this.textAlign = TextAlign.center,
  });

  final String text;

  /// Equipped PROFILE_EFFECT cosmetic, or null for the default style.
  final CosmeticItem? effect;

  /// The OWNER's nickname color (hex, e.g. "#0066FF"), or null for the
  /// default MATRIX color. Never the viewer's color.
  final String? nameColor;

  /// Base text style when no effect is equipped (defaults to the profile
  /// display-name style).
  final TextStyle? baseStyle;

  final TextAlign textAlign;

  TextStyle _styleFor(BuildContext context) {
    final base = baseStyle ?? AppTextStyles.h2;
    var style = base;
    // A name color replaces only the text color — never adds effects.
    final color = resolveNameColor(nameColor, AppColors.cardSurface);
    if (color != null) {
      style = style.copyWith(color: color);
    }
    if (effect == null) return style;
    // Placeholder effect: neon glow. Real effect rendering (gradient,
    // glitch, animation) plugs in here keyed by effect.id / assetUrl.
    return style.copyWith(
      shadows: [
        Shadow(color: style.color ?? Colors.white, blurRadius: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: _styleFor(context),
      textAlign: textAlign,
      overflow: TextOverflow.ellipsis,
    );
  }
}
