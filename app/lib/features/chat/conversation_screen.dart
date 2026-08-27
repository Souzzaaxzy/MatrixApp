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

  /// Whether the newest message is pinned to the bottom (auto-follow new).
  bool _followBottom = true;

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
    _chatSub?.cancel();
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

    final controller = _input;
    setState(() => _sending = true);
    try {
      final message = await _state!.sendChatMessage(
        conversationId,
        text,
        otherUser: _conversation?.otherUser ?? widget.args.otherUser,
      );
      if (!mounted) return;
      controller.clear();
      setState(() {});
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
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimensions.spaceSm),
            child: NicknameRenderer(
              other.nickname,
              baseStyle: AppTextStyles.h3.copyWith(fontSize: 19),
              background: AppColors.absoluteBlack,
              nameColor: other.nameColor,
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ),
        ),
        titleTextStyle: AppTextStyles.h3.copyWith(fontSize: 19, color: AppColors.techWhite),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildThread(conversation, other)),
            _Composer(
              controller: _input,
              sending: _sending,
              enabled: conversation != null,
              onSend: _send,
            ),
          ],
        ),
      ),
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
    for (final m in _messages) {
      final day = DateTime(m.createdAt.year, m.createdAt.month, m.createdAt.day);
      if (lastDay == null || lastDay != day) {
        lastDay = day;
        items.add(_DaySeparator(label: chatDayLabel(m.createdAt)));
      }
      items.add(_MessageBubble(message: m));
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

/// A single message bubble. Sent messages align right; received align left.
/// Each bubble is independent (own rounded corners, own timestamp).
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.mine;
    final align = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      constraints: const BoxConstraints(maxWidth: 300),
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
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message.content,
            style: AppTextStyles.body.copyWith(
              color: mine ? AppColors.techWhite : AppColors.techWhite,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            chatClock(message.createdAt),
            style: TextStyle(
              fontSize: 10,
              color: mine
                  ? AppColors.techWhite.withValues(alpha: 0.7)
                  : AppColors.holographicBlue,
              fontFamily: 'JetBrainsMono',
            ),
          ),
        ],
      ),
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: align,
        mainAxisSize: MainAxisSize.min,
        children: [bubble],
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
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final bool enabled;
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
                  onChanged: (v) => setState(() {}),
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