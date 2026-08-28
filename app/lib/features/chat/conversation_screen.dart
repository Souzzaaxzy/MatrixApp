import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/services/app_state.dart';
import '../../core/utils/chat_format.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/glow_container.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/matrix_text_field.dart';
import '../../core/widgets/nickname_renderer.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/api_config.dart';
import '../../data/services.dart';
import '../../models/conversation.dart';
import 'chat_navigation.dart';
import 'voice_player_bubble.dart';
import 'voice_recorder.dart';

/// How long the "digitando..." hint stays on screen without a new typing
/// frame before it auto-clears (peer stopped or its app closed silently).
const _typingTimeout = Duration(seconds: 4);

/// Vertical offset the reply quote is capped at while swiping.
const _replySwipeThreshold = 96.0;

/// Minimum horizontal drag distance to activate reply selection.
const _replyDragThreshold = 90.0;

/// Private conversation screen — the single DM UI reached from every entry
/// point (Chat search / friends / conversations list / profile "Mensagem").
///
/// Layout: nickname HEADER (centered, tappable → the other user's profile),
/// the message thread (received left, sent right, each in its own bubble,
/// exact local HH:mm) and a bottom composer (input + send button that rides
/// the keyboard). Messages are persisted server-side; paginated (oldest
/// pages fetched on scroll-up); live-updated via the shared WebSocket.
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.args});

  final ConversationRouteArgs args;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with WidgetsBindingObserver {
  static const _pagesize = 30;

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  Conversation? _conversation;
  final List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _loadingOlder = false;
  bool _hasMore = true;
  String? _error;

  /// Voice-message recorder. Reading [VoiceRecorderController.state] lets the
  /// composer swap the text field for the waveform + mic gestures. Cancels
  /// (releases the mic) on dispose/interruption so nothing is left open.
  final VoiceRecorderController _recorder = VoiceRecorderController();
  VoidCallback? _recListener;
  double _dragDx = 0; // live gesture displacement of the mic button
  bool _dragLocked = false;
  bool _voiceSending = false;
  double _dragDy = 0; // vertical live gesture displacement (up = negative)
  bool _recordingSignaled =
      false; // whether the peer was told were are recording

  StreamSubscription<ChatMessage>? _chatSub;
  StreamSubscription<ChatTypingEvent>? _typingSub;
  StreamSubscription<ChatRecordingEvent>? _recordingSub;
  StreamSubscription<ChatReadEvent>? _readSub;
  StreamSubscription<ChatMessageDeletedEvent>? _deletedSub;

  /// Whether the newest message is pinned to the bottom (auto-follow new).
  bool _followBottom = true;

  // ── "digitando..." (peer typing) ───────────────────────────
  bool _peerTyping = false;
  Timer? _typingAutoClear;

  // ── "gravando áudio" (peer voice recording) ─────────────
  bool _peerRecording = false;
  Timer? _recordingAutoClear;

  // ── Reply-to-message selection ─────────────────────────────
  ChatMessage? _replyTarget;
  int? _replyTargetIndex;

  /// True after dispose — guards async callbacks (typing debounce) against
  /// touching a destroyed state.
  bool _disposeCalled = false;

  @override
  void initState() {
    super.initState();
    _conversation = null;
    _scroll.addListener(_scrollListener);
    // Notify the native-push layer that THIS conversation is on screen so it
    // suppresses notifications for it (Part 4.5 — rule driven by real state).
    // Guarded: Services may not be initialized in isolated widget tests.
    if (Services.isInitialized) {
      final id = widget.args.conversationId;
      if (id.isNotEmpty && Services.instance.push.activeConversationId != id) {
        Services.instance.push.activeConversationId = id;
      }
    }
  }

  /// Safe accessor — the actual AppState (may still be null during the very
  /// first frames until the scope resolves).
  AppState? get _state => _resolvedState;
  AppState? _resolvedState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppStateScope.maybeOf(context);
    if (_resolvedState != state) {
      _resolvedState = state;
      _chatSub?.cancel();
      _chatSub = state?.onChatIncoming.listen(_onRealtime);
      _typingSub?.cancel();
      _typingSub = state?.onChatTyping.listen(_onTyping);
      _recordingSub?.cancel();
      _recordingSub = state?.onChatRecording.listen(_onRecording);
      _readSub?.cancel();
      _readSub = state?.onChatRead.listen(_onReadReceipt);
      _deletedSub?.cancel();
      _deletedSub =
          state?.onChatMessageDeleted.listen(_onMessageDeletedRealtime);
    }
    if (!_loadRequested) {
      // Defer the load: _load notifies listeners synchronously.
      _loadRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    // Reflect recorder state changes into the composer (waveform, gesture
    // states, send progression). ChangeNotifier → addListener.
    if (_recListener == null) {
      _recListener = () {
        if (mounted) setState(() {});
      };
      _recorder.addListener(_recListener!);
    }
    // Interruption guard: any app/dialog transition cancels a live capture
    // so the mic is always released (never left "gravando" forever).
    WidgetsBinding.instance.addObserver(this);
  }

  bool _loadRequested = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Background, inactive (interrupted by a call/notification shade that
    // steals focus), etc. → lock or cancel a running capture so the mic is
    // released promptly. Locked recordings survive; a plain RECORDING stays
    // safe but never loses its resource.
    if (s == AppLifecycleState.resumed) return;
    if (_recorder.isRecording && !_dragLocked) {
      _recorder.lock(); // protected capture: don't lose the take
    }
  }

  @override
  void dispose() {
    _disposeCalled = true;
    // Leaving the screen while capturing must clear the peer's
    // "gravando áudio" hint immediately (ephemeral signal, fire-and-forget).
    if (_recordingSignaled) {
      _recordingSignaled = false;
      final id = _conversationId;
      if (id.isNotEmpty) _state?.sendRecording(id, false);
    }
    _chatSub?.cancel();
    _typingSub?.cancel();
    _recordingSub?.cancel();
    _readSub?.cancel();
    _deletedSub?.cancel();
    if (_recListener != null) {
      _recorder.removeListener(_recListener!);
      _recListener = null;
    }
    final id = _conversationId;
    if (Services.isInitialized &&
        id.isNotEmpty &&
        Services.instance.push.activeConversationId == id) {
      Services.instance.push.activeConversationId = null;
    }
    _typingAutoClear?.cancel();
    _typingSendDebounce?.cancel();
    if (_typingLastSent) {
      final id = _conversationId;
      if (id.isNotEmpty) _state?.sendTyping(id, false);
    }
    _recordingAutoClear?.cancel();
    if (_peerRecording) {
      final id = _conversationId;
      if (id.isNotEmpty) _state?.sendRecording(id, false);
    }
    // Releasing the recorder here ALSO cancels a live capture (the mic is
    // closed in VoiceRecorderController.dispose) — leaving the screen while
    // recording never leaves the resource hanging.
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_recorder.cancel());
    _recorder.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _conversationId {
    if (widget.args.conversationId.isNotEmpty) {
      return widget.args.conversationId;
    }
    return _conversation?.id ?? '';
  }

  Future<void> _load() async {
    final state = _state;
    if (state == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Ensure the conversation exists (get-or-create) when we only have the
      // other user (search/friend/profile entry). Already-known ids load fast.
      var conversation = _conversation;
      if (_conversationId.isEmpty) {
        conversation =
            await state.getOrCreateConversation(widget.args.otherUserId);
        if (!mounted) return;
      } else if (conversation == null || conversation.id == _conversationId) {
        // Reuse the cached conversation if present, else fetch a fresh one.
        final cached = state.conversations
            .where((c) => c.id == _conversationId)
            .firstOrNull;
        if (cached != null) {
          conversation = cached;
        } else {
          conversation =
              await state.getOrCreateConversation(widget.args.otherUserId);
          if (!mounted) return;
        }
      }
      _conversation = conversation;

      final page = await state.loadMessages(conversation.id, limit: _pagesize);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(page.messages);
        _hasMore = page.hasMore;
        _loading = false;
      });
      // Open the DM → mark read (clears the unread badge server-side).
      unawaited(state.markConversationRead(conversation.id));
      // Start near the newest message.
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar a conversa. Verifique sua conexão.';
      });
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final conversationId = _conversationId;
    if (conversationId.isEmpty) return;

    // Grab the reply target BEFORE clearing state so the outgoing quote is
    // attached to the right message.
    final reply = _replyTarget;
    final controller = _input;
    setState(() => _sending = true);
    try {
      final message = await _state!.sendChatMessage(
        conversationId,
        text,
        otherUser: _conversation?.otherUser ?? widget.args.otherUser,
        replyToMessageId: reply?.id,
      );
      if (!mounted) return;
      controller.clear();
      setState(() {
        _replyTarget = null;
        _replyTargetIndex = null;
      });
      _appendMessage(message);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível enviar a mensagem.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Sends a finished voice message (locked tap-to-send flow). The recorder
  /// must be LOCKED. On success appends the bubble and updates the list
  /// preview live; failures surface as a message without killing the thread.
  Future<void> _sendVoice() async {
    final conversationId = _conversationId;
    if (conversationId.isEmpty) return;
    if (_voiceSending) return; // no double send while processing
    if (_recorder.state != VoiceRecorderState.locked &&
        _recorder.state != VoiceRecorderState.recording) {
      return;
    }
    if (_recorder.state == VoiceRecorderState.recording) {
      // A plain press-and-release (no lock) still sends on release.
      _recorder.lock();
    }
    setState(() {
      _voiceSending = true;
      _dragLocked = false;
      _dragDx = 0;
      _dragDy = 0;
    });
    final file = await _recorder.finish();
    // The capture ended (regardless of outcome) — tell rise peer so the
    // "gravando áudio" hint clears immediately, even when we cannot send.s
    if (_recordingSignaled) {
      _recordingSignaled = false;
      final id = _conversationId;
      if (id.isNotEmpty) _state?.sendRecording(id, false);
    }
    if (!mounted) return;
    if (file == null) {
      setState(() => _voiceSending = false);
      return;
    }
    final durationMs = _recorder.elapsed.inMilliseconds.clamp(1000, 60000);
    try {
      final message = await _state!.sendVoiceMessage(
        conversationId,
        file,
        durationMs: durationMs,
        otherUser: _conversation?.otherUser ?? widget.args.otherUser,
      );
      _appendMessage(message);
      unawaited(_state!.markConversationRead(conversationId));
    } on ApiException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível enviar o áudio.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Erro ao enviar o áudio. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _voiceSending = false);
    }
  }

  /// Appends a message to the list (dedup by id) and scrolls to the bottom
  /// when following it.
  void _appendMessage(ChatMessage message) {
    if (_messages.any((m) => m.id == message.id)) return; // dedupe
    setState(() => _messages.add(message));
    if (_followBottom) _jumpToBottom();
  }

  void _onRealtime(ChatMessage message) {
    if (!mounted) return;
    if (message.conversationId != _conversationId) return;
    if (message.senderId == _state?.currentUser?.id) return; // own send
    _appendMessage(message);
  }

  // ── Realtime message deletion ─────────────────────────────
  /// A peer deleted a message FOR EVERYONE → drop the bubble live from this
  /// open conversation (no manual refresh needed).
  void _onMessageDeletedRealtime(ChatMessageDeletedEvent event) {
    if (!mounted) return;
    if (event.conversationId != _conversationId) return;
    if (event.messageId.isEmpty) return;
    setState(() {
      _messages.removeWhere((m) => m.id == event.messageId);
      if (_replyTarget?.id == event.messageId) {
        _replyTarget = null;
        _replyTargetIndex = null;
      }
    });
  }

  // ── Long-press message menu ──────────────────────────────
  /// Long-press on a bubble → contextual menu with the actions the user is
  /// actually allowed to take. "Excluir" = for me only; "Excluir para todos"
  /// (always available to any participant, server-validated) removes it for
  /// both sides.
  Future<void> _showMessageMenu(int index) async {
    if (index < 0 || index >= _messages.length) return;
    final message = _messages[index];
    final conversationId = _conversationId;
    if (conversationId.isEmpty) return;

    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      isScrollControlled: true,
      builder: (_) => _MessageActionMenu(message: message, index: index),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case _MessageAction.reply:
        _startReply(index);
      case _MessageAction.deleteForMe:
        await _confirmAndDeleteMessageForMe(
          conversationId,
          message,
        );
      case _MessageAction.deleteForEveryone:
        await _confirmAndDeleteForEveryone(
          conversationId,
          message,
        );
    }
  }

  Future<void> _confirmAndDeleteMessageForMe(
    String conversationId,
    ChatMessage message,
  ) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bluishBlack,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          side: BorderSide(color: AppColors.deepBlue),
        ),
        title: Text(
          'Excluir mensagem?',
          style: AppTextStyles.hud.copyWith(
            fontSize: 16,
            color: AppColors.techWhite,
          ),
        ),
        content: Text(
          'A mensagem será removida somente para você.',
          style: AppTextStyles.bodyMuted,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar',
                style: TextStyle(color: AppColors.holographicBlue)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Excluir', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await _state?.deleteChatMessageForMe(conversationId, message.id);
    if (!mounted) return;
    if (ok == true) {
      setState(() => _messages.removeWhere((m) => m.id == message.id));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível excluir a mensagem.')),
      );
    }
  }

  Future<void> _confirmAndDeleteForEveryone(
    String conversationId,
    ChatMessage message,
  ) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bluishBlack,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          side: BorderSide(color: AppColors.deepBlue),
        ),
        title: Text(
          'Excluir esta mensagem para todos?',
          style: AppTextStyles.hud.copyWith(
            fontSize: 16,
            color: AppColors.techWhite,
          ),
        ),
        content: Text(
          'Esta mensagem será removida para todos os participantes.',
          style: AppTextStyles.bodyMuted,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar',
                style: TextStyle(color: AppColors.holographicBlue)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Excluir', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok =
        await _state?.deleteChatMessageForEveryone(conversationId, message.id);
    if (!mounted) return;
    if (ok == true) {
      setState(() => _messages.removeWhere((m) => m.id == message.id));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível excluir a mensagem.')),
      );
    }
  }

  // ── Realtime "digitando..." ────────────────────────────────
  void _onTyping(ChatTypingEvent event) {
    if (!mounted) return;
    if (event.conversationId != _conversationId) return;
    _typingAutoClear?.cancel();
    if (event.typing) {
      setState(() => _peerTyping = true);
      // Auto-clear if the peer stops sending frames (closed app, lost
      // connection, stalled input) — never let it get stuck.
      _typingAutoClear = Timer(_typingTimeout, () {
        if (mounted) setState(() => _peerTyping = false);
      });
    } else {
      setState(() => _peerTyping = false);
    }
  }

  // ── Realtime "gravando áudio" (peer voice recording) ──────
  void _onRecording(ChatRecordingEvent event) {
    if (!mounted) return;
    if (event.conversationId != _conversationId) return;
    _recordingAutoClear?.cancel();
    if (event.recording) {
      if (!_peerRecording) setState(() => _peerRecording = true);
      // Auto-clear if the peer's app dies mid-capture (closed, lost
      // connection, crash) — never leave "gravando áudio" stuck.s
      _recordingAutoClear = Timer(const Duration(seconds: 8), () {
        if (mounted) setState(() => _peerRecording = false);
      });
    } else {
      if (_peerRecording) setState(() => _peerRecording = false);
    }
  }

  // ── Realtime read receipt ("visto agora") ──────────────────
  void _onReadReceipt(ChatReadEvent event) {
    if (!mounted) return;
    if (event.conversationId != _conversationId) return;
    // The peer read my messages → flip readAt on my LAST sent message.
    bool changed = false;
    final now = DateTime.now();
    for (var i = _messages.length - 1; i >= 0 && !changed; i--) {
      final m = _messages[i];
      if (!m.mine) continue;
      if (m.readAt == null) {
        _messages[i] = m.copyWith(readAt: now);
        changed = true;
      }
      break; // only the newest of my messages needs the hint
    }
    if (changed) setState(() {});
  }

  // ── Reply-to-message selection ─────────────────────────────
  /// Activates the reply composer for [index] (a swipe crossed the
  /// threshold).
  void _startReply(int index) {
    if (index < 0 || index >= _messages.length) return;
    setState(() {
      _replyTarget = _messages[index];
      _replyTargetIndex = index;
    });
  }

  void _cancelReply() {
    setState(() {
      _replyTarget = null;
      _replyTargetIndex = null;
    });
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlder || !_hasMore || _messages.isEmpty) return;
    final conversationId = _conversationId;
    if (conversationId.isEmpty) return;
    setState(() => _loadingOlder = true);
    final beforeId = _messages.first.id;
    try {
      final page = await _state!.loadMessages(
        conversationId,
        before: beforeId,
        limit: _pagesize,
      );
      if (!mounted) return;
      final offsetBefore = _scroll.position.minScrollExtent;
      setState(() {
        _messages.insertAll(
            0, page.messages.where((m) => !_messages.any((x) => x.id == m.id)));
        _hasMore = page.hasMore;
        _loadingOlder = false;
      });
      // Keep the scroll anchored near the same message instead of jumping.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final offsetAfter = _scroll.position.minScrollExtent;
        _scroll.jumpTo(_scroll.position.pixels + (offsetAfter - offsetBefore));
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _scrollListener() {
    // Near the bottom → follow new messages; near the top → load older.
    final pos = _scroll.position;
    _followBottom = pos.pixels >= pos.maxScrollExtent - 80;
    if (pos.pixels <= pos.minScrollExtent + 40 && _hasMore) {
      _loadOlderMessages();
    }
  }

  void _openPeerProfile() {
    final user = _conversation?.otherUser ?? widget.args.otherUser;
    if (user.id.isEmpty) return;
    Navigator.of(context).pushNamed(
      AppRoutes.profile,
      arguments: user.nickname,
    );
  }

  @override
  Widget build(BuildContext context) {
    final conversation = _conversation;
    final other = conversation?.otherUser ?? widget.args.otherUser;

    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      appBar: AppBar(
        backgroundColor: AppColors.absoluteBlack,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: true,
        centerTitle: true,
        leading: BackButton(
          color: AppColors.holographicBlue,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: GestureDetector(
          onTap: _openPeerProfile,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NicknameRenderer(
                other.nickname,
                baseStyle: AppTextStyles.h3.copyWith(fontSize: 19),
                background: AppColors.absoluteBlack,
                nameColor: other.nameColor,
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
              // Realtime peer status directly below the nickname (only in
              // a live conversation with a peer). Centered. Voice recording
              // takes precedence over typing — the peer cannot do both,so
              // swapping them avoids rendering a stacked/conflicting pair.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position:
                        Tween(begin: const Offset(0, -0.05), end: Offset.zero)
                            .animate(anim),
                    child: child,
                  ),
                ),
                child: conversation == null
                    ? const SizedBox(key: ValueKey('idle'), width: 0, height: 0)
                    : _peerRecording
                        ? _RecordingIndicator(
                            key: const ValueKey('recording'),
                            typing: false,
                          )
                        : _peerTyping
                            ? const _RecordingIndicator(
                                key: ValueKey('typing'),
                                typing: true,
                              )
                            : const SizedBox(
                                key: ValueKey('idle'),
                                width: 0,
                                height: 0,
                              ),
              ),
            ],
          ),
        ),
        titleTextStyle:
            AppTextStyles.h3.copyWith(fontSize: 19, color: AppColors.techWhite),
        toolbarHeight:
            kToolbarHeight + ((_peerRecording || _peerTyping) ? 18 : 0),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildThread(conversation, other)),
            // Reply-to preview above the composer when a message is selected.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position:
                      Tween(begin: const Offset(0, 0.05), end: Offset.zero)
                          .animate(anim),
                  child: child,
                ),
              ),
              child: _replyTarget != null
                  ? _ReplyPreviewBar(
                      key: ValueKey(_replyTarget!.id),
                      target: _replyTarget!,
                      onCancel: _cancelReply,
                    )
                  : const SizedBox.shrink(),
            ),
            _Composer(
              controller: _input,
              sending: _sending,
              enabled: conversation != null,
              onChanged: _onInputChanged,
              onSend: _send,
              onTapMic: _onMicTap,
              onMicLongPressStart: _onMicPressStart,
              onMicLongPressEnd: _onMicRelease,
              onMicDragUpdate: _onMicDrag,
              recorder: _recorder,
              dragDx: _dragDx,
              dragDy: _dragDy,
              dragCancelZone: _dragDx <= -40 && !_dragLocked,
              dragLocked: _dragLocked,
              voiceSending: _voiceSending,
            ),
          ],
        ),
      ),
    );
  }

  /// Typing debounce-signalling from the composer: any change → start typing;
  /// after 1.5s of no input the peer's indicator stops.
  Timer? _typingSendDebounce;
  bool _typingLastSent = false;

  void _onInputChanged(String _) {
    final id = _conversationId;
    if (id.isEmpty || _disposeCalled) return;
    _typingSendDebounce?.cancel();
    if (!_typingLastSent) {
      _typingLastSent = true;
      _state?.sendTyping(id, true);
    }
    _typingSendDebounce = Timer(
      const Duration(milliseconds: 1400),
      () {
        _typingLastSent = false;
        if (mounted && !_disposeCalled) _state?.sendTyping(id, false);
      },
    );
  }

  // ── Voice recording gestures ──────────────────────────────
  // Short tap: hint only (never starts a capture). Hold: start recording
  // immediately). Hold+drag UP: lock the take (recording continues after
  // the finger lifts and the central button becomes "tap to send"). Hold+
  // drag LEFT: cancel + discard (no file, no message, back to idle).
  // The button can never leave the screen (displacement is clamped to keep it
  // inside the composer area).

  Future<void> _onMicTap() async {
    if (_recorder.state == VoiceRecorderState.recording ||
        _recorder.state == VoiceRecorderState.locked) {
      // Locked take: the stable mic button now wears the send icon — a tap
      // finalizes the capture and starts the upload (no second hold needed).
      if (_dragLocked) await _sendVoice();
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('segure para gravar áudio'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _onMicPressStart(LongPressStartDetails details) async {
    if (_recorder.state != VoiceRecorderState.idle &&
        _recorder.state != VoiceRecorderState.error) {
      return; // already capturing / processing — never start a second one
    }
    _dragLocked = false;
    _dragDx = 0;
    _dragDy = 0;
    _recordingSignaled = false;
    final ok = await _recorder.start();
    if (ok && mounted) {
      _recordingSignaled = true;
      // Tell the peer the capture started (ephemeral realtime frame — best
      // effort; failed signals don't kill the recording). Also stops the
      // "digitando..." if it was showing (we no longer are typing).s
      final id = _conversationId;
      if (id.isNotEmpty) {
        _state?.sendRecording(id, true);
        _typingSendDebounce?.cancel();
        if (_typingLastSent) {
          _typingLastSent = false;
          _state?.sendTyping(id, false);
        }
      }
    }
    if (!ok && mounted) {
      // Permission denied or capture failed. Show a clear message once.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(_recorder.lastError ??
              'Permissão do microfone necessária para gravar áudio.'),
          duration: const Duration(seconds: 3),
        ));
    }
  }

  void _onMicDrag(Offset delta) {
    if (_recorder.state != VoiceRecorderState.recording) return;
    // Horizontal clamp keeps the button inside the composer area; vertical
    // only tracks upward motion (negative) — past its threshold it locks
    // the take (recording survives release,, mic becomes "tap to send").
    // Positive dy can jitter from the long-press recognizer, so it is ignored
    // toward lock/send. Dragging within the cancel zone already shows red.

    _dragDx = (_dragDx + delta.dx).clamp(-140.0, 140.0);
    if (delta.dy < 0) {
      _dragDy = (_dragDy + delta.dy).clamp(-140.0, 0);
    }
    if (!_dragLocked && _dragDy <= -70) {
      _dragLocked = true;
      _dragDy = 0;
      _recorder.lock();
      if (mounted) setState(() {});
      return;
    }
    if (!_dragLocked && _dragDx <= -70) {
      _dragDx = 0;
      _dragDy = 0;
      unawaited(_cancelMic());
      return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _onMicRelease() async {
    if (_recorder.state == VoiceRecorderState.recording && !_dragLocked) {
      // Plain press-and-release with NO lock → send the take (matches
      // WhatsApp-style short holds). Cancelled drags already reset state.

      _dragDx = 0;
      _dragDy = 0;
      await _sendVoice();
      return;
    }
    if (_dragLocked) {
      // Release after LOCK: nothing to do — the take keeps recording until
      // the "send" button is tapped. Reset the drag visuals anyway.s
      if (mounted) {
        setState(() {
          _dragDx = 0;
          _dragDy = 0;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _dragDx = 0;
        _dragDy = 0;
      });
    }
  }

  Future<void> _cancelMic() async {
    await _recorder.cancel();
    if (_recordingSignaled) {
      _recordingSignaled = false;
      final id = _conversationId;
      if (id.isNotEmpty) _state?.sendRecording(id, false);
    }
    if (mounted) {
      setState(() {
        _dragLocked = false;
        _dragDx = 0;
        _dragDy = 0;
      });
    }
  }

  Widget _buildThread(Conversation? conversation, ChatUser other) {
    if (_loading) {
      return const Center(
          child: HudLabel(text: 'CARREGANDO MENSAGENS...', dot: true));
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.spaceXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  color: AppColors.error, size: 40),
              const SizedBox(height: AppDimensions.spaceMd),
              Text(
                error,
                textAlign: TextAlign.center,
                style: AppTextStyles.body,
              ),
              const SizedBox(height: AppDimensions.spaceLg),
              MatrixButton(
                label: 'Tentar novamente',
                icon: Icons.refresh_rounded,
                onPressed: _load,
              ),
            ],
          ),
        ),
      );
    }
    if (conversation == null) {
      return Center(
        child: Text(
          'Não foi possível abrir esta conversa.',
          style: AppTextStyles.bodyMuted,
        ),
      );
    }
    if (_messages.isEmpty) {
      return _EmptyThread(other: other);
    }
    // Chronological messages grouped by day separators.
    final items = <Widget>[];
    DateTime? lastDay;
    var normalShownCounter = 0;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final day =
          DateTime(m.createdAt.year, m.createdAt.month, m.createdAt.day);
      if (lastDay == null || lastDay != day) {
        lastDay = day;
        items.add(_DaySeparator(label: chatDayLabel(m.createdAt)));
      }
      // Whether this is the newest message OF THE WHOLE LIST (only that one
      // shows the "enviado"/"visto agora" hint). Slots ease updates when a
      // message shifts position.
      final isLast = i == _messages.length - 1;
      // Mention the SENDER only when it's the OTHER side (my own avatar is
      // not shown — the layout stays clean and matches the original design).
      final senderAvatar = m.mine ? null : (other.avatarUrl ?? other.nickname);
      // Avatar rule for OTHER-side bubbles (own never show one):
      //  * a reply or a voice message ALWAYS shows the avatar;
      //  * a normal (text, non-reply] message shows when the previous
      //    same-sender run was interrupted (sender change,, my own message,
      //    voice or reply), OR when five consecutive normal bubbles already
      //    showed it —the 6th starts a fresh 5-group again.
      final prev = i > 0 ? _messages[i - 1] : null;
      final prevSameNormalSender = prev != null &&
          !prev.mine &&
          prev.senderId == m.senderId &&
          !prev.isVoice &&
          prev.replyTo == null;
      final interrupted = m.mine ||
          prev == null ||
          !prevSameNormalSender ||
          m.isVoice ||
          m.replyTo != null;
      final showAvatar = !m.mine && (interrupted || normalShownCounter >= 5);
      if (m.mine) {
        normalShownCounter = 0;
      } else if (m.isVoice || m.replyTo != null) {
        normalShownCounter = 0;
      } else if (interrupted) {
        normalShownCounter = 1;
      } else if (normalShownCounter >= 5) {
        normalShownCounter = 1;
      } else {
        normalShownCounter++;
      }
      final firstOfRun = showAvatar;
      items.add(_MessageBubble(
        message: m,
        index: i,
        isLast: isLast,
        firstOfRun: firstOfRun,
        peerName: m.mine ? null : other.nickname,
        peerAvatar: senderAvatar,
        onStartReply: _startReply,
        onLongPress: () => _showMessageMenu(i),
        replySelected: _replyTargetIndex == i,
      ));
    }
    return Listener(
      onPointerMove: (_) {},
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          if (_hasMore)
            SliverToBoxAdapter(
              child: _loadingOlder
                  ? const Padding(
                      padding: EdgeInsets.all(AppDimensions.spaceMd),
                      child: Center(
                          child: HudLabel(text: 'CARREGANDO...', dot: true)),
                    )
                  : const SizedBox(height: AppDimensions.spaceSm),
            ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.spaceLg,
              vertical: AppDimensions.spaceMd,
            ),
            sliver: SliverList(delegate: SliverChildListDelegate(items)),
          ),
          const SliverToBoxAdapter(
              child: SizedBox(height: AppDimensions.spaceMd)),
        ],
      ),
    );
  }
}

