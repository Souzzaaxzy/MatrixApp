import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/app/routes.dart';
import 'package:matrix_app/app/theme/app_theme.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/core/widgets/app_state_scope.dart';
import 'package:matrix_app/features/auth/login/login_screen.dart';
import 'package:matrix_app/features/auth/register/register_screen.dart';
import 'package:matrix_app/features/create_post/create_post_screen.dart';
import 'package:matrix_app/features/customizations/customizations_screen.dart';
import 'package:matrix_app/features/home/home_screen.dart';
import 'package:matrix_app/features/post/post_detail_screen.dart';
import 'package:matrix_app/features/profile/edit_profile_screen.dart';
import 'package:matrix_app/features/profile/profile_screen.dart';
import 'package:matrix_app/features/splash/splash_screen.dart';

import 'fake_repositories.dart';

/// Pumps a given [child] inside a MaterialApp with the MATRIX theme and an
/// [AppStateScope] backed by in-memory fake repositories, so widget tests
/// share the same dependency wiring as the real app without a network.
Future<void> pumpMatrixApp(
  WidgetTester tester,
  Widget child, {
  AppState? state,
}) async {
  state ??= AppState(repositories: FakeRepositories());
  // Restore the session so screens relying on currentUser render content.
  await state.restoreSession();
  await state.loadFeed();
  await tester.pumpWidget(
    AppStateScope(
      state: state,
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
          AppRoutes.customizations: (_) => const CustomizationsScreen(),
          AppRoutes.postDetail: (context) {
            final id = ModalRoute.of(context)!.settings.arguments as String;
            return PostDetailScreen(postId: id);
          },
          AppRoutes.profile: (context) {
            final nickname =
                ModalRoute.of(context)!.settings.arguments as String?;
            return ProfileScreen(
              nickname:
                  (nickname != null && nickname.isNotEmpty) ? nickname : null,
            );
          },
        },
      ),
    ),
  );
  // Let any post-frame callbacks (feed load, etc.) run.
  await tester.pump();
}

/// Creates an [AppState] ready for widget tests — restores the session and
/// loads the feed against the fake repositories.
Future<AppState> seededAppState() async {
  final state = AppState(repositories: FakeRepositories());
  await state.restoreSession();
  await state.loadFeed();
  return state;
}

/// Logged-in [AppState] with social data (notifications, friend requests)
/// seeded in the fake store, as if the server had persisted them.
Future<AppState> seededAppStateWithSocial({
  List<dynamic> notifications = const [],
  List<dynamic> friendRequests = const [],
}) async {
  final repos = FakeRepositories();
  for (final n in notifications) {
    repos.store.notifications.add(n);
  }
  for (final r in friendRequests) {
    repos.store.friendRequests[r.id] = r;
  }
  final state = AppState(repositories: repos);
  await state.restoreSession();
  await state.loadFeed();
  await state.loadNotifications();
  return state;
}
