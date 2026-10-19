import 'package:flutter/material.dart';

/// Ícone ⏯️ (play/pause) DESENHADO com [CustomPaint].
///
/// Por que um painter e não `Icons.play_arrow`/`Icons.pause`: o pedido é o
/// símbolo ⏯️ como um botão só — um triângulo e duas barras no MESMO glifo,
/// exatamente como o emoji, mas monocromático e colorido pelo tema. Um
/// `Icon` do Material só oferece play OU pause; alternar dois glifos faria o
/// botão "pular" de largura. Aqui a largura é constante e a cor vem de
/// [color], então o botão segue o tema (azul ativo / cinza inativo) e nunca
/// cai num emoji colorido do sistema.
class PlayPauseIcon extends StatelessWidget {
  const PlayPauseIcon({
    super.key,
    required this.playing,
    required this.color,
    this.size = 22,
  });

  /// When true the PAUSE glyph (⏸ two bars) is drawn; otherwise the PLAY
  /// glyph (▶ triangle) — the two states of ⏯️.
  final bool playing;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PlayPausePainter(playing: playing, color: color),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PlayPausePainter extends CustomPainter {
  _PlayPausePainter({required this.playing, required this.color});

  final bool playing;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    if (playing) {
      // PAUSE: duas barras verticais com cantos levemente arredondados.
      final barW = w * 0.22;
      final barH = h * 0.66;
      final top = (h - barH) / 2;
      final radius = Radius.circular(w * 0.06);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.20, top, barW, barH),
          radius,
        ),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.58, top, barW, barH),
          radius,
        ),
        paint,
      );
      return;
    }

    // PLAY: triângulo apontando para a direita, opticamente centralizado
    // (um triângulo centrado pela caixa parece deslocado à esquerda).
    final path = Path()
      ..moveTo(w * 0.30, h * 0.18)
      ..lineTo(w * 0.82, h * 0.50)
      ..lineTo(w * 0.30, h * 0.82)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PlayPausePainter old) =>
      old.playing != playing || old.color != color;
}
