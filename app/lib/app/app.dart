import 'package:flutter/material.dart';

import '../core/services/app_state.dart';
import '../core/services/theme_controller.dart';
import '../core/widgets/app_state_scope.dart';
import '../data/dtos/dtos.dart';
import '../data/services.dart';
import 'routes.dart';
import 'theme/app_colors.dart';
import 'theme/app_palette.dart';
import 'theme/app_theme.dart';

/// Root widget for the MATRIX app.
class MatrixApp extends StatefulWidget {
  const MatrixApp({super.key});

  @override
  State<MatrixApp> createState() => _MatrixAppState();
}

class _MatrixAppState extends State<MatrixApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Tapping a native notification deep-links into the matching screen:
    // LIKE/COMMENT → the post; FRIEND_REQUEST → Atividades;
    // FRIEND_ACCEPTED → the friend's profile.
    if (Services.isInitialized) {
      Services.instance.push.onNavigate = _onPushNavigate;
      Services.instance.push.onChatMessage = _onChatMessage;
    }
  }

  /// A real-time private message arrived on the WebSocket. Route it into the
  /// app state so an open DM / the conversations list updates live.
  /// Deduping happens by message id in the chat layer.
  void _onChatMessage(Map<String, dynamic> data) {
    final state = _navigatorKey.currentContext == null
        ? null
        : AppStateScope.maybeOf(_navigatorKey.currentContext!);
    if (state == null) return;
    final rawMessage = data['message'];
    if (rawMessage is! Map<String, dynamic>) return;
    try {
      final message = ChatMessageDto.fromJson(rawMessage).toModel();
      state.handleIncomingChatMessage(message);
    } catch (_) {
      // Malformed chat payload: ignore (the list refreshes on focus anyway).
    }
  }

  void _onPushNavigate(Map<String, dynamic> data) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    switch (data['type']) {
      case 'LIKE':
      case 'COMMENT':
        final postId = data['postId'] as String?;
        if (postId != null && postId.isNotEmpty) {
          navigator.pushNamed(AppRoutes.postDetail, arguments: postId);
        }
      case 'FRIEND_REQUEST':
        navigator.pushNamed(AppRoutes.home, arguments: 4);
      case 'FRIEND_ACCEPTED':
        final nickname = data['actorNickname'] as String?;
        if (nickname != null && nickname.isNotEmpty) {
          navigator.pushNamed(AppRoutes.profile, arguments: nickname);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      state: AppState(),
      child: ListenableBuilder(
        listenable: ThemeController.instance,
        builder: (context, _) {
          // Sync the static palette used by the widget tree with the
          // resolved (effective) brightness before building the ThemeData.
          final controller = ThemeController.instance;
          final platformDark =
              WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                  Brightness.dark;
          AppColors.setActive(effectivePalette(
            controller.mode,
            platformDark ? Brightness.dark : Brightness.light,
          ));
          return MaterialApp(
            title: 'MATRIX',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: controller.materialMode,
            navigatorKey: _navigatorKey,
            initialRoute: AppRoutes.splash,
            onGenerateRoute: buildAppRoute,
            onGenerateInitialRoutes: appInitialRoutes,
          );
        },
      ),
    );
  }
}
