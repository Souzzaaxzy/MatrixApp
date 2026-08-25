import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_text_styles.dart';
import '../../models/name_effect.dart';
import '../utils/name_colors.dart';

/// Central nickname renderer — the ONE place that applies a user's nickname
/// cosmetics (nameColor + nameEffect) to real TEXT.
///
/// Every surface (feed, comments, profile, activities/notifications,
/// search, friends, preview) must render nicknames through this widget so
/// effects are never duplicated per screen. The nickname stays real,
/// selectable text — effects are purely visual overlays/animations.
///
/// Performance: animations run on a single ticker per nickname, driven by
/// the effect's server-provided `speed`; a [lightweight] mode (used by long
/// lists) disables particles and reduces the animation to a static glow so
/// dozens of animated nicknames never hurt scrolling.
class NicknameRenderer extends StatefulWidget {
  const NicknameRenderer(
    this.text, {
    super.key,
    this.nameColor,
    this.effect,
    this.background,
    this.baseStyle,
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
    this.lightweight = false,
  });

  final String text;

  /// The OWNER's nickname color (hex) — never the viewer's.
  final String? nameColor;

  /// The OWNER's nickname effect (server catalog entry). Null → "Nenhum":
  /// the color still applies, with no animation.
  final NameEffect? effect;

  /// Surface behind the text, for the contrast guard.
  final Color? background;

  final TextStyle? baseStyle;
  final TextAlign textAlign;
  final int maxLines;

  /// Disables particles and heavy animations (long lists: feed, comments).
  final bool lightweight;

  @override
  State<NicknameRenderer> createState() => _NicknameRendererState();
}

class _NicknameRendererState extends State<NicknameRenderer>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  bool get _animated {
    final effect = widget.effect;
    if (effect == null) return false;
    if (_kind(effect) != _EffectKind.staticGlow) return true;
    // Static glows still animate when they spawn particles (star_glow,
    // cosmic, ...) so the particle field moves.
    return effect.particles && !widget.lightweight;
  }

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(NicknameRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effect?.id != widget.effect?.id ||
        oldWidget.lightweight != widget.lightweight) {
      _syncController();
    }
  }

  void _syncController() {
    if (_animated) {
      final speed = widget.effect?.speed ?? 1;
      _controller ??= AnimationController(vsync: this)..addListener(_tick);
      _controller!.duration = Duration(
        milliseconds: (2400 / speed.clamp(0.2, 4)).round(),
      );
      if (!_controller!.isAnimating) _controller!.repeat();
    } else {
      _controller?.dispose();
      _controller = null;
    }
  }

  // Rebuilds are cheap (a Text + small stacks); the listener keeps the
  // animation self-contained instead of wrapping everything in an
  // AnimatedBuilder at every call site.
  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.baseStyle ?? AppTextStyles.h3;
    final surface = widget.background ?? Theme.of(context).cardColor;
    // Contrast guard: the owner's color is never altered; if it would be
    // invisible on this surface, the theme default is used instead.
    final color = resolveNameColor(widget.nameColor, surface) ?? base.color;
    final effect = widget.effect;
    final t = _controller?.value ?? 0;

    final TextStyle style;
    if (effect == null) {
      style = base.copyWith(color: color);
    } else {
      style = _styled(base, color ?? Colors.white, effect, t);
    }

    Widget child = Text(
      widget.text,
      style: style,
      textAlign: widget.textAlign,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
    );

    if (effect == null) return child;

    switch (_kind(effect)) {
      case _EffectKind.staticGlow:
        return child;
      case _EffectKind.glitch:
        child = _GlitchWrap(t: t, child: child);
        break;
      case _EffectKind.gradient:
        child = _GradientText(t: t, effect: effect, style: style, child: child);
        break;
      case _EffectKind.float:
        child = Transform.translate(
          offset: Offset(0, -2 * math.sin(t * 2 * math.pi)),
          child: child,
        );
        break;
      case _EffectKind.wave:
        child = _GradientText(
          t: t,
          effect: effect,
          style: style,
          sliding: true,
          child: child,
        );
        break;
      case _EffectKind.pulse:
        // Already encoded in the animated shadow of _styled.
        break;
    }

    // Particle overlay (cosmic/fire/premium/dark effects) — skipped in
    // lightweight list mode to keep scrolling fluid.
    if (effect.particles && !widget.lightweight) {
      child = Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ParticlesPainter(
                  t: t,
                  color: _accentColor(effect, color ?? Colors.white),
                  intensity: effect.intensity,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return child;
  }
}

enum _EffectKind { staticGlow, pulse, glitch, gradient, float, wave }

