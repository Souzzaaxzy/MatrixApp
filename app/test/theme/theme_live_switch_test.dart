import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/app/app.dart';
import 'package:matrix_app/app/theme/app_colors.dart';
import 'package:matrix_app/app/theme/app_palette.dart';
import 'package:matrix_app/core/services/theme_controller.dart';
import 'package:matrix_app/features/auth/login/login_screen.dart';

/// Regression: switching the theme must repaint the WHOLE app immediately —
/// no restart, no navigation, no reload. The single source of truth is
/// [ThemeController.instance]; the root [MatrixApp] listens to it, swaps the
/// active palette and rebuilds the MaterialApp in the same frame.
///
/// Note: `setMode` is called WITHOUT await — the state change is synchronous
/// (only the disk write is async, and platform channels never resolve inside
/// the fake-async widget-test zone).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MaterialApp materialApp(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp));

  Color scaffoldColor(WidgetTester tester) =>
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor ??
      Colors.transparent;

  testWidgets('dark → light → dark applies immediately across the app',
      (tester) async {
    final controller = ThemeController.instance;
    controller.setMode(MatrixThemeMode.dark);
    addTearDown(() => controller.setMode(MatrixThemeMode.dark));

    await tester.pumpWidget(const MatrixApp());
    await tester.pump();

    expect(materialApp(tester).themeMode, ThemeMode.dark);
    expect(AppColors.activePalette, MatrixPalette.dark);
    expect(scaffoldColor(tester), MatrixPalette.dark.scaffold);

    // Tap "Claro": the SAME frame updates state, palette and widgets.
    controller.setMode(MatrixThemeMode.light);
    await tester.pump();
    expect(materialApp(tester).themeMode, ThemeMode.light);
    expect(AppColors.activePalette, MatrixPalette.light);
    expect(scaffoldColor(tester), MatrixPalette.light.scaffold);

    // And back to "Escuro" — still without any restart.
    controller.setMode(MatrixThemeMode.dark);
    await tester.pump();
    expect(materialApp(tester).themeMode, ThemeMode.dark);
    expect(AppColors.activePalette, MatrixPalette.dark);
    expect(scaffoldColor(tester), MatrixPalette.dark.scaffold);
  });

  testWidgets('system mode follows the phone brightness live', (tester) async {
    final controller = ThemeController.instance;
    addTearDown(() {
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue();
      controller.setMode(MatrixThemeMode.dark);
    });
    controller.setMode(MatrixThemeMode.system);

    await tester.pumpWidget(const MatrixApp());
    await tester.pump();
    expect(materialApp(tester).themeMode, ThemeMode.system);

    // Phone flips to light: MATRIX follows without touching the settings.
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    await tester.pump();
    expect(AppColors.activePalette, MatrixPalette.light);
    expect(scaffoldColor(tester), MatrixPalette.light.scaffold);

    // Phone flips back to dark.
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    await tester.pump();
    expect(AppColors.activePalette, MatrixPalette.dark);
    expect(scaffoldColor(tester), MatrixPalette.dark.scaffold);
  });

  testWidgets('a pushed/navigated screen also follows the switch live',
      (tester) async {
    final controller = ThemeController.instance;
    controller.setMode(MatrixThemeMode.dark);
    addTearDown(() => controller.setMode(MatrixThemeMode.dark));

    await tester.pumpWidget(const MatrixApp());
    // Splash animation (1.8s) completes → session restore fails (no
    // Services in tests) → lands on the login screen.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(scaffoldColor(tester), MatrixPalette.dark.scaffold);

    controller.setMode(MatrixThemeMode.light);
    await tester.pump();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(scaffoldColor(tester), MatrixPalette.light.scaffold);
  });
}
