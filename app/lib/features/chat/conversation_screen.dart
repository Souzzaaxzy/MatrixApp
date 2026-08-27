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
import '../../data/api_config.dart';
import '../../models/conversation.dart';
import 'chat_navigation.dart';

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

class _ConversationScreenState extends State<ConversationScreen> {
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

  StreamSubscription<ChatMessage>? _chatSub;
  StreamSubscription<ChatTypingEvent>? _typingSub;
  StreamSubscription<ChatReadEvent>? _readSub;
  StreamSubscription<ChatMessageDeletedEvent>? _deletedSub;

  /// Whether the newest message is pinned to the bottom (auto-follow new).
  bool _followBottom = true;

  // ── "digitando..." (peer typing) ───────────────────────────
  bool _peerTyping = false;
  Timer? _typingAutoClear;

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
      _readSub?.cancel();
      _readSub = state?.onChatRead.listen(_onReadReceipt);
      _deletedSub?.cancel();
      _deletedSub = state?.onChatMessageDeleted.listen(_onMessageDeletedRealtime);
    }
    if (!_loadRequested) {
      // Defer the load: _load notifies listeners synchronously.
      _loadRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }
  bool _loadRequested = false;

  @override
  void dispose() {
    _disposeCalled = true;
    _chatSub?.cancel();
    _typingSub?.cancel();
    _readSub?.cancel();
    _deletedSub?.cancel();
    _typingAutoClear?.cancel();
    _typingSendDebounce?.cancel();
    if (_typingLastSent) {
      final id = _conversationId;
      if (id.isNotEmpty) _state?.sendTyping(id, false);
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _conversationId {
    if (widget.args.conversationId.isNotEmpty) return widget.args.conversationId;
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
        conversation = await state.getOrCreateConversation(widget.args.otherUserId);
        if (!mounted) return;
      } else if (conversation == null || conversation.id == _conversationId) {
        // Reuse the cached conversation if present, else fetch a fresh one.
        final cached = state.conversations
            .where((c) => c.id == _conversationId)
            .firstOrNull;
        if (cached != null) {
          conversation = cached;
        } else {
          conversation = await state.getOrCreateConversation(widget.args.otherUserId);
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível enviar a mensagem.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
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
        _messages.insertAll(0, page.messages.where((m) => !_messages.any((x) => x.id == m.id)));
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
              // Realtime "digitando..." directly below the nickname (only in
              // a live conversation with a peer). Centered.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, -0.05), end: Offset.zero)
                        .animate(anim),
                    child: child,
                  ),
                ),
                child: _peerTyping && conversation != null
                    ? const Padding(
                        key: ValueKey('typing'),
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
        titleTextStyle: AppTextStyles.h3.copyWith(fontSize: 19, color: AppColors.techWhite),
        toolbarHeight: kToolbarHeight + (_peerTyping ? 18 : 0),
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
                  position: Tween(begin: const Offset(0, 0.05), end: Offset.zero)
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

  Widget _buildThread(Conversation? conversation, ChatUser other) {
    if (_loading) {
      return const Center(child: HudLabel(text: 'CARREGANDO MENSAGENS...', dot: true));
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.spaceXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, color: AppColors.error, size: 40),
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
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final day = DateTime(m.createdAt.year, m.createdAt.month, m.createdAt.day);
      if (lastDay == null || lastDay != day) {
        lastDay = day;
        items.add(_DaySeparator(label: chatDayLabel(m.createdAt)));
      }
      // Whether this is the newest message OF THE WHOLE LIST (only that one
      // shows the "enviado"/"visto agora" hint). Slots ease updates when a
      // message shifts position.
      final isLast = i == _messages.length - 1;
      items.add(_MessageBubble(
        message: m,
        index: i,
        isLast: isLast,
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
                      child: Center(child: HudLabel(text: 'CARREGANDO...', dot: true)),
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
          const SliverToBoxAdapter(child: SizedBox(height: AppDimensions.spaceMd)),
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
    required this.onStartReply,
    required this.onLongPress,
    this.replySelected = false,
  });

  final ChatMessage message;
  final int index;
  final bool isLast;
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
          bottomLeft: Radius.circular(mine ? AppDimensions.radiusLg : AppDimensions.radiusSm),
          bottomRight: Radius.circular(mine ? AppDimensions.radiusSm : AppDimensions.radiusLg),
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
    required this.onStartReply,
    required this.onLongPress,
    this.replySelected = false,
  });

  final ChatMessage message;
  final int index;
  final bool mine;
  final CrossAxisAlignment align;
  final Widget bubble;
  final void Function(int index) onStartReply;
  final VoidCallback onLongPress;
  final bool replySelected;

  @override
  State<_ReplySwipe> createState() => _ReplySwipeState();
}

class _ReplySwipeState extends State<_ReplySwipe> {
  /// Current horizontal displacement (0 when idle/selected).
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
    return GestureDetector(
      // Long-press on a message bubble opens the contextual actions menu
      // (Responder / Excluir / Excluir para todos).
      onLongPress: widget.onLongPress,
      onHorizontalDragUpdate: (details) {
        if (_selected) return; // already replying another message
        setState(() {
          _dx = (_dx + details.delta.dx).clamp(0.0, _replySwipeThreshold);
        });
      },
      onHorizontalDragEnd: (_) => _endDragAndMaybeSelect(),
      onHorizontalDragCancel: () => setState(() => _dx = 0),
      child: AnimatedContainer(
        duration: _selected
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(_dx, 0, 0),
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: widget.align,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
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
  });

  final TextEditingController controller;
  final bool sending;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  @override
  Widget build(BuildContext context) {
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
                child: MatrixTextField(
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
              _SendButton(
                enabled: widget.enabled && !widget.sending,
                sending: widget.sending,
                onTap: widget.onSend,
              ),
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
                color: canSend ? AppColors.techWhite : AppColors.holographicBlue,
                size: 22,
              ),
      ),
    );
  }
}

/// The "Respondendo a …" bar shown above the composer while a reply is
/// selected: the original message's author + truncated preview + a ✕ close.
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
          const Icon(Icons.reply_rounded, color: AppColors.electricBlue, size: 18),
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
                onTap: () => Navigator.of(context).pop(_MessageAction.deleteForMe),
              ),
              _ActionItem(
                icon: Icons.delete_forever_rounded,
                iconColor: AppColors.error,
                label: 'Excluir para todos',
                onTap: () => Navigator.of(context).pop(_MessageAction.deleteForEveryone),
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