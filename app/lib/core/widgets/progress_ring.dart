import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Anel de progresso DESENHADO em volta de um botão — o padrão do Instagram
/// para a música do perfil.
///
/// Por que um painter e não `CircularProgressIndicator`: o widget do Material
/// desenha um arco solto e não deixa controlar a largura/posição com precisão
/// nem combinar com uma trilha completa por baixo. Aqui o anel tem duas
/// partes, como no Instagram:
///   * TRILHA — círculo completo, discreto (mostra o quanto falta);
///   * PROGRESSO — arco que cresce do topo, no sentido horário.
///
/// O arco começa no TOPO (12 horas) e não na direita: é o ponto de partida
/// que o olho espera num player.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.progress,
    required this.child,
    this.size = 44,
    this.strokeWidth = 2.5,
    this.color = Colors.white,
    this.trackColor,
    this.gap = 3,
  });

  /// 0.0 → 1.0. Valores fora da faixa são fixados (nunca desenha um arco
  /// maior que o círculo).
  final double progress;
  final Widget child;

  /// Diâmetro EXTERNO do anel (o botão fica dentro, descontado o [gap]).
  final double size;
  final double strokeWidth;
  final Color color;

  /// Cor da trilha (o "resto" do círculo). Nula → a cor do arco bem apagada.
  final Color? trackColor;

  /// Espaço entre o anel e o [child].
  final double gap;

  @override
  Widget build(BuildContext context) {
    final value = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ProgressRingPainter(
          progress: value,
          strokeWidth: strokeWidth,
          color: color,
          trackColor: trackColor ?? color.withValues(alpha: 0.22),
        ),
        child: Padding(
          padding: EdgeInsets.all(strokeWidth + gap),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final double strokeWidth;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    if (radius <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;
    canvas.drawCircle(center, radius, track);

    // Com progresso ~0 não desenha arco nenhum (um traço de comprimento zero
    // com ponta arredondada viraria um ponto solto no topo).
    if (progress <= 0) return;

    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // -pi/2 = topo (12 horas); o arco cresce no sentido horário.
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, arc);
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter old) =>
      old.progress != progress ||
      old.strokeWidth != strokeWidth ||
      old.color != color ||
      old.trackColor != trackColor;
}
