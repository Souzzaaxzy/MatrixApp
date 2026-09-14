import 'dart:async';

import 'package:flutter/material.dart';

import '../core/services/app_state.dart';
import '../core/services/theme_controller.dart';
import '../core/widgets/app_state_scope.dart';
import '../data/dtos/dtos.dart';
import '../data/services.dart';
import '../data/share_sticker_service.dart';
import '../features/chat/chat_navigation.dart';
import '../models/conversation.dart';
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
  StreamSubscription<List<SharedStickerFile>>? _shareSub;

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Tapping a native notification deep-links into the matching screen:
    // LIKE/COMMENT → the post; FRIEND_REQUEST → Atividades;
    // FRIEND_ACCEPTED → the friend's profile.
    if (Services.isInitialized) {
      Services.instance.push.onNavigate = _onPushNavigate;
      Services.instance.push.onChatMessage = _onChatMessage;
      Services.instance.push.onChatTyping = _onChatTyping;
      Services.instance.push.onChatRecording = _onChatRecording;
      Services.instance.push.onChatRead = _onChatRead;
      Services.instance.push.onChatMessageDeleted = _onChatMessageDeleted;
      Services.instance.push.onChatGroupUpdated = _onChatGroupUpdated;
      Services.instance.push.onChatGroupBanned = _onChatGroupBanned;
      Services.instance.push.onChatGroupDeleted = _onChatGroupDeleted;
      Services.instance.push.onCommentDeleted = _onCommentDeleted;
      // Compartir de Android: archivos de figuritas recibidos mientras el
      // app está abierto → abre la pantalla de importación.
      ShareStickerService.instance.listen();
      _shareSub = ShareStickerService.instance.onFiles.listen((_) {
        _openStickerImport(title: '');
      });
      // Lote que haya abierto el app (proceso frío) — lo consulta el splash
      // después del restore para asegurar que el usuario está autenticado.
      _checkInitialShare();
    }
  }

  /// Si el app fue abierto por un share (proceso frío) y ya hay sesión,
  /// abre la importación. El splash llama a [initialFiles] en el arranque.
  void _checkInitialShare() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final files = await ShareStickerService.instance.currentFiles();
      if (files != null && files.isNotEmpty) {
        final state = _state;
        if (state != null && state.isAuthenticated) {
          _openStickerImport(title: '');
        }
      }
    });
  }

  /// Navega hasta la pantalla de importación de figuritas.
  void _openStickerImport({required String title}) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    final state = _state;
    if (state == null || !state.isAuthenticated) return;
    navigator.pushNamed(AppRoutes.stickerImport, arguments: title);
  }

  /// A peer deleted a message FOR EVERYONE (realtime). AppState forwards it
  /// to open conversation screens via [AppState.onChatMessageDeleted].
  void _onChatMessageDeleted(Map<String, dynamic> data) {
    final state = _state;
    if (state == null) return;
    final groupId = data['groupId'] as String?;
    final conversationId = data['conversationId'] as String?;
    final messageId = data['messageId'] as String? ?? '';
    if (messageId.isEmpty) return;
    if (conversationId == null && groupId == null) return;
    state.handleIncomingChatMessageDeleted(
      ChatMessageDeletedEvent(
        groupId: groupId,
        conversationId: conversationId,
        messageId: messageId,
      ),
    );
  }

  /// A comment was deleted (by its owner or the post author). AppState
  /// exposes it so open comments surfaces remove the entry live..

  /// A group's identity was edited by the owner (realtime. Refresh the
  /// cached header and tell open conversation/profile screens to re-render.
  void _onChatGroupUpdated(Map<String, dynamic> data) {
    final state = _state;
    if (state == null) return;
    try {
      state.handleIncomingGroupUpdated(GroupUpdatedEvent.fromMap(data));
    } catch (_) {
      // Malformed payload: ignore (the next list load refreshes it anyway).
    }
  }

  /// The session user was BANNED from a group (realtime). AppState drops
  /// the group from the cache; open group screens are kicked via the
  /// [AppState.onGroupBanned] stream.
  void _onChatGroupBanned(Map<String, dynamic> data) {
    final state = _state;
    if (state == null) return;
    final groupId = data['groupId'] as String? ?? '';
    if (groupId.isEmpty) return;
    state.handleIncomingGroupBanned(GroupBannedEvent(
      groupId: groupId,
      groupName: data['groupName'] as String? ?? '',
    ));
  }

  /// The session user LOST ACCESS to a group (realtime) — the owner
  /// permanently deleted it or the user left it. AppState drops the group
  /// from the cache; open group screens close via the
  /// [AppState.onGroupDeleted] stream.
  void _onChatGroupDeleted(Map<String, dynamic> data) {
    final state = _state;
    if (state == null) return;
    final groupId = data['groupId'] as String? ?? '';
    if (groupId.isEmpty) return;
    state.handleIncomingGroupDeleted(GroupDeletedEvent(
      groupId: groupId,
      groupName: data['groupName'] as String? ?? '',
    ));
  }

  void _onCommentDeleted(Map<String, dynamic> data) {
    final state = _state;
    if (state == null) return;
    final postId = data['postId'] as String? ?? '';
    final commentId = data['commentId'] as String? ?? '';
    if (postId.isEmpty || commentId.isEmpty) return;
    state.handleIncomingCommentDeleted(
      CommentDeletedEvent(postId: postId, commentId: commentId),
    );
  }

  /// A real-time private message arrived on the WebSocket. Route it into the
  /// app state so an open DM / the conversations list updates live.
  /// Deduping happens by message id in the chat layer.
  void _onChatMessage(Map<String, dynamic> data) {
    final state = _state;
    if (state == null) return;
    final rawMessage = data['message'];
    if (rawMessage is! Map<String, dynamic>) return;
    try {
      final message = ChatMessageDto.fromJson(rawMessage).toModel();
      // The realtime payload carries the SENDER's identity (id, nickname,
      // avatarUrl, cosmetics…) so the app can build a real preview bubble
      // and avatar for an inbox conversation it hasn't loaded yet.
      final rawPeer = data['peer'];
      ChatUser? peer;
      if (rawPeer is Map<String, dynamic>) {
        peer = ChatUser(
          id: (rawPeer['id'] as String?) ?? message.senderId,
          nickname: (rawPeer['nickname'] as String?) ?? 'desconhecido',
          avatarUrl: rawPeer['avatarUrl'] as String?,
          nameColor: rawPeer['nameColor'] as String?,
          frameId: (rawPeer['frameId'] as String?) ??
              (rawPeer['frameAsset'] as String?),
          frameAsset: rawPeer['frameAsset'] as String?,
        );
      }
      state.handleIncomingChatMessage(message, peer: peer);
    } catch (_) {
      // Malformed chat payload: ignore (the list refreshes on focus anyway).
    }
  }

  /// A real-time typing signal arrived (peer started/stopped typing).
  void _onChatTyping(Map<String, dynamic> data) {
    final state = _state;
    if (state == null) return;
    final groupId = data['groupId'] as String?;
    final conversationId = data['conversationId'] as String?;
    if (conversationId == null && groupId == null) return;
    state.handleIncomingChatTyping(ChatTypingEvent(
      groupId: groupId,
      conversationId: conversationId,
      userId: data['userId'] as String?,
      nickname: data['nickname'] as String?,
      typing: (data['typing'] as bool?) ?? false,
    ));
  }

  /// The peer started/stopped recording a voice message in a conversation
  /// (realtime "gravando áudio" hint below the nickname).
  void _onChatRecording(Map<String, dynamic> data) {
    final state = _state;
    if (state == null) return;
    final groupId = data['groupId'] as String?;
    final conversationId = data['conversationId'] as String?;
    if (conversationId == null && groupId == null) return;
    state.handleIncomingChatRecording(ChatRecordingEvent(
      groupId: groupId,
      conversationId: conversationId,
      userId: data['userId'] as String?,
      nickname: data['nickname'] as String?,
      recording: (data['recording'] as bool?) ?? false,
    ));
  }

  /// The peer read one of my messages in a conversation(realtime read
  /// receipt for the "visto agora" hint).
  void _onChatRead(Map<String, dynamic> data) {
    final state = _state;
    if (state == null) return;
    final groupId = data['groupId'] as String?;
    final conversationId = data['conversationId'] as String?;
    if (conversationId == null && groupId == null) return;
    final rawMessageIds = data['messageIds'];
    state.handleIncomingChatRead(
      ChatReadEvent(
        groupId: groupId,
        conversationId: conversationId,
        userId: data['userId'] as String?,
        messageIds: rawMessageIds is List
            ? rawMessageIds.whereType<String>().toList()
            : const <String>[],
      ),
    );
  }

  /// Resolves the AppState from the navigator context whenever available.
  AppState? get _state {
    final context = _navigatorKey.currentContext;
    if (context == null) return null;
    return AppStateScope.maybeOf(context);
  }

  void _onPushNavigate(Map<String, dynamic> data) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    // Native DM notification → open the matching conversation directly.
    if (data['route'] == 'conversation') {
      final conversationId = data['conversationId'] as String? ?? '';
      final otherUserId = data['otherUserId'] as String? ?? '';
      final nickname = (data['otherNickname'] as String?) ?? otherUserId;
      if (conversationId.isNotEmpty) {
        navigator.pushNamed(
          AppRoutes.conversation,
          arguments: ConversationRouteArgs(
            conversationId: conversationId,
            otherUserId: otherUserId,
            otherNickname: nickname,
            otherAvatarUrl: data['otherAvatarUrl'] as String?,
          ),
        );
      }
      return;
    }
    switch (data['type']) {
      case 'LIKE':
      case 'COMMENT':
        final postId = data['postId'] as String?;
        if (postId != null && postId.isNotEmpty) {
          navigator.pushNamed(AppRoutes.postDetail, arguments: postId);
        }
      case 'FRIEND_REQUEST':
        // Atividades tab (index 3 — Akame is no longer a bottom-bar entry).
        navigator.pushNamed(AppRoutes.home, arguments: 3);
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