class _EmptyThread extends StatelessWidget {
  const _EmptyThread({required this.other});
  final ChatUser other;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlowContainer(
              glow: Glow.medium,
              color: AppColors.glowSmall,
              background: AppColors.primaryBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
              padding: const EdgeInsets.all(AppDimensions.spaceLg),
              child: Icon(Icons.chat_bubble_outline_rounded,
                  color: AppColors.electricBlue, size: 40),
            ),
            const SizedBox(height: AppDimensions.spaceLg),
            Text(
              'Sem mensagens ainda',
              style: AppTextStyles.h3.copyWith(color: AppColors.techWhite),
            ),
            const SizedBox(height: AppDimensions.spaceSm),
            Text(
              'Envie a primeira mensagem para ${other.nickname}.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimensions.spaceMd),
      child: Center(
        child: HudLabel(text: label.toUpperCase(), dot: false),
      ),
    );
  }
}

/// Realtime peer status hint under the app-bar nickname: "gravando áudio"
/// (recording voice — animated, light: a tiny looping 3-dot wave, no
/// layout churn) or "digitando..." (typing — static, matching the pre-existing
/// hint). Only one is rendered at a time — recording wins when both arrive.

class _RecordingIndicator extends StatefulWidget {
  const _RecordingIndicator({super.key, required this.typing});
  final bool typing;

