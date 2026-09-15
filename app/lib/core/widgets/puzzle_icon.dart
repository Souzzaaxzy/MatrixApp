import 'package:flutter/material.dart';

/// Ícone de FIGURINHAS do composer: um quebra-cabeça (puzzle) MONOCROMÁTICO
/// desenhado com [CustomPaint].
///
/// Por que um painter e não `Icons.extension_*`: o pedido é o símbolo de
/// peça de quebra-cabeça em versão PRETA/limpa — um glifo vetorial próprio
/// garante exatamente essa aparência, sem depender do conjunto de ícones nem
/// correr o risco de cair num emoji colorido do sistema (que não é aceitável
/// como ícone final do botão). A cor é sempre a recebida em [color], então o
/// botão continua seguindo o tema (cinza inativo / azul ativo) e nada muda no
/// resto do composer.
class PuzzleIcon extends StatelessWidget {
  const PuzzleIcon({
    super.key,
    required this.color,
    this.size = 24,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PuzzlePainter(color: color),
        // Semantics: o botão é lido como "Figurinhas" por leitores de tela.
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PuzzlePainter extends CustomPainter {
  _PuzzlePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Peça de quebra-cabeça em visão "cheia": um quadrado com uma saliência
    // (nó) no topo e um encaixe (nó negativo) na lateral direita, desenhado
    // em coordenadas relativas (funciona em qualquer tamanho).
    final path = Path();
    const cx = 0.5; // centro horizontal
    final r = w * 0.13; // raio do nó

    // Começa no canto superior esquerdo, desce a lateral esquerda.
    path.moveTo(w * 0.16, h * 0.30);

    // Topo com saliência central (nó para cima).
    path.lineTo(w * 0.38, h * 0.30);
    path.arcToPoint(
      Offset(w * (cx + 0.12), h * 0.30),
      radius: Radius.circular(r),
      clockwise: true,
    );
    path.lineTo(w * 0.84, h * 0.30);

    // Lateral direita com encaixe (nó para dentro).
    path.lineTo(w * 0.84, h * 0.45);
    path.arcToPoint(
      Offset(w * 0.84, h * 0.70),
      radius: Radius.circular(r),
      clockwise: false,
    );
    path.lineTo(w * 0.84, h * 0.84);

    // Base e lateral esquerda completando a peça.
    path.lineTo(w * 0.16, h * 0.84);
    path.lineTo(w * 0.16, h * 0.70);
    path.arcToPoint(
      Offset(w * 0.16, h * 0.45),
      radius: Radius.circular(r),
      clockwise: false,
    );
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PuzzlePainter oldDelegate) =>
      oldDelegate.color != color;
}