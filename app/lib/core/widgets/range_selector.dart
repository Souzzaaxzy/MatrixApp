import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Seletor de TRECHO de uma faixa, arrastando as duas pontas — o padrão do
/// Instagram para escolher a música do perfil.
///
/// O usuário arrasta a alça esquerda (início) e a direita (fim) sobre a faixa
/// inteira, e a duração é o que sobra entre elas. A precisão é de SEGUNDO, não
/// de "passos de 5s": o pedido é escolher minuto a minuto exato.
///
/// Regras (as mesmas do Instagram):
///   * as alças NÃO se cruzam e há um mínimo entre elas ([minMs]);
///   * nenhuma alça sai da faixa [0, totalMs];
///   * o trecho nunca passa de [maxMs] — quando o usuário empurra uma alça
///     além do limite, a OUTRA alça anda junto (mantendo o trecho no teto),
///     em vez de travar a alça no meio do gesto.
///
/// O widget não toca áudio: só reporta a janela escolhida. Isso o mantém
/// testável e permite que a tela decida quando tocar.
class RangeSelector extends StatelessWidget {
  const RangeSelector({
    super.key,
    required this.totalMs,
    required this.startMs,
    required this.endMs,
    required this.onChanged,
    this.minMs = 5000,
    this.maxMs = 60000,
    this.height = 54,
    this.color,
    this.trackColor,
    this.onChangeStart,
    this.onChangeEnd,
  });

  /// Duração total da faixa (ms). Sem isso não há faixa para arrastar.
  final int totalMs;

  /// Pontas atuais, em ms, relativas ao início da faixa.
  final int startMs;
  final int endMs;

  /// Chamado durante o arrasto com a janela já normalizada (nunca fora da
  /// faixa, nunca maior que [maxMs], nunca menor que [minMs]).
  final void Function(int startMs, int endMs) onChanged;

  /// Mínimo de trecho aceito.
  final int minMs;

  /// Máximo de trecho aceito (o teto de 1 minuto do perfil).
  final int maxMs;

  final double height;
  final Color? color;
  final Color? trackColor;

  /// Avisos de início/fim de gesto (a tela usa para tocar/pré-visualizar).
  final VoidCallback? onChangeStart;
  final VoidCallback? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    final track = trackColor ?? accent.withValues(alpha: 0.22);
    final total = totalMs > 0 ? totalMs : 1;

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return _RangeSelectorBody(
            width: width,
            totalMs: total,
            startMs: startMs,
            endMs: endMs,
            minMs: minMs,
            maxMs: maxMs,
            accent: accent,
            track: track,
            onChanged: onChanged,
            onChangeStart: onChangeStart,
            onChangeEnd: onChangeEnd,
          );
        },
      ),
    );
  }
}

/// Normaliza a janela escolhida para os limites do perfil.
///
/// Fica fora do widget de propósito: é a REGRA, e a regra é o que os testes
/// travam. Devolve sempre `start < end`, dentro de [0, totalMs], com pelo
/// menos [minMs] e no máximo [maxMs] de trecho.
({int startMs, int endMs}) normalizeRange({
  required int startMs,
  required int endMs,
  required int totalMs,
  required int minMs,
  required int maxMs,
  required bool movingStart,
}) {
  final total = math.max(totalMs, 0);
  final lo = math.max(minMs, 1); // janela de pelo menos 1ms
  final hi = math.max(maxMs, lo); // teto nunca abaixo do piso
  var s = startMs;
  var e = endMs;

  // 1. A alça ARRASTADA nunca sai da faixa. Fazer isto PRIMEIRO é o que
  //    impede o gesto de AMPLIAR a janela: arrastar o início para antes de
  //    zero encosta em zero e o fim fica onde estava (antes, a regra do teto
  //    rodava com o valor fora da faixa e esticava o trecho de 30s para 60s).
  if (movingStart) {
    s = s.clamp(0, total);
  } else {
    e = e.clamp(0, total);
  }

  // 2/3. Mínimo e teto: a alça ARRASTADA PARA no limite e a oposta fica
  //      ancorada. Deixar a janela "seguir" o dedo moveria o início que o
  //      usuário escolheu a dedo (ex.: o refrão em 1:12) sem aviso — pior que
  //      simplesmente parar de crescer.
  if (e - s < lo) {
    if (movingStart) {
      s = e - lo;
    } else {
      e = s + lo;
    }
  }
  if (e - s > hi) {
    if (movingStart) {
      s = e - hi;
    } else {
      e = s + hi;
    }
  }

  // 4. Se a alça oposta saiu da faixa, empurra a JANELA inteira de volta,
  //    preservando o comprimento.
  if (s < 0) {
    e -= s;
    s = 0;
  }
  if (e > total) {
    s -= e - total;
    e = total;
  }
  s = s.clamp(0, math.max(0, total - lo));
  e = e.clamp(math.min(total, s + lo), total);

  // 5. Faixa mais curta que o mínimo: melhor esforço, sempre com s < e.
  if (e - s < lo) {
    s = 0;
    e = total;
    if (e <= s) {
      s = 0;
      e = lo;
    }
  }
  if (e - s > hi) e = s + hi;
  return (startMs: s, endMs: e);
}