  @override
  State<_RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<_RecordingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  static const _period = Duration(milliseconds: 900);

  @override
  void initState() {
    super.initState();
    // Only a recording indicator needs the loop; typing stays static (zero
    // extra work for the common case).
    _pulse = AnimationController(vsync: this, duration: _period)..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.typing) {
      return const Padding(
        padding: EdgeInsets.only(top: 2),
        child: Text(
          'digitando...',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.electricBlue,
            fontFamily: 'JetBrainsMono',
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    // Three dots pulsing in sequence around the label — a lightweight
    // wave driven by a single ticker (one small row,, no full-list rebuild).
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'gravando áudio',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.electricBlue,
              fontFamily: 'JetBrainsMono',
            ),
          ),
          const SizedBox(width: 4),
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) {
              final v = _pulse.value;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final phase = (v + i / 3) % 1;
                  final opacity = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
                  return Opacity(
                    opacity: opacity.clamp(0.2, 1.0),
                    child: const Text(
                      '•',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.electricBlue,
                        fontFamily: 'JetBrainsMono',
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A single message bubble. Sent messages align right; received align left —
/// ALWAYS driven by `message.mine` (the server's real sender), never by a
/// local "who sent last" heuristic.
///
/// Features:
///  * Reply quote rendered inside the bubble when the message answers one.
///  * The "enviado"/"visto agora" status only appears INSIDE the newest
///    message the SESSION user sent (no symbols, no ticks).
///  * Swipe-left→right on the bubble activates reply selection with a smooth
///    followed heal-drag (bounded so the bubble never leaves the screen).
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.index,
    required this.isLast,
    this.firstOfRun = true,
    this.peerName,
    this.peerAvatar,
    required this.onStartReply,
    required this.onLongPress,
    this.replySelected = false,
  });

  final ChatMessage message;
  final int index;
  final bool isLast;

  /// Whether this is the first received bubble of a same-sender run (drives
  /// avatar emphasis). Irrelevant for my own messages.
  final bool firstOfRun;

  /// The OTHER sender's identity when this is a received message (drives the
  /// avatar next to the bubble). Null for my own messages.
  final String? peerName;
  final String? peerAvatar;

  final void Function(int index) onStartReply;
  final VoidCallback onLongPress;
  final bool replySelected;

  static const _maxWidth = 300.0;

  @override
  Widget build(BuildContext context) {
    final mine = message.mine;
    final align = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    // "enviado"/"visto agora" only on the SESSION user's newest message.
    final showStatus = mine && isLast;
    final statusText = message.readAt != null ? 'visto agora' : 'enviado';

    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      constraints: const BoxConstraints(maxWidth: _maxWidth),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spaceMd,
        vertical: AppDimensions.spaceSm,
      ),
      decoration: BoxDecoration(
        color: mine ? AppColors.primaryBlue : AppColors.bluishBlack,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppDimensions.radiusLg),
          topRight: const Radius.circular(AppDimensions.radiusLg),
          bottomLeft: Radius.circular(
              mine ? AppDimensions.radiusLg : AppDimensions.radiusSm),
          bottomRight: Radius.circular(
              mine ? AppDimensions.radiusSm : AppDimensions.radiusLg),
        ),
        boxShadow: mine
            ? [BoxShadow(color: AppColors.glowSmall, blurRadius: 6)]
            : const [],
      ),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reply quote (visual only — both the message content and the
          // original stay untouched; the preview is resolved server-side).
          if (message.replyTo != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              decoration: BoxDecoration(
                color: AppColors.absoluteBlack.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                border: Border(
                  left: BorderSide(color: AppColors.electricBlue, width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.replyTo!.exists
                        ? message.replyTo!.senderNickname
                        : 'Mensagem apagada',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.electricBlue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    message.replyTo!.exists
                        ? message.replyTo!.content
                        : '(a mensagem original foi apagada)',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: mine
                          ? AppColors.techWhite.withValues(alpha: 0.85)
                          : AppColors.holographicBlue,
                    ),
                  ),
                ],
              ),
            ),
          if (message.isVoice)
            VoicePlayerBubble(message: message, mine: mine)
          else
            Text(
              message.content,
              style: AppTextStyles.body.copyWith(color: AppColors.techWhite),
            ),
          const SizedBox(height: 2),
          // Status + time. Status only on my newest message; time always.
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (showStatus) ...[
                Text(statusText, style: _statusStyle(mine)),
                const SizedBox(width: 6),
              ],
              Text(
                chatClock(message.createdAt),
                style: _clockStyle(mine),
              ),
            ],
          ),
        ],
      ),
    );

    return _ReplySwipe(
      message: message,
      index: index,
      mine: mine,
      align: align,
      bubble: bubble,
      firstOfRun: firstOfRun,
      peerName: peerName,
      peerAvatar: peerAvatar,
      onStartReply: onStartReply,
      onLongPress: onLongPress,
      replySelected: replySelected,
    );
  }

  TextStyle _statusStyle(bool mine) => TextStyle(
        fontSize: 10,
        color: mine
            ? AppColors.techWhite.withValues(alpha: 0.75)
            : AppColors.holographicBlue,
        fontFamily: 'JetBrainsMono',
        fontWeight: FontWeight.w500,
      );

  TextStyle _clockStyle(bool mine) => TextStyle(
        fontSize: 10,
        color: mine
            ? AppColors.techWhite.withValues(alpha: 0.7)
            : AppColors.holographicBlue,
        fontFamily: 'JetBrainsMono',
      );
}

/// Wraps a bubble with the left→right swipe-to-reply gesture. Each bubble
/// carries its OWN drag state (StatefulWidget) so swiping one never affects
/// its siblings. During the drag the bubble follows the finger (capped at
/// [_replySwipeThreshold], so it can never leave the screen); when the drag
/// releases past the threshold the message is selected for reply, otherwise
/// it snaps back with a short ease-out animation.
class _ReplySwipe extends StatefulWidget {
  const _ReplySwipe({
    required this.message,
    required this.index,
    required this.mine,
    required this.align,
    required this.bubble,
    this.firstOfRun = true,
    this.peerName,
    this.peerAvatar,
    required this.onStartReply,
    required this.onLongPress,
    this.replySelected = false,
  });

  final ChatMessage message;
  final int index;
  final bool mine;
  final CrossAxisAlignment align;
  final Widget bubble;
  final bool firstOfRun;
  final String? peerName;
  final String? peerAvatar;
  final void Function(int index) onStartReply;
  final VoidCallback onLongPress;
  final bool replySelected;

  @override
  State<_ReplySwipe> createState() => _ReplySwipeState();
}

class _ReplySwipeState extends State<_ReplySwipe> {
  /// Current displacement magnitude (0 when idle/selected.). Direction
  /// is implied by the owner: theirs drags left→right (positive); mine drags
  /// right→left toward the reply affordance (also positive after flipping).
  double _dx = 0;

