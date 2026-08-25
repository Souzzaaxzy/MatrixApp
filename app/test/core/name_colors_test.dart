import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/utils/name_colors.dart';

void main() {
  group('parseHexColor', () {
    test('parses #RRGGBB and RRGGBB', () {
      expect(parseHexColor('#0066FF'), const Color(0xFF0066FF));
      expect(parseHexColor('0066FF'), const Color(0xFF0066FF));
    });

    test('returns null for absent/invalid values', () {
      expect(parseHexColor(null), isNull);
      expect(parseHexColor(''), isNull);
      expect(parseHexColor('#12345'), isNull);
      expect(parseHexColor('not-a-color'), isNull);
    });
  });

  group('resolveNameColor — contrast guard', () {
    const darkSurface = Color(0xFF050810);
    const lightSurface = Color(0xFFF5F7FA);

    test('keeps readable colors untouched on both themes', () {
      expect(
          resolveNameColor('#0066FF', darkSurface), const Color(0xFF0066FF));
      expect(
          resolveNameColor('#0066FF', lightSurface), const Color(0xFF0066FF));
      expect(
          resolveNameColor('#E53935', darkSurface), const Color(0xFFE53935));
    });

    test('drops near-invisible colors instead of altering them', () {
      // White on a light surface → fallback (null), never a "fixed" color.
      expect(resolveNameColor('#FAFAFA', lightSurface), isNull);
      // Near-black on a dark surface → fallback.
      expect(resolveNameColor('#212121', darkSurface), isNull);
      // The SAME colors stay valid on the opposite theme.
      expect(
          resolveNameColor('#FAFAFA', darkSurface), const Color(0xFFFAFAFA));
      expect(
          resolveNameColor('#212121', lightSurface), const Color(0xFF212121));
    });

    test('no customization resolves to null (theme default)', () {
      expect(resolveNameColor(null, darkSurface), isNull);
    });
  });
}
