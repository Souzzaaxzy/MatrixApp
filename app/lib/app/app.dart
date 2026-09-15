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
  final _RouteWatcher _routeWatcher = _RouteWatcher();
  StreamSubscription<SharedStickerBatch>? _shareSub;

  /// Compartir recibido que todavía no pudo abrirse (app sin sesión o aún en
  /// el splash). Se reintenta en cuanto la navegación/ sesión lo permiten —
  /// así el contenido NUNCA se pierde.
  String? _pendingShareTitle;
  String? _pendingShareError;

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
      // Compartir de Android: contenido recibido mientras el app está
      // abierto → abre la pantalla de importación.
      ShareStickerService.instance.listen();
      _shareSub = ShareStickerService.instance.onBatches.listen(_onSharedBatch);
      // Lote que haya abierto el app (proceso frío) — lo consulta el splash
      // después del restore para asegurar que el usuario está autenticado.
      _checkInitialShare();
    }
  }

  /// Trata un lote compartido: error → feedback claro al usuario; contenido
  /// válido → abre la importación de stickers.
  void _onSharedBatch(SharedStickerBatch batch) {
    if (batch.kind == SharedBatchKind.error) {
      _pendingShareError =
          batch.error ?? 'O conteúdo compartilhado não é compatível com o MATRIX.';
      ShareStickerService.instance.clearCurrent();
      _flushPendingShare();
      return;
    }
    _pendingShareTitle = batch.title;
    _flushPendingShare();
  }

  /// Si el app fue abierto por un share (proceso frío) y ya hay sesión,
  /// abre la importación. El splash llama a [initialBatch] en el arranque.
  void _checkInitialShare() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final batch = await ShareStickerService.instance.currentBatch();
      if (batch == null) return;
      _onSharedBatch(batch);
    });
  }

  /// Abre lo pendiente cuando la pantalla actual y la sesión lo permiten.
  /// Se vuelve a llamar en cada cambio de ruta y al autenticarse.
  void _flushPendingShare() {
    final state = _state;
    if (state == null) return;

    final error = _pendingShareError;
    if (error != null) {
      final context = _navigatorKey.currentContext;
      if (context != null) {
        _pendingShareError = null;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
      return;
    }

    final title = _pendingShareTitle;
    if (title == null) return;
    if (!state.isAuthenticated) return; // el splash redirige a login primero
    // Só espera enquanto as rotas de BOOT ainda estão no topo: o
    // `pushReplacementNamed` do splash (ou do login) SUBSTITUIRIA a tela de
    // confirmação e o pacote se perderia. ANTES havia um allowlist
    // (home/stickerImport) que bloqueava a confirmação quando o usuário
    // estava em QUALQUER outra tela — por exemplo numa conversa, justamente
    // de onde se compartilha uma figurinha. Era a causa da confirmação
    // "sumida". Agora só bloqueamos as rotas de arranque.
    const bootRoutes = {
      AppRoutes.splash,
      AppRoutes.login,
      AppRoutes.register,
      AppRoutes.recover,
    };
    if (bootRoutes.contains(_routeWatcher.current)) {
      return;
    }
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    _pendingShareTitle = null;
    // Nunca APILAR telas de importação: se uma já está aberta (o usuário
    // compartilhou de novo sem fechá-la), o lote novo a SUBSTITUI — cada
    // share é processado uma vez e não sobra uma pilha para o Back desfazer.
    if (_routeWatcher.current == AppRoutes.stickerImport) {
      navigator.pushReplacementNamed(AppRoutes.stickerImport, arguments: title);
    } else {
      navigator.pushNamed(AppRoutes.stickerImport, arguments: title);
    }
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
          final appState = AppStateScope.of(context);
          return MaterialApp(
            title: 'MATRIX',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: controller.materialMode,
            navigatorKey: _navigatorKey,
            navigatorObservers: [_routeWatcher],
            initialRoute: AppRoutes.splash,
            onGenerateRoute: buildAppRoute,
            onGenerateInitialRoutes: appInitialRoutes,
            builder: (context, child) {
              // La sesión puede restaurarse/autenticarse DESPUÉS de recibir
              // el share: reintenta abrir la importación cuando cambie.
              return ListenableBuilder(
                listenable: appState,
                builder: (context, _) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _flushPendingShare();
                  });
                  return child ?? const SizedBox.shrink();
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Observa el nombre de la ruta superior para saber cuándo es seguro abrir la
/// importación de stickers sin que el splash/una redirección la reemplace.
class _RouteWatcher extends NavigatorObserver {
  String? current;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    current = route.settings.name;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    current = previousRoute?.settings.name;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    current = newRoute?.settings.name;
  }
}