  bool get _selected => widget.replySelected;

  @override
  void didUpdateWidget(covariant _ReplySwipe old) {
    super.didUpdateWidget(old);
    // When the parent marks this message as the reply target, settle at the
    // pinned offset; when it deselects, snap back.
    if (widget.replySelected != old.replySelected) {
      _dx = widget.replySelected ? _replySwipeThreshold : 0;
    }
  }

  void _endDragAndMaybeSelect() {
    if (_dx >= _replyDragThreshold) {
      widget.onStartReply(widget.index);
    } else {
      setState(() => _dx = 0); // snap back
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.mine;
    final dir =
        mine ? -1.0 : 1.0; // flip drag so BOTH sides swipe toward the arrow
    return GestureDetector(
      // Long-press on a message bubble opens the contextual actions menu
      // (Responder / Excluir / Excluir para todos).
      onLongPress: widget.onLongPress,
      onHorizontalDragUpdate: (details) {
        if (_selected) return; // already replying another message
        setState(() {
          _dx = (_dx + details.delta.dx * dir).clamp(0.0, _replySwipeThreshold);
        });
      },
      onHorizontalDragEnd: (_) => _endDragAndMaybeSelect(),
      onHorizontalDragCancel: () => setState(() => _dx = 0),
      child: AnimatedContainer(
        duration: _selected ? Duration.zero : const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(_dx * dir, 0, 0),
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: widget.align,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Profile picture of the OTHER sender, shown to the LEFT of
                // received messages (matches [FOTO] [MENSAGEM]). Hidden
                // on my own messages —the layout stays clean. Replies and
                // voice messages ALWAYS keep it (firstOfRun force-cs true,
                // so a burst of five normal bubbles wears it only once,, then
                // the next group's first normal brings it back).
                if (!widget.mine &&
                    widget.peerName != null &&
                    widget.firstOfRun)
                  Padding(
                    padding: const EdgeInsets.only(right: 5, bottom: 4),
                    child: UserAvatar(
                      key: ValueKey('peer-avatar-${widget.message.id}'),
                      name: widget.peerName!,
                      imageUrl: widget.peerAvatar,
                      // Proportional to the 300px-max bubble — keeping the
                      // received layout balanced (MATRIX's visual format).
                      size: 38,
                      seed: widget.peerName,
                    ),
                  ),
                // Reply affordance that lights up as the swipe approaches.
                AnimatedOpacity(
                  opacity: _selected || _dx > 8 ? 0.9 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Icon(
                    Icons.reply_rounded,
                    color: AppColors.electricBlue,
                    size: 18,
                  ),
                ),
                widget.bubble,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom composer: message input + send button, riding the keyboard.
class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.enabled,
    required this.onChanged,
    required this.onSend,
    required this.onTapMic,
    required this.onMicLongPressStart,
    required this.onMicLongPressEnd,
    required this.onMicDragUpdate,
    required this.recorder,
    required this.dragDx,
    required this.dragDy,
    required this.dragCancelZone,
    required this.dragLocked,
    required this.voiceSending,
  });

  final TextEditingController controller;
  final bool sending;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  /// Tap (short) → "segure para gravar áudio". Long-press starts recording.
  final VoidCallback onTapMic;
  final void Function(LongPressStartDetails) onMicLongPressStart;
  final VoidCallback onMicLongPressEnd;
  final void Function(Offset delta) onMicDragUpdate;
  final VoiceRecorderController recorder;
  final double dragDx;
  final double dragDy;

  /// Whether the finger is inside the cancel zone (drag left, under threshold)
  /// — drives the red cancel tint feedback.

  final bool dragCancelZone;
  final bool dragLocked;
  final bool voiceSending;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  @override
  Widget build(BuildContext context) {
    // The mic button stays mounted in every state (idle/recording/locked/
    // sending/. Only the left area swaps between the text field and the recording
    // status bar. The gesture recognizers live on the mic button, so keeping
    // it in place lets the hold → release → send chain complete (see class doc).
    final captureActive =
        widget.recorder.state == VoiceRecorderState.recording ||
            widget.recorder.state == VoiceRecorderState.locked;
    final barShown = captureActive || widget.voiceSending;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.navBarBackground,
        border: Border(
          top: BorderSide(
            color: AppColors.primaryBlue,
            width: AppDimensions.borderWidthThin,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spaceLg,
            vertical: AppDimensions.spaceSm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: barShown
                    ? _RecordingBar(
                        recorder: widget.recorder,
                        locking: widget.dragLocked,
                        dragDx: widget.dragDx,
                        dragDy: widget.dragDy,
                        cancelZone: widget.dragCancelZone,
                        sending: widget.voiceSending,
                      )
                    : MatrixTextField(
                        hint: 'Escreva sua mensagem...',
                        controller: widget.controller,
                        enabled: widget.enabled,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.newline,
                        onChanged: (v) {
                          setState(() {});
                          widget.onChanged(v);
                        },
                      ),
              ),
              const SizedBox(width: AppDimensions.spaceSm),
              _MicButton(
                onTap: widget.onTapMic,
                onLongPressStart: widget.onMicLongPressStart,
                onLongPressEnd: widget.onMicLongPressEnd,
                onDrag: widget.onMicDragUpdate,
                enabled: widget.enabled && !widget.voiceSending,
                state: widget.recorder.state,
                sending: widget.voiceSending,
                locking: widget.dragLocked,
                cancelZone: widget.dragCancelZone,
              ),
              if (!barShown) ...[
                const SizedBox(width: AppDimensions.spaceSm),
                _SendButton(
                  enabled: widget.enabled && !widget.sending,
                  sending: widget.sending,
                  onTap: widget.onSend,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.sending,
    required this.onTap,
  });

  final bool enabled;
  final bool sending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final canSend = enabled && !sending;
    return GestureDetector(
      onTap: canSend ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: canSend ? AppColors.primaryBlue : AppColors.deepBlue,
          shape: BoxShape.circle,
          boxShadow: canSend
              ? [BoxShadow(color: AppColors.glowSmall, blurRadius: 8)]
              : const [],
        ),
        child: sending
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.techWhite,
                ),
              )
            : Icon(
                Icons.arrow_forward_rounded,
                color:
                    canSend ? AppColors.techWhite : AppColors.holographicBlue,
                size: 22,
              ),
      ),
    );
  }
}

