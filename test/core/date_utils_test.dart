import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/utils/date_utils.dart';

void main() {
  final now = DateTime(2026, 1, 15, 12, 0, 0);

  test('returns "agora" for less than a minute', () {
    expect(relativeTime(now.subtract(const Duration(seconds: 10)), now: now), 'agora');
  });

  test('returns minutes', () {
    expect(relativeTime(now.subtract(const Duration(minutes: 5)), now: now), 'há 5 min');
  });

  test('returns hours', () {
    expect(relativeTime(now.subtract(const Duration(hours: 3)), now: now), 'há 3 h');
  });

  test('returns days', () {
    expect(relativeTime(now.subtract(const Duration(days: 2)), now: now), 'há 2 d');
  });

  test('returns formatted date for older than a week', () {
    final past = DateTime(2025, 12, 1, 10, 0, 0);
    expect(relativeTime(past, now: now), '01/12');
  });
}
