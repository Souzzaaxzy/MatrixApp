import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/app/theme/app_colors.dart';
import 'package:matrix_app/app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppTheme', () {
    test('dark theme uses MATRIX black background', () {
      final theme = AppTheme.dark;
      expect(theme.scaffoldBackgroundColor, AppColors.absoluteBlack);
    });

    test('primary color is the official MATRIX blue', () {
      final theme = AppTheme.dark;
      expect(theme.colorScheme.primary, AppColors.primaryBlue);
      expect(theme.colorScheme.error, AppColors.error);
    });

    test('input fields have blue focused border', () {
      final theme = AppTheme.dark;
      final input = theme.inputDecorationTheme;
      final focusedBorder = input.focusedBorder;
      expect(focusedBorder, isA<OutlineInputBorder>());
      focusedBorder as OutlineInputBorder;
      expect(focusedBorder.borderSide.color, AppColors.primaryBlue);
    });
  });

  test('AppColors palette matches the official MATRIX tokens', () {
    expect(AppColors.primaryBlue, const Color(0xFF0066FF));
    expect(AppColors.electricBlue, const Color(0xFF008CFF));
    expect(AppColors.deepBlue, const Color(0xFF003B8F));
    expect(AppColors.nightBlue, const Color(0xFF00142E));
    expect(AppColors.absoluteBlack, const Color(0xFF000000));
    expect(AppColors.bluishBlack, const Color(0xFF050914));
    expect(AppColors.techWhite, const Color(0xFFEAF4FF));
    expect(AppColors.holographicBlue, const Color(0xFF6EB6FF));
    expect(AppColors.success, const Color(0xFF00FF88));
    expect(AppColors.error, const Color(0xFFFF304F));
  });
}