/// The capture button between the text field and the send button. A SHORT
/// tap shows the "segure para gravar áudio" hint; a HOLD starts recording
/// immediately. Dragging UP locks the take; dragging LEFT cancels it.
/// The button stays mounted in the SAME slot in every state (the composer
/// only swaps the text area) so the long-press/drag recognizers survive the
/// whole hold→release→send sequence (the classic "stuck gravando" bug).
/// Its surface reflects the recorder state: idle→mic, recording→glowing
/// recording mic, locked→send icon (tap to send,, uploading→spinner.
class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
    required this.onDrag,
    required this.enabled,
    required this.state,
    required this.sending,
    required this.locking,
    required this.cancelZone,
  });

  final VoidCallback onTap;

  final void Function(LongPressStartDetails) onLongPressStart;

  final VoidCallback onLongPressEnd;

  final void Function(Offset delta) onDrag;

  final bool enabled;

  final VoiceRecorderState state;

  final bool sending;

  final bool locking;

  final bool cancelZone;

  @override
  Widget build(BuildContext context) {
    final showingSpinner = sending;
    final showingLockedSend = locking && !sending;
    final showingCancel = cancelZone && !locking && !sending;
    final recordingActive = state == VoiceRecorderState.recording ||
        state == VoiceRecorderState.locked;
    final Color bg;
    final IconData? icon;
    if (showingSpinner) {
      bg = AppColors.nightBlue;
      icon = null;
    } else if (showingCancel) {
      bg = AppColors.error;
      icon = Icons.close_rounded;
    } else if (showingLockedSend) {
      bg = AppColors.primaryBlue;
      icon = Icons.send_rounded;
    } else if (recordingActive) {
      bg = AppColors.electricBlue.withValues(alpha: 0.18);
      icon = Icons.mic_rounded;
    } else {
      bg = AppColors.nightBlue;
      icon = Icons.mic_rounded;
    }
    return GestureDetector(
      onTap: enabled ? onTap : null,
      onLongPressStart: enabled ? onLongPressStart : null,
      onLongPressEnd: enabled ? (details) => onLongPressEnd() : null,
      onLongPressMoveUpdate: enabled ? (d) => onDrag(d.offsetFromOrigin) : null,
      // The long-press recognizer wins over the tap, so a SHORT tap fires
      // onTap (the "segure para gravar" hint / locked "send")and a HOLD
      // starts recording; the recording surface itself never owns gestures.

      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bg,
          border: Border.all(
            color: showingCancel
                ? AppColors.error
                : (showingLockedSend
                    ? AppColors.techWhite.withValues(alpha: 0.6)
                    : AppColors.holographicBlue),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: showingCancel || showingLockedSend || recordingActive
                  ? AppColors.glowStrong
                  : AppColors.glowSmall,
              blurRadius: showingCancel ? 10 : 6,
            ),
          ],
        ),
        child: showingSpinner
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.techWhite,
                ),
              )
            : Icon(
                icon ?? Icons.mic_rounded,
                color: showingLockedSend
                    ? AppColors.techWhite
                    : (recordingActive
                        ? AppColors.electricBlue
                        : AppColors.techWhite),
                size: 22,
              ),
      ),
    );
  }
}

