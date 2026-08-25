import 'package:flutter/material.dart';

import '../features/auth/login/login_screen.dart';
import '../features/auth/recover/recover_screen.dart';
import '../features/auth/register/register_screen.dart';
import '../features/create_post/create_post_screen.dart';
import '../features/home/home_screen.dart';
import '../features/post/post_detail_screen.dart';
import '../features/profile/edit_profile_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/splash/splash_screen.dart';

/// Named routes for the MATRIX app.
class AppRoutes {
  AppRoutes._();

  static const String splash = '/splash';
  static const String login = '/login';
  static const String register = '/register';
  static const String recover = '/recover';
  static const String home = '/home';
  static const String createPost = '/home/create-post';
  static const String editProfile = '/home/edit-profile';

  /// Post detail. Argument: the post's server id (String).
  static const String postDetail = '/home/post';

  /// Profile of another user. Argument: the username (String). A null/
  /// empty argument means the session user's own profile.
  static const String profile = '/home/profile';
}

/// Single route generator for the entire app. Every route resolves to a
/// real screen; the `default` falls back to the authenticated shell
/// (HomeScreen) instead of a "Rota não encontrada" dead-end. The route
/// settings are always preserved so `popUntil((r) => r.settings.name == x)`
/// works on any pushed route.
PageRoute buildAppRoute(RouteSettings settings) {
  final Widget page = switch (settings.name) {
    AppRoutes.splash => const SplashScreen(),
    AppRoutes.login => const LoginScreen(),
    AppRoutes.register => const RegisterScreen(),
    AppRoutes.recover => const RecoverScreen(),
    AppRoutes.home =>
      HomeScreen(initialIndex: (settings.arguments as int?) ?? 0),
    AppRoutes.createPost => const CreatePostScreen(),
    AppRoutes.editProfile => const EditProfileScreen(),
    AppRoutes.postDetail => _postDetail(settings.arguments as String?),
    AppRoutes.profile => ProfileScreen(username: _usernameArg(settings.arguments)),
    _ => const HomeScreen(), // defensive fallback — never a 404 page
  };
  return PageRouteBuilder(
    settings: settings,
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 250),
  );
}

Widget _postDetail(String? postId) {
  if (postId != null && postId.isNotEmpty) return PostDetailScreen(postId: postId);
  return const HomeScreen();
}

String? _usernameArg(Object? arg) {
  final username = arg as String?;
  return (username != null && username.isNotEmpty) ? username : null;
}

/// Resolves the app's first route. The default `Navigator` implementation
/// would treat '/splash' as a deep link and ALSO push a phantom '/' route
/// underneath — which used to fall into the "not found" default case and
/// was revealed by the Android back button. We resolve exactly one route.
List<Route<dynamic>> appInitialRoutes(String initialRoute) {
  return [buildAppRoute(RouteSettings(name: initialRoute))];
}