/// Maps the server-owned animation key to a render strategy. Families
/// share strategies (all glows → static/pulse glow; all glitches → glitch;
/// color/elemental/premium gradients → gradient), so new catalog ids work
/// without code changes whenever their `animation` key is one of these.
_EffectKind _kind(NameEffect effect) {
  switch (effect.animation) {
    case 'pulse':
    case 'breathing':
    case 'neon_pulse':
    case 'flicker':
    case 'cyber_pulse':
    case 'blackout':
    case 'eclipse':
      return _EffectKind.pulse;
    case 'glitch':
    case 'digital_glitch':
    case 'screen_glitch':
    case 'error':
    case 'corrupted':
    case 'rgb_glitch':
    case 'chromatic_glitch':
    case 'signal_lost':
    case 'digital_noise':
    case 'cyber_glitch':
    case 'dark_glitch':
      return _EffectKind.glitch;
    case 'float':
      return _EffectKind.float;
    case 'wave':
    case 'shimmer':
    case 'reflection':
    case 'cyber_wave':
    case 'scanline':
      return _EffectKind.wave;
    default:
      // Color-cycling, elemental and premium effects carry a gradient
      // palette; everything else is a (possibly animated) glow.
      if (effect.colors.length >= 2) return _EffectKind.gradient;
      return _EffectKind.staticGlow;
  }
}

/// Builds the text style for the current animation frame: the base color
/// plus a glow shadow whose radius/opacity pulse over time.
TextStyle _styled(TextStyle base, Color color, NameEffect e, double t) {
  final accent = _accentColor(e, color);
  final kind = _kind(e);
  final pulse = kind == _EffectKind.pulse
      ? 0.55 + 0.45 * math.sin(t * 2 * math.pi)
      : 1.0;
  final blur = (6 + 22 * e.intensity) * pulse;
  final style = base.copyWith(
    color: color,
    shadows: [
      Shadow(color: accent.withValues(alpha: 0.85 * pulse), blurRadius: blur),
      if (e.intensity > 0.6)
        Shadow(
          color: accent.withValues(alpha: 0.5 * pulse),
          blurRadius: blur * 2.2,
        ),
    ],
  );
  if (kind == _EffectKind.gradient || kind == _EffectKind.wave) {
    // The gradient painter owns the foreground; keep the glow only.
    return style.copyWith(color: style.color?.withValues(alpha: 0.0));
  }
  return style;
}

/// The effect's own accent color: the server palette's first entry when the
/// effect defines one, otherwise the nickname's base color — so ANY color
/// combines with ANY effect (blue + fire works, red + ice works).
Color _accentColor(NameEffect e, Color base) {
  if (e.colors.isNotEmpty) {
    final parsed = parseHexColor(e.colors.first);
    if (parsed != null) return parsed;
  }
  return base;
}

/// Horizontal RGB-split / slice displacement for glitch effects.
class _GlitchWrap extends StatelessWidget {
  const _GlitchWrap({
    required this.t,
    required this.child,
  });

  final double t;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final phase = (t * 6).floor();
    final active = (phase % 3) == 0;
    final dx = active ? (1.5 * math.sin(phase * 12.9898)).abs() + 0.5 : 0.0;
    return Stack(
      children: [
        if (active) ...[
          Transform.translate(
            offset: Offset(dx, 0),
            child: Opacity(
              opacity: 0.7,
              child: _tinted(Colors.redAccent),
            ),
          ),
          Transform.translate(
            offset: Offset(-dx, 0),
            child: Opacity(
              opacity: 0.7,
              child: _tinted(Colors.cyanAccent),
            ),
          ),
        ],
        child,
      ],
    );
  }

  Widget _tinted(Color c) => ColorFiltered(
        colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
        child: child,
      );
}

/// Animated gradient sweep over the text (rainbow, color shifts, elemental
/// and premium effects). Uses a shader over the text bounds — still real,
/// selectable text underneath.
class _GradientText extends StatelessWidget {
  const _GradientText({
    required this.t,
    required this.effect,
    required this.style,
    required this.child,
    this.sliding = false,
  });

  final double t;
  final NameEffect effect;
  final TextStyle style;
  final Widget child;

  /// Wave/shimmer: a highlight slides across the nickname.
  final bool sliding;

  @override
  Widget build(BuildContext context) {
    final colors = [
      for (final hex in effect.colors)
        parseHexColor(hex) ?? (style.color ?? Colors.white),
    ];
    if (colors.length < 2) return child;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        final width = bounds.width == 0 ? 1.0 : bounds.width;
        final shift = sliding ? (t * 2 - 1) * width : (t * width) % width;
        return LinearGradient(
          colors: colors,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          tileMode: TileMode.mirror,
          transform: _SlideTransform(shift),
        ).createShader(bounds);
      },
      child: child,
    );
  }
}

class _SlideTransform extends GradientTransform {
  const _SlideTransform(this.dx);
  final double dx;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

/// Lightweight deterministic particle field (stars/embers/dust) that orbits
/// the nickname. Particle count scales DOWN with intensity caps in lists.
class _ParticlesPainter extends CustomPainter {
  const _ParticlesPainter({
    required this.t,
    required this.color,
    required this.intensity,
  });

  final double t;
  final Color color;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final count = (3 + intensity * 5).round().clamp(3, 8);
    final paint = Paint()..color = color.withValues(alpha: 0.9);
    for (var i = 0; i < count; i++) {
      final seed = i * 37.0;
      final x = (size.width * ((seed * 0.618) % 1));
      final drift = (t + i / count) % 1.0;
      final y = size.height * (1 - drift) - 4;
      final radius = 0.8 + (i % 3) * 0.5;
      paint.color = color.withValues(alpha: (1 - drift) * 0.9);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlesPainter old) => old.t != t;
}
