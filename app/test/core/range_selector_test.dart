import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/widgets/range_selector.dart';

/// A REGRA do seletor, testada direto (sem widget): é aqui que ficam as
/// garantias de que o trecho nunca sai da faixa nem do teto de 1 minuto.
void main() {
  ({int startMs, int endMs}) norm(
    int s,
    int e, {
    int total = 300000,
    int min = 5000,
    int max = 60000,
    required bool movingStart,
  }) =>
      normalizeRange(
        startMs: s,
        endMs: e,
        totalMs: total,
        minMs: min,
        maxMs: max,
        movingStart: movingStart,
      );

  test('dragging the end beyond the cap stops at 1 minute', () {
    final r = norm(0, 999999, movingStart: false);
    expect(r.startMs, 0);
    expect(r.endMs, 60000);
  });

  test('dragging the start left of zero keeps the window in the track', () {
    final r = norm(-99999, 30000, movingStart: true);
    expect(r.startMs, 0);
    expect(r.endMs, 30000);
  });

  test('dragging the start past the end stops at end - minimum', () {
    // Comportamento de slider de intervalo: a alça do início para quando
    // encosta no mínimo, sem cruzar a alça do fim.
    final r = norm(999999, 30000, total: 45000, movingStart: true);
    expect(r.endMs, 30000);
    expect(r.startMs, 25000);
    expect(r.endMs - r.startMs, 5000);
  });

  test('dragging the end before the start keeps the minimum gap', () {
    final r = norm(30000, 0, movingStart: false);
    expect(r.startMs, 30000);
    expect(r.endMs, 35000);
    expect(r.endMs - r.startMs, 5000);
  });

  test('the window never leaves the track, whatever the drag', () {
    for (final s in [-50000, 0, 1000, 250000, 299999, 500000]) {
      for (final e in [-50000, 0, 1000, 250000, 299999, 500000]) {
        for (final movingStart in [true, false]) {
          final r = norm(s, e, movingStart: movingStart);
          expect(r.startMs, greaterThanOrEqualTo(0), reason: 's=$s e=$e');
          expect(r.endMs, lessThanOrEqualTo(300000), reason: 's=$s e=$e');
          expect(r.startMs, lessThan(r.endMs), reason: 's=$s e=$e');
          expect(r.endMs - r.startMs, greaterThanOrEqualTo(5000),
              reason: 's=$s e=$e');
          expect(r.endMs - r.startMs, lessThanOrEqualTo(60000),
              reason: 's=$s e=$e');
        }
      }
    }
  });

  test('a track shorter than the minimum still yields a valid window', () {
    // Faixa de 3s com mínimo de 5s: o widget não pode devolver start >= end.
    final r = norm(0, 3000, total: 3000, movingStart: false);
    expect(r.startMs, lessThan(r.endMs));
    expect(r.startMs, greaterThanOrEqualTo(0));
  });
}
