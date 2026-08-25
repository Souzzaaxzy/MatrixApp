import 'package:flutter/material.dart';

import '../../app/theme/app_text_styles.dart';
import '../../models/cosmetic_item.dart';

/// Display-name renderer with an optional name cosmetic applied.
///
/// Prepared for the future name cosmetics (Neon / Gradient / Glitch /
/// Rainbow / ...): today an equipped [effect] adds a neon glow; the style
/// pipeline is a single place ([_styleFor]) so new effects are a data +
/// style entry, not a refactor of the profile screens.
class StyledUsername extends StatelessWidget {
  const StyledUsername(
    this.text, {
    super.key,
    this.effect,
    this.baseStyle,
  });

  final String text;

  /// Equipped PROFILE_EFFECT cosmetic, or null for the default style.
  final CosmeticItem? effect;

  /// Base text style when no effect is equipped (defaults to the profile
  /// display-name style).
  final TextStyle? baseStyle;

  TextStyle _styleFor(CosmeticItem? effect) {
    final base = baseStyle ?? AppTextStyles.h2;
    if (effect == null) return base;
    // Placeholder effect: neon glow. Real effect rendering (gradient,
    // glitch, animation) plugs in here keyed by effect.id / assetUrl.
    return base.copyWith(
      shadows: [
        Shadow(color: base.color ?? Colors.white, blurRadius: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: _styleFor(effect),
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
    );
  }
}