class _RangeSelectorBody extends StatelessWidget {
  const _RangeSelectorBody({
    required this.width,
    required this.totalMs,
    required this.startMs,
    required this.endMs,
    required this.minMs,
    required this.maxMs,
    required this.accent,
    required this.track,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
  });

  final double width;
  final int totalMs;
  final int startMs;
  final int endMs;
  final int minMs;
  final int maxMs;
  final Color accent;
  final Color track;
  final void Function(int startMs, int endMs) onChanged;
  final VoidCallback? onChangeStart;
  final VoidCallback? onChangeEnd;

  static const double _handleWidth = 14;

  double get _pxPerMs => width / totalMs;

  double _xFor(int ms) => ms * _pxPerMs;

  int _msFor(double x) => (x / _pxPerMs).round();

  void _emit(int s, int e, {required bool movingStart}) {
    final r = normalizeRange(
      startMs: s,
      endMs: e,
      totalMs: totalMs,
      minMs: minMs,
      maxMs: maxMs,
      movingStart: movingStart,
    );
    onChanged(r.startMs, r.endMs);
  }

  @override
  Widget build(BuildContext context) {
    final startX = _xFor(startMs);
    final endX = _xFor(endMs);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Trilha completa (a faixa inteira, apagada).
        Positioned.fill(
          child: Align(
            alignment: Alignment.center,
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: track,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        // Parte SELECIONADA (destacada).
        Positioned(
          left: startX,
          width: math.max(0, endX - startX),
          top: 0,
          bottom: 0,
          child: Center(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        // Alça ESQUERDA (início).
        _handle(
          key: const ValueKey('range-handle-start'),
          x: startX,
          semanticsLabel: 'Início do trecho',
          onDragStart: () => onChangeStart?.call(),
          onDragUpdate: (dx) =>
              _emit(_msFor(startX + dx), endMs, movingStart: true),
          onDragEnd: () => onChangeEnd?.call(),
        ),
        // Alça DIREITA (fim).
        _handle(
          key: const ValueKey('range-handle-end'),
          x: endX,
          semanticsLabel: 'Fim do trecho',
          onDragStart: () => onChangeStart?.call(),
          onDragUpdate: (dx) =>
              _emit(startMs, _msFor(endX + dx), movingStart: false),
          onDragEnd: () => onChangeEnd?.call(),
        ),
      ],
    );
  }

  Widget _handle({
    required Key key,
    required double x,
    required String semanticsLabel,
    required VoidCallback onDragStart,
    required void Function(double dx) onDragUpdate,
    required VoidCallback onDragEnd,
  }) {
    return Positioned(
      left: x - _handleWidth / 2,
      top: 0,
      bottom: 0,
      width: _handleWidth,
      child: Semantics(
        label: semanticsLabel,
        slider: true,
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          // O arrasto é medido em DELTA (não em posição absoluta): assim a
          // alça acompanha o dedo mesmo quando o gesto começa fora do centro.
          onHorizontalDragStart: (_) => onDragStart(),
          onHorizontalDragUpdate: (d) => onDragUpdate(d.delta.dx),
          onHorizontalDragEnd: (_) => onDragEnd(),
          onHorizontalDragCancel: onDragEnd,
          child: Center(
            child: Container(
              width: _handleWidth,
              height: 26,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: Colors.white24, width: 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
