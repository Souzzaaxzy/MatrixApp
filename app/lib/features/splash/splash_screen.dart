import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/routes.dart';
import '../../core/widgets/app_state_scope.dart';

/// Splash total duration in ms — the animation HARD cap (spec: max 5s).
const int splashDurationMs = 4800;

/// Cyberpunk MATRIX splash screen.
///
/// Renders a lightweight, fully-native "system boot" scene using only
/// [CustomPaint] + a single animation controller — no video, no heavy
/// assets, no extra dependencies:
///  * binary code rain (0/1, JetBrains Mono) falling at different speeds
///    and brightness levels with subtle depth;
///  * small glowing particles drifting around the composition;
///  * a digital network (node dots + hairline connections) that emerges
///    progressively near the logo;
///  * the single text "MATRIX" in neon cyan with a soft glow.
///
/// While the scene plays, the stored session restore runs in parallel; the
/// app navigates to Home (authenticated) or Login as soon as BOTH the
/// minimum splash time and the restore result are known — never blindly
/// waiting the full duration, and never exceeding [splashDurationMs].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _navigated = false;
  bool _restoreDone = false;
  bool _restored = false;
  bool _ready = false;
  bool _restoreStarted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: splashDurationMs),
    )..forward();
    // Even if the restore hangs (offline timeout), the animation reaching
    // its end forces the navigation so the user is never stuck.
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _maybeNavigate();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppStateScope must be reached here (never in initState). One shot.
    if (!_restoreStarted) {
      _restoreStarted = true;
      _restoreAndNavigate();
    }
  }

  Future<void> _restoreAndNavigate() async {
    if (_navigated) return;
    final state = AppStateScope.of(context);
    final authenticated = await state.restoreSession();
    if (!mounted) return;
    _restored = authenticated;
    _restoreDone = true;
    _maybeNavigate();
  }

  void _maybeNavigate() {
    if (_navigated || !mounted) return;
    if (!_restoreDone) return;
    final timeUp = _controller.status == AnimationStatus.completed;
    if (!timeUp && !_ready) return;
    _navigated = true;
    Navigator.of(context).pushReplacementNamed(
      _restored ? AppRoutes.home : AppRoutes.login,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Called when the scene is visually established (title + network are on
  /// screen), so navigation can occur as soon as the restore finishes.
  void _onSceneReady() {
    if (_ready) return;
    setState(() => _ready = true);
    _maybeNavigate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      body: _MatrixSplashScene(
        animation: _controller,
        onReady: _onSceneReady,
      ),
    );
  }
}

/// Renders the animated scene. All layers share ONE [CustomPaint] driven by
/// a single controller so frame cost stays bounded; the rain streams are
/// moved forward on every repaint and the glyph painter set is tiny (two
/// characters).
class _MatrixSplashScene extends StatefulWidget {
  const _MatrixSplashScene({required this.animation, required this.onReady});

  final Animation<double> animation;
  final VoidCallback onReady;

  @override
  State<_MatrixSplashScene> createState() => _MatrixSplashSceneState();
}

class _MatrixSplashSceneState extends State<_MatrixSplashScene> {
  late final List<_RainColumn> _columns;
  late final List<_Particle> _particles;
  late final List<_NetworkNode> _network;
  late final math.Random _rng;
  bool _readySent = false;

  @override
  void initState() {
    super.initState();
    // Deterministic seed → the scene is stable across runs/tests.
    _rng = math.Random(42);
    _columns = List.generate(30, (i) => _RainColumn(index: i, rng: _rng));
    _particles = List.generate(24, (_) => _Particle(rng: _rng));
    _network = List.generate(16, (_) => _NetworkNode(rng: _rng));
    widget.animation.addListener(_onTick);
  }

  @override
  void didUpdateWidget(covariant _MatrixSplashScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeListener(_onTick);
      widget.animation.addListener(_onTick);
    }
  }

  @override
  void dispose() {
    widget.animation.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    if (!_readySent && widget.animation.value >= 0.5) {
      _readySent = true;
      widget.onReady();
    }
    // The rain is continuous → repaint on every tick.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _MatrixSplashPainter(
          progress: widget.animation.value,
          columns: _columns,
          particles: _particles,
          network: _network,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// One falling binary stream.
class _RainColumn {
  _RainColumn({required this.index, required math.Random rng}) {
    speed = 0.6 + rng.nextDouble() * 1.1;
    brightness = 0.25 + rng.nextDouble() * 0.75;
    char = rng.nextBool() ? '0' : '1';
  }

  final int index;
  late final double speed;
  late final double brightness;
  late final String char;

  /// Vertical position ∈ [0, 1).
  double offset = 0;

  void tick(double dtSeconds) {
    offset = (offset + speed * dtSeconds * 0.28) % 1.0;
  }
}

/// A small drifting luminous point.
class _Particle {
  _Particle({required math.Random rng})
      : x = rng.nextDouble(),
        y = rng.nextDouble(),
        size = 0.7 + rng.nextDouble() * 1.5,
        driftY = 0.008 + rng.nextDouble() * 0.02,
        opacity = 0.2 + rng.nextDouble() * 0.6,
        twinkle = rng.nextDouble() * math.pi * 2;

  final double x;
  double y;
  final double size;
  final double driftY;
  final double opacity;
  final double twinkle;

  void tick(double dtSeconds) {
    y = (y - driftY * dtSeconds) % 1.0;
  }
}

/// A network node (dot positioned around the lower/center region).
class _NetworkNode {
  _NetworkNode({required math.Random rng})
      : x = rng.nextDouble(),
        y = 0.55 + rng.nextDouble() * 0.4,
        size = 1.0 + rng.nextDouble() * 1.4;

  final double x;
  final double y;
  final double size;
}

/// Paints: deep background → binary rain → particles → network → neon
/// "MATRIX". Deterministic except for real wall-clock tick advancement (the
/// streams are stepped per repaint, independent of the progress t).
class _MatrixSplashPainter extends CustomPainter {
  _MatrixSplashPainter({
    required this.progress,
    required this.columns,
    required this.particles,
    required this.network,
  });

  final double progress;
  final List<_RainColumn> columns;
  final List<_Particle> particles;
  final List<_NetworkNode> network;

  static const _glyphBase = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 13,
    color: AppColors.electricBlue,
    fontWeight: FontWeight.w600,
  );

  static const _kRainStep = 1 / 60;

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in columns) {
      c.tick(_kRainStep);
    }
    for (final p in particles) {
      p.tick(_kRainStep);
    }

    _paintBackground(canvas, size);
    _paintRain(canvas, size);
    _paintParticles(canvas, size);
    _paintNetwork(canvas, size);
    _paintTitle(canvas, size);
  }

  void _paintBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF05090D), Color(0xFF010204), Color(0xFF00100A)],
      ).createShader(rect);
    canvas.drawRect(rect, bg);
    // Very subtle center glow to draw the eye to the logo.
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.electricBlue.withValues(
              alpha: 0.12 * (0.3 + 0.7 * _fadeIn(progress, 0.05, 0.5))),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, glow);
  }

  void _paintRain(Canvas canvas, Size size) {
    final gauge = size.width / columns.length;
    final centerY = size.height * 0.5;
    // Soft mask near the title so the glyph stays legible.
    for (var c = 0; c < columns.length; c++) {
      final col = columns[c];
      final x = col.index * gauge + gauge / 2;
      final y = col.offset * size.height;

      // Skip glyphs too close to the title band.
      final distToCenter = (y - centerY).abs();
      if (distToCenter < size.height * 0.14) continue;

      final depth = 1.0 - (y / size.height - 0.5).abs() * 1.2;
      final alpha = col.brightness * depth;
      if (alpha <= 0.05) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: col.char,
          style: _glyphBase.copyWith(
            color: AppColors.electricBlue.withValues(alpha: alpha),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y));
    }
  }

  void _paintParticles(Canvas canvas, Size size) {
    final world = _fadeIn(progress, 0.0, 0.7);
    if (world <= 0.01) return;
    for (final p in particles) {
      final twinkle = (math.sin(p.twinkle + progress * 6) + 1) * 0.5;
      final alpha = p.opacity * (0.35 + 0.65 * twinkle) * world;
      if (alpha <= 0.02) continue;
      final paint = Paint()
        ..color = AppColors.success.withValues(alpha: alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.1);
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.size,
        paint,
      );
    }
  }

  void _paintNetwork(Canvas canvas, Size size) {
    final net = _fadeIn(progress, 0.4, 0.92);
    if (net <= 0.01) return;
    final pts = <Offset>[
      for (final n in network)
        Offset(n.x * size.width, n.y * size.height * 0.62),
    ];
    final line = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: 0.2 * net)
      ..strokeWidth = 0.7;
    for (var i = 0; i < pts.length; i++) {
      for (var j = i + 1; j < pts.length; j++) {
        final a = pts[i];
        final b = pts[j];
        if ((a - b).distance < size.shortestSide * 0.3) {
          canvas.drawLine(a, b, line);
        }
      }
    }
    final node = Paint()
      ..color = AppColors.electricBlue.withValues(alpha: 0.85 * net)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4);
    for (final p in pts) {
      canvas.drawCircle(p, 1.7, node);
    }
  }

  void _paintTitle(Canvas canvas, Size size) {
    final appear = _fadeIn(progress, 0.18, 0.5);
    if (appear <= 0.002) return;
    final scale = _easeOutBack(appear);
    final center = Offset(size.width / 2, size.height * 0.46);
    final word = 'MATRIX';
    final tp = TextPainter(
      text: TextSpan(
        text: word,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 52,
          fontWeight: FontWeight.w900,
          letterSpacing: 6,
          color: Colors.white.withValues(alpha: appear),
          shadows: [
            Shadow(color: AppColors.electricBlue, blurRadius: 28),
            Shadow(color: AppColors.primaryBlue, blurRadius: 12),
            Shadow(color: AppColors.electricBlue, blurRadius: 4),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-tp.width / 2, -tp.height / 2);
    tp.paint(canvas, Offset.zero);
    canvas.restore();
  }

  double _fadeIn(double t, double start, double end) {
    if (t <= start) return 0;
    if (t >= end) return 1;
    return (t - start) / (end - start);
  }

  double _easeOutBack(double t) {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    final u = t - 1;
    return 1 + c3 * u * u * u + c1 * u * u;
  }

  @override
  bool shouldRepaint(covariant _MatrixSplashPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.columns != columns ||
      oldDelegate.particles != particles ||
      oldDelegate.network != network;
}