/// The recorder status surface swapped in place of the text field while a
/// capture is active or being uploaded. It shows the live waveform + elapsed
/// timer; dragging LEFT tints it red ("soltar para cancelar"), dragging UP
/// hints the take is about to lock ("solte para enviar"); once LOCKED it
/// shows the locked hint (the stable mic button beside it becomes the send
/// affordance),and while uploading it swaps to the "enviando audio..."
/// spinner (the mic button beside it shows the matching spinner).

class _RecordingBar extends StatelessWidget {
  const _RecordingBar({
    required this.recorder,
    required this.locking,
    required this.dragDx,
    required this.dragDy,
    required this.cancelZone,
    required this.sending,
  });

  final VoiceRecorderController recorder;

  final bool locking;

  final double dragDx;

  /// Live upward drag displacement (negative while pulled up).
  final double dragDy;

  /// Whetherthe finger is inside the cancel zone — red tint + "cancelar"
  /// hint feedback while dragging left.

  final bool cancelZone;

  /// Whetherthe recorded take is being uploaded/sent (spinner + "enviando
  /// audio..."), replacing the live waveform with a sending state.

  final bool sending;

  @override
  Widget build(BuildContext context) {
    final amp = recorder.amplitude;
    final bars = <Widget>[];
    if (!sending) {
      for (var i = 0; i < 28; i++) {
        // Weighted toward the center so the on-mic "pulse" reads naturally.

        final core = 1 - ((i - 13.5).abs() / 13.5);
        final h = 6 + (amp * 30 * (0.4 + 0.6 * core)).clamp(2.0, 34.0);
        bars.add(AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: 3,
          height: h,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: locking
                ? AppColors.holographicBlue
                : AppColors.primaryBlue.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(2),
          ),
        ));
      }
    }
    final lockHint = !locking && dragDy <= -40;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cancelZone
            ? AppColors.error.withValues(alpha: 0.15)
            : AppColors.absoluteBlack.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(
          color: cancelZone
              ? AppColors.error
              : (locking ? AppColors.electricBlue : AppColors.deepBlue),
        ),
      ),
      child: Row(
        children: [
          Icon(
            sending
                ? Icons.cloud_upload_rounded
                : locking
                    ? Icons.lock_rounded
                    : (cancelZone
                        ? Icons.cancel_rounded
                        : Icons.graphic_eq_rounded),
            color: cancelZone
                ? AppColors.error
                : (sending || locking
                    ? AppColors.techWhite
                    : AppColors.electricBlue),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: sending
                    ? const Row(
                        key: ValueKey('sending'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'enviando audio...',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.electricBlue,
                              fontFamily: 'JetBrainsMono',
                            ),
                          ),
                        ],
                      )
                    : cancelZone
                        ? const Padding(
                            key: ValueKey('cancel'),
                            padding: EdgeInsets.zero,
                            child: Text(
                              'soltar para cancelar',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.error,
                                fontFamily: 'JetBrainsMono',
                              ),
                            ),
                          )
                        : lockHint
                            ? const Padding(
                                key: ValueKey('lock'),
                                padding: EdgeInsets.zero,
                                child: Text(
                                  'solte para enviar',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.electricBlue,
                                    fontFamily: 'JetBrainsMono',
                                  ),
                                ),
                              )
                            : Row(
                                key: const ValueKey('wave'),
                                mainAxisSize: MainAxisSize.min,
                                children: bars,
                              ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _clockText(recorder.elapsed),
            style: TextStyle(
              color: AppColors.techWhite,
              fontFamily: 'JetBrainsMono',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _clockText(Duration d) {
    final s = d.inSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

/// The "Respondendo a …" bar shown above the composer while a reply is
/// selected:the original message's author + truncated preview + a ✕ close.
class _ReplyPreviewBar extends StatelessWidget {
  const _ReplyPreviewBar({
    super.key,
    required this.target,
    required this.onCancel,
  });

  final ChatMessage target;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    // The swiped message is itself the original being replied to — show its
    // own preview (the server separately renders the quote inside bubble).
    final preview = target.content.isNotEmpty ? target.content : 'mensagem';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.navBarBackground,
        border: Border(
          top: BorderSide(color: AppColors.electricBlue, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.spaceLg,
        AppDimensions.spaceSm,
        AppDimensions.spaceSm,
        AppDimensions.spaceSm,
      ),
      child: Row(
        children: [
          const Icon(Icons.reply_rounded,
              color: AppColors.electricBlue, size: 18),
          const SizedBox(width: AppDimensions.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Respondendo a mensagem',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.electricBlue,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'JetBrainsMono',
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '“$preview”',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.holographicBlue,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded,
                color: AppColors.holographicBlue, size: 20),
            onPressed: onCancel,
            tooltip: 'Cancelar resposta',
          ),
        ],
      ),
    );
  }
}

/// Actions a user can take on a message via the long-press menu.
enum _MessageAction { reply, deleteForMe, deleteForEveryone }

/// Bottom menu shown when a message bubble is long-pressed. Options respect
/// the real (server-validated) rules: replying is always allowed; "Excluir"
/// removes the message only for ME; "Excluir para todos" removes it for every
/// participant.
class _MessageActionMenu extends StatelessWidget {
  const _MessageActionMenu({required this.message, required this.index});

  final ChatMessage message;
  final int index;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(AppDimensions.spaceMd),
        padding: const EdgeInsets.symmetric(vertical: AppDimensions.spaceXs),
        decoration: BoxDecoration(
          color: AppColors.bluishBlack,
          borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
          border: Border.all(color: AppColors.deepBlue),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 20,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionItem(
                icon: Icons.reply_rounded,
                label: 'Responder',
                onTap: () => Navigator.of(context).pop(_MessageAction.reply),
              ),
              _ActionItem(
                icon: Icons.remove_circle_outline_rounded,
                iconColor: AppColors.holographicBlue,
                label: 'Excluir',
                hint: 'só para mim',
                onTap: () =>
                    Navigator.of(context).pop(_MessageAction.deleteForMe),
              ),
              _ActionItem(
                icon: Icons.delete_forever_rounded,
                iconColor: AppColors.error,
                label: 'Excluir para todos',
                onTap: () =>
                    Navigator.of(context).pop(_MessageAction.deleteForEveryone),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final Color? iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: Icon(icon, color: iconColor ?? AppColors.electricBlue, size: 22),
      title: Text(
        label,
        style: AppTextStyles.body.copyWith(color: AppColors.techWhite),
      ),
      trailing: hint == null
          ? null
          : Text(hint!, style: AppTextStyles.hud.copyWith(fontSize: 10)),
    );
  }
}
