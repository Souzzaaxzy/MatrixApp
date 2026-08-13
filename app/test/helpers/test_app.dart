import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/app/routes.dart';
import 'package:matrix_app/app/theme/app_theme.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/core/widgets/app_state_scope.dart';
import 'package:matrix_app/features/auth/login/login_screen.dart';
import 'package:matrix_app/features/auth/register/register_screen.dart';
import 'package:matrix_app/features/create_post/create_post_screen.dart';
import 'package:matrix_app/features/home/home_screen.dart';
import 'package:matrix_app/features/profile/edit_profile_screen.dart';
import 'package:matrix_app/features/splash/splash_screen.dart';

/// Pumps a given [child] inside a MaterialApp with the MATRIX theme and an
/// [AppStateScope], so widget tests share the same dependency wiring as
/// the real app.
Future<void> pumpMatrixApp(
  WidgetTester tester,
  Widget child, {
  AppState? state,
}) async {
  await tester.pumpWidget(
    AppStateScope(
      state: state ?? AppState(),
      child: MaterialApp(
        theme: AppTheme.dark,
        home: child,
        routes: {
          AppRoutes.splash: (_) => const SplashScreen(),
          AppRoutes.login: (_) => const LoginScreen(),
          AppRoutes.register: (_) => const RegisterScreen(),
          AppRoutes.home: (_) => const HomeScreen(),
          AppRoutes.createPost: (_) => const CreatePostScreen(),
          AppRoutes.editProfile: (_) => const EditProfileScreen(),
        },
      ),
    ),
  );
}
