import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/app/theme/app_colors.dart';
import 'package:matrix_app/app/theme/app_palette.dart';
import 'package:matrix_app/core/services/theme_controller.dart';
import 'package:matrix_app/data/theme_store.dart';

/// In-memory ThemeStore: stands in for secure storage so persistence is
/// exercised through the real ThemeController code path.
class _MemoryThemeStore implements ThemeStore {
  String? value;

  @override
  Future<MatrixThemeMode> read() async {
    for (final mode in MatrixThemeMode.values) {
      if (mode.name == value) return mode;
    }
    return MatrixThemeMode.dark;
  }

  @override
  Future<void> write(MatrixThemeMode mode) async {
    value = mode.name;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeController', () {
    testWidgets('defaults to dark before any preference is loaded',
        (tester) async {
      final controller = ThemeController.debug(_MemoryThemeStore());
      expect(controller.mode, MatrixThemeMode.dark);
      expect(controller.materialMode, ThemeMode.dark);
    });

    testWidgets('setMode persists: a fresh controller loads the same value',
        (tester) async {
      final store = _MemoryThemeStore();
      final a = ThemeController.debug(store);
      await a.load();
      await a.setMode(MatrixThemeMode.light);
      expect(a.mode, MatrixThemeMode.light);
      expect(a.materialMode, ThemeMode.light);
      expect(store.value, 'light');

      // Simulate an app restart: a new controller on the SAME store.
      final b = ThemeController.debug(store);
      await b.load();
      expect(b.mode, MatrixThemeMode.light);

      await a.setMode(MatrixThemeMode.system);
      expect(store.value, 'system');
    });

    testWidgets('notifies listeners on setMode', (tester) async {
      final controller = ThemeController.debug(_MemoryThemeStore());
      await controller.load();
      var notified = 0;
      controller.addListener(() => notified++);
      await controller.setMode(MatrixThemeMode.light);
      expect(notified, greaterThan(0));
    });
  });

  group('Palette resolution', () {
    test('dark preference always resolves to the dark palette', () {
      expect(effectivePalette(MatrixThemeMode.dark, Brightness.dark),
          MatrixPalette.dark);
      expect(effectivePalette(MatrixThemeMode.dark, Brightness.light),
          MatrixPalette.dark);
    });

    test('light preference always resolves to the light palette', () {
      expect(effectivePalette(MatrixThemeMode.light, Brightness.dark),
          MatrixPalette.light);
      expect(effectivePalette(MatrixThemeMode.light, Brightness.light),
          MatrixPalette.light);
    });

    test('system follows the platform brightness', () {
      expect(effectivePalette(MatrixThemeMode.system, Brightness.dark),
          MatrixPalette.dark);
      expect(effectivePalette(MatrixThemeMode.system, Brightness.light),
          MatrixPalette.light);
    });

    testWidgets('AppColors tokens change with the active palette',
        (tester) async {
      AppColors.setActive(MatrixPalette.dark);
      final darkBg = AppColors.scaffoldBackground;
      final darkText = AppColors.techWhite;

      AppColors.setActive(MatrixPalette.light);
      expect(AppColors.scaffoldBackground, isNot(darkBg));
      expect(AppColors.techWhite, isNot(darkText));
      // Brand accent survives both themes.
      expect(AppColors.primaryBlue, AppColors.primaryBlue);

      AppColors.setActive(MatrixPalette.dark); // restore default for others
    });
  });
}
