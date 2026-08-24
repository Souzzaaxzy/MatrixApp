import 'package:flutter/material.dart';

import '../core/services/app_state.dart';
import '../core/widgets/app_state_scope.dart';
import '../features/auth/login/login_screen.dart';
import '../features/auth/recover/recover_screen.dart';
import '../features/auth/register/register_screen.dart';
import '../features/create_post/create_post_screen.dart';
import '../features/home/home_screen.dart';
import '../features/post/post_detail_screen.dart';
import '../features/profile/edit_profile_screen.dart';
import '../features/splash/splash_screen.dart';
import 'routes.dart';
import 'theme/app_theme.dart';

/// Root widget for the MATRIX app.
class MatrixApp extends StatelessWidget {
  const MatrixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      state: AppState(),
      child: MaterialApp(
        title: 'MATRIX',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        initialRoute: AppRoutes.splash,
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case AppRoutes.splash:
              return _fade(const SplashScreen());
            case AppRoutes.login:
              return _fade(const LoginScreen());
            case AppRoutes.register:
              return _fade(const RegisterScreen());
            case AppRoutes.recover:
              return _fade(const RecoverScreen());
            case AppRoutes.home:
              return _fade(HomeScreen(initialIndex: (settings.arguments as int?) ?? 0));
            case AppRoutes.createPost:
              return _fade(const CreatePostScreen());
            case AppRoutes.editProfile:
              return _fade(const EditProfileScreen());
            case AppRoutes.postDetail:
              final postId = settings.arguments as String?;
              if (postId != null && postId.isNotEmpty) {
                return _fade(PostDetailScreen(postId: postId));
              }
              return _fade(const HomeScreen());
            default:
              // Unreachable through the app's own navigation — every route
              // above is wired. Kept only as a defensive fallback.
              return _fade(const Scaffold(
                body: Center(child: Text('Rota não encontrada')),
              ));
          }
        },
      ),
    );
  }

  PageRouteBuilder _fade(Widget screen) => PageRouteBuilder(
        pageBuilder: (_, __, ___) => screen,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 250),
      );
}
