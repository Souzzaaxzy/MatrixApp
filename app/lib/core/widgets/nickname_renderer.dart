import 'package:flutter/material.dart';

import '../../app/theme/app_text_styles.dart';
import '../utils/name_colors.dart';

/// Central nickname renderer — the ONE place that applies a user's nickname
/// color to real TEXT.
///
/// Every surface (feed, comments, profile, activities/notifications,
/// search, friends, preview) renders nicknames through this widget so the
/// color resolution (owner's color + contrast guard) is never duplicated
/// per screen. The nickname is plain, static text rendered EXACTLY as
/// stored (Unicode, emojis, symbols) — Flutter's Text renders it as text,
/// never as HTML, so no escaping/XSS concerns apply.
///
/// Performance: this widget is STATELESS. There are no animations, no
/// AnimationController, no Ticker, no Timer and no observers — nothing
/// keeps running in the background for nicknames.
class NicknameRenderer extends StatelessWidget {
  const NicknameRenderer(
    this.text, {
    super.key,
    this.nameColor,
    this.background,
    this.baseStyle,
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
  });

  final String text;

  /// The OWNER's nickname color (hex) — never the viewer's.
  final String? nameColor;

  /// Surface behind the text, for the contrast guard.
  final Color? background;

  final TextStyle? baseStyle;
  final TextAlign textAlign;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final base = baseStyle ?? AppTextStyles.h3;
    final surface = background ?? Theme.of(context).cardColor;
    // Contrast guard: the owner's color is never altered; if it would be
    // invisible on this surface, the theme default is used instead.
    final color = resolveNameColor(nameColor, surface) ?? base.color;
    return Text(
      text,
      style: base.copyWith(color: color),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
