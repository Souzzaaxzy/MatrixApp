import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/services/app_state.dart';
import '../../core/utils/chat_format.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/matrix_text_field.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/api_config.dart';
import '../../models/conversation.dart';
import 'chat_navigation.dart';
import 'voice_player_bubble.dart';
import 'voice_recorder.dart';

const _typingTimeout = Duration(seconds: 4);

class GroupConversationScreen extends StatefulWidget {
  const GroupConversationScreen({super.key, required this.args});

  final GroupConversationRouteArgs args;

  @override
  State<GroupConversationScreen> createState() =>
      _GroupConversationScreenState();
}

class _GroupConversationScreenState extends State<GroupConversationScreen> {
  static const _pagesize = 30;

  GroupConversationRouteArgs? _args;
  String? _groupName;
  String? _groupAvatarUrl;
  String _groupDescription = '';
  String? _groupOwnerId;
  int _groupMemberCount = 0;
  StreamSubscription<GroupUpdatedEvent>? _groupSub;

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _loadingOlder = false;
  bool _hasMore = true;
  String? _error;
  ChatMessage? _replyTarget;

  final VoiceRecorderController _recorder = VoiceRecorderController();
  VoidCallback? _recListener;
  bool _recording = false;
  bool _voiceSending = false;
  bool _recordingSignaled = false;

  StreamSubscription<ChatMessage>? _chatSub;
  StreamSubscription<ChatTypingEvent>? _typingSub;
  StreamSubscription<ChatRecordingEvent>? _recordingSub;
  StreamSubscription<ChatReadEvent>? _readSub;
  StreamSubscription<ChatMessageDeletedEvent>? _deletedSub;

  final bool _followBottom = true;
  bool _peerTyping = false;
  Timer? _typingAutoClear;
  bool _peerRecording = false;
  Timer? _recordingAutoClear;
  Timer? _typingSendDebounce;
  bool _typingLastSent = false;
  bool _loadRequested = false;

  AppState? _resolvedState;
  AppState? get _state => _resolvedState;
  String get _groupId => widget.args.groupId;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scrollListener);
  }

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
      _readSub = state?.onChatRead.listen(_onRead);
      _deletedSub?.cancel();
      _deletedSub = state?.onChatMessageDeleted.listen(_onMessageDeleted);
      _groupSub?.cancel();
      _groupSub = state?.onGroupUpdated.listen(_onGroupUpdated;
    }
    if (!_loadRequested) {
      _loadRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    if (_recListener == null) {
      _recListener = () {
        if (mounted) setState(() {});
      };
      _recorder.addListener(_recListener!);
    }
  }

  @override
  void dispose() {
    if (_recordingSignaled) {
      _state?.sendGroupRecording(_groupId, false);
    }
    _chatSub?.cancel();
    _typingSub?.cancel();
    _recordingSub?.cancel();
    _readSub?.cancel();
    _deletedSub?.cancel();
    _groupSub?.cancel();
    if (_recListener != null) {
      _recorder.removeListener(_recListener!);
      _recListener = null;
    }
    _typingAutoClear?.cancel();
    _typingSendDebounce?.cancel();
    _recordingAutoClear?.cancel();
    if (_typingLastSent) {
      _state?.sendGroupTyping(_groupId, false);
    }
    _recorder.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = _state;
    if (state == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await state.loadGroupMessages(_groupId, limit: _pagesize);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(page.messages);
        _hasMore = page.hasMore;
        _loading = false;
        _applyFreshHeader();
      });
      unawaited(state.markGroupRead(_groupId));
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
        _error = 'Não foi possível carregar o grupo. Verifique sua conexão.';
      });
    }
  }

  /// Refreshes the header from the current AppState cache if available — the
  /// cache is fed by the group list and by real-time `group_updated` frames, so
  /// the AppBar always reflects the persisted group identity (never a stale
  /// snapshot from the route argument)). Falls back to the route payload..
  void _applyFreshHeader() {
    final groups = _state?.groups ?? const <GroupConversation>[];
    GroupConversation? group;
    for (final g in groups) {
      if (g.id == _groupId) { group = g; break; }
    }
    if (group == null) return;
    _groupName = group.name;
    _groupAvatarUrl = group.avatarUrl;
    _groupDescription = group.description;
    _groupOwnerId = group.createdById;
    _groupMemberCount = group.memberCount;
  }

  /// An owner edited the group (name/avatar/description/membership). The
  /// server pushed a fresh header; update the AppBar and cached fields live.
  void _onGroupUpdated(GroupUpdatedEvent event) {
    if (!mounted) return;
    if (event.groupId != _groupId) return;
    if (event.group.id != _groupId) return;
    setState(() {
      _groupName = event.group.name;
      _groupAvatarUrl = event.group.avatarUrl;
      _groupDescription = event.group.description;
      _groupOwnerId = event.group.createdById;
      _groupMemberCount = event.group.memberCount;
    });
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlder || _messages.isEmpty || !_hasMore) return;
    _loadingOlder = true;
    try {
      final page = await _state!.loadGroupMessages(
        _groupId,
        before: _messages.first.id,
        limit: _pagesize,
      );
      if (!mounted) return;
      if (page.messages.isEmpty) {
        _hasMore = false;
      } else {
        setState(() {
          _messages.insertAll(0, page.messages);
          _hasMore = page.hasMore;
        });
      }
    } catch (_) {
      // Silent: next scroll retry.
    } finally {
      if (mounted) _loadingOlder = false;
    }
  }

  void _appendMessage(ChatMessage message) {
    if (_messages.any((m) => m.id == message.id)) return;
    setState(() => _messages.add(message));
    if (_followBottom) _jumpToBottom();
  }

  void _onRealtime(ChatMessage message) {
    if (!mounted) return;
    if (message.groupId != _groupId) return;
    if (message.senderId == _state?.currentUser?.id) return;
    _appendMessage(message);
  }

  void _onMessageDeleted(ChatMessageDeletedEvent event) {
    if (!mounted) return;
    if (event.groupId != _groupId) return;
    if (event.messageId.isEmpty) return;
    setState(() {
      _messages.removeWhere((m) => m.id == event.messageId);
      if (_replyTarget?.id == event.messageId) {
        _replyTarget = null;
      }
    });
  }

  void _onTyping(ChatTypingEvent event) {
    if (!mounted) return;
    if (event.groupId != _groupId) return;
    if (event.typing) {
      _peerTyping = true;
      _typingAutoClear?.cancel();
      _typingAutoClear = Timer(_typingTimeout, () {
        if (mounted) setState(() => _peerTyping = false);
      });
    } else {
      _peerTyping = false;
      _typingAutoClear?.cancel();
    }
    setState(() {});
  }

  void _onRecording(ChatRecordingEvent event) {
    if (!mounted) return;
    if (event.groupId != _groupId) return;
    if (event.recording) {
      _peerRecording = true;
      _recordingAutoClear?.cancel();
      _recordingAutoClear = Timer(_typingTimeout, () {
        if (mounted) setState(() => _peerRecording = false);
      });
    } else {
      _peerRecording = false;
      _recordingAutoClear?.cancel();
    }
    setState(() {});
  }

  void _onRead(ChatReadEvent event) {
    // Group read receipts are coarse — no per-message flip here:the server
    // persists reads; individual readAt comes embedded when available.
  }

  void _scrollListener() {
    if (_scroll.position.pixels <= 120.0 && _hasMore && !_loadingOlder) {
      unawaited(_loadOlderMessages());
    }
  }

  void _jumpToBottom() {
    if (!mounted || !_scroll.hasClients) return;
    final pos = _scroll.position.maxScrollExtent;
    _scroll.jumpTo(pos);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final reply = _replyTarget;
    setState(() => _sending = true);
    try {
      final message = await _state!.sendGroupChatMessage(
        _groupId,
        text,
        replyToMessageId: reply?.id,
      );
      if (!mounted) return;
      _input.clear();
      setState(() {
        _replyTarget = null;
      });
      _appendMessage(message);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível enviar a mensagem.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendVoice() async {
    if (_voiceSending) return;
    if (_recorder.state != VoiceRecorderState.locked &&
        _recorder.state != VoiceRecorderState.recording) {
      return;
    }
    if (_recorder.state == VoiceRecorderState.recording) {
      _recorder.lock();
    }
    setState(() {
      _voiceSending = true;
      _recording = false;
    });
    await null;
    final file = await _recorder.finish();
    if (_recordingSignaled) {
      _recordingSignaled = false;
      _state?.sendGroupRecording(_groupId, false);
    }
    if (!mounted) return;
    if (file == null) {
      setState(() => _voiceSending = false);
      _recorder.resetToIdle();
      return;
    }
    final durationMs = _recorder.elapsed.inMilliseconds.clamp(1000, 60000);
    try {
      final message = await _state!.sendGroupVoiceMessage(
        _groupId,
        file,
        durationMs: durationMs,
      );
      _appendMessage(message);
      unawaited(_state!.markGroupRead(_groupId));
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
      _recorder.resetToIdle();
    }
  }

  void _startReply(int index) async {
    if (index < 0 || index >= _messages.length) return;
    setState(() {
      _replyTarget = _messages[index];
    });
  }

  Future<void> _showMessageMenu(int index) async {
    if (index < 0 || index >= _messages.length) return;
    final message = _messages[index];
    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      isScrollControlled: true,
      builder: (_) => _MessageActionSheet(message: message),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _MessageAction.reply:
        _startReply(_messages.indexOf(message));
      case _MessageAction.deleteForMe:
        await _confirmDeleteForMe(message);
      case _MessageAction.deleteForEveryone:
        await _confirmDeleteForEveryone(message);
    }
  }

  Future<void> _confirmDeleteForMe(ChatMessage message) async {
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
          style: AppTextStyles.hud
              .copyWith(fontSize: 16, color: AppColors.techWhite),
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
    final ok = await _state?.deleteGroupMessageForMe(_groupId, message.id);

    if (!mounted) return;
    if (ok == true) {
      setState(() => _messages.removeWhere((m) => m.id == message.id));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível excluir a mensagem.')),
      );
    }
  }

  Future<void> _confirmDeleteForEveryone(ChatMessage message) async {
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
          'Excluir para todos?',
          style: AppTextStyles.hud
              .copyWith(fontSize: 16, color: AppColors.techWhite),
        ),
        content: Text(
          'A mensagem será removida para todos os membros.',
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
        await _state?.deleteGroupMessageForEveryone(_groupId, message.id);
    if (!mounted) return;
    if (ok != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível excluir a mensagem.')),
      );
    }
  }

  void _onComposerChanged(String _) {
    final typing = _input.text.trim().isNotEmpty;
    if (typing != _typingLastSent) {
      _typingLastSent = typing;
      _typingSendDebounce?.cancel();
      _typingSendDebounce = Timer(const Duration(milliseconds: 400), () {
        _state?.sendGroupTyping(_groupId, typing);
      });
    }
  }

  void _onMicTap() async {
    if (_recording) {
      setState(() => _recording = false);
      if (_recordingSignaled) {
        _recordingSignaled = false;
        _state?.sendGroupRecording(_groupId, false);
      }
      unawaited(_sendVoice());
      return;
    }
    final ok = await _recorder.start();
    if (!mounted) return;
    if (ok) {
      setState(() {
        _recording = true;
        _recordingSignaled = true;
      });
      _state?.sendGroupRecording(_groupId, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível iniciar a gravação.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _groupName ?? _args?.groupName ?? widget.args.groupName;
    final avatar = _groupAvatarUrl ?? _args?.groupAvatarUrl ?? widget.args.groupAvatarUrl;

    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      // Default IME handling — the Scaffold resizes with the Android keyboard so
      // the composer sits directly above it (same proven behavior as the DM chat;
      // no fixed-pixel hacks for the nav bar or insets).
      appBar: AppBar(
        backgroundColor: AppColors.absoluteBlack,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: true,
        centerTitle: true,
        toolbarHeight: kToolbarHeight + 52,
        title: GestureDetector(
          onTap: _openGroupProfile,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _GroupAvatar(
                  size: 72,
                  url: avatar,
                  name: name),
              const SizedBox(height: 6),
              Text(
                name,
                textAlign: TextAlign.center,
                style: AppTextStyles.hud.copyWith(
                  fontSize: 18,
                  color: AppColors.techWhite,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (_groupMemberCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${_groupMemberCount} membro${_groupMemberCount == 1 ? '' : 's'}',
                    style: AppTextStyles.caption.copyWith(
                        fontSize: 11, color: AppColors.holographicBlue),
                  ),
                ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _buildBody(),
      ),
    );
  }

  /// Opens the group profile menu (stage 3). The header (avatar/name)
  /// doubles as its entry point;the profile pushes a fresh route so the
  /// conversation state survives underneath (popped back intact).
  void _openGroupProfile() {
    if (_groupId.isEmpty) return;
    Navigator.of(context).pushNamed(
      AppRoutes.groupProfile,
      arguments: GroupProfileRouteArgs(
        groupId: _groupId,
        initialName: _groupName ?? _args?.groupName ?? widget.args.groupName,
        initialAvatarUrl:
            _groupAvatarUrl ?? _args?.groupAvatarUrl ?? widget.args.groupAvatarUrl,
        initialDescription: _groupDescription,
        initialOwnerId: _groupOwnerId,
        initialMemberCount: _groupMemberCount,
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.spaceXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
              const SizedBox(height: AppDimensions.spaceMd),
              MatrixButton(
                label: 'TENTAR NOVAMENTE',
                expanded: false,
                onPressed: () => _load(),
              ),
            ],
          ),
        ),
      );
    }
    if (_loading && _messages.isEmpty) {
      return const Center(child: HudLabel(text: 'CARREGANDO...', dot: true));
    }
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: _messageList(),
          ),
        ),
        if (_peerTyping)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.spaceLg, vertical: 4),
            child: Row(children: [
              Text('Digitando...',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.holographicBlue)),
            ]),
          ),
        if (_peerRecording)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.spaceLg, vertical: 4),
            child: Row(children: [
              Text('Gravando áudio...',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.holographicBlue)),
            ]),
          ),
        _composer(),
      ],
    );
  }

  Widget _messageList() {
    if (_messages.isEmpty) {
      return ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(AppDimensions.spaceXl),
        children: [
          Center(
            child: Text('Nenhuma mensagem ainda. Seja o primeiro a escrever!',
                style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
          ),
        ],
      );
    }
    final items = <Widget>[];
    String? lastDay;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final day = chatDayLabel(m.createdAt);
      if (day != lastDay) {
        items.add(_DaySeparator(label: day));
        lastDay = day;
      }
      items.add(_GroupMessageBubble(
        message: m,
        mine: m.senderId == _state?.currentUser?.id,
        onLongPress: () => _showMessageMenu(i),
        replyingTo: (_replyTarget?.id == m.id) ? _replyTarget : null,
      ));
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: items.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) return const SizedBox(height: 12);
        final i = index - 1;
        if (i < items.length) {
          return items[i];
        }
        if (_loadingOlder) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: HudLabel(text: 'CARREGANDO...', dot: true)),
          );
        }
        return const SizedBox(height: 12);
      },
    );
  }

  Widget _composer() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(color: AppColors.deepBlue),
      ),
      margin: const EdgeInsets.fromLTRB(AppDimensions.spaceMd, 0,
          AppDimensions.spaceMd, AppDimensions.spaceMd),
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spaceSm, vertical: AppDimensions.spaceXs),
      child: Row(
        children: [
          Expanded(
            child: MatrixTextField(
              hint: 'Mensagem no grupo',
              controller: _input,
              onChanged: _onComposerChanged,
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onFieldSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          _recording
              ? _GroupPill(
                  icon: Icons.stop_rounded,
                  color: AppColors.error,
                  onTap: _onMicTap)
              : _GroupPill(
                  icon: Icons.mic_rounded,
                  color: AppColors.holographicBlue,
                  onTap: _onMicTap),
          const SizedBox(width: 8),
          IconButton(
            onPressed: (_sending || _voiceSending) ? null : () => _send(),
            icon: Icon(Icons.send_rounded, color: AppColors.holographicBlue),
          ),
        ],
      ),
    );
  }
}

class _GroupPill extends StatelessWidget {
  const _GroupPill(
      {required this.icon, required this.color, required this.onTap});

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(22),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 22, color: color),
      ),
    );
  }
}

class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({required this.size, this.url, this.name});

  final double size;
  final String? url;
  final String? name;

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(
            url!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(),
          ),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.deepBlue, AppColors.holographicBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        (name ?? 'G').isEmpty
            ? 'G'
            : (name ?? 'G').substring(0, 1).toUpperCase(),
        style: AppTextStyles.hud
            .copyWith(color: AppColors.techWhite, fontSize: 14),
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
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style:
                  AppTextStyles.caption.copyWith(color: AppColors.techWhite)),
        ),
      ),
    );
  }
}

class _GroupMessageBubble extends StatelessWidget {
  const _GroupMessageBubble({
    required this.message,
    required this.mine,
    this.onLongPress,
    this.replyingTo,
  });

  final ChatMessage message;
  final bool mine;
  final VoidCallback? onLongPress;
  final ChatMessage? replyingTo;

  @override
  Widget build(BuildContext context) {
    final sender = message.sender;
    final rowMain = mine ? MainAxisAlignment.end : MainAxisAlignment.start;
    final bubble = Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: mine
            ? AppColors.holographicBlue.withValues(alpha: 0.18)
            : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(
          color: mine
              ? AppColors.holographicBlue.withValues(alpha: 0.5)
              : AppColors.deepBlue,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (sender != null) ...[
            Text(
              '@${sender.nickname}',
              style: AppTextStyles.caption.copyWith(
                fontSize: 11,
                color: AppColors.holographicBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
          ],
          if (replyingTo != null) _ReplyQuote(reply: replyingTo!),
          _MessageContent(message: message),
          if (!mine) ...[
            const SizedBox(height: 4),
            Text(
              chatClock(message.createdAt),
              style: AppTextStyles.caption
                  .copyWith(fontSize: 10, color: AppColors.holographicBlue),
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: rowMain,
        crossAxisAlignment:
            mine ? CrossAxisAlignment.center : CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 8),
              child: UserAvatar(
                name: sender?.nickname ?? '?',
                seed: sender?.nickname,
                imageUrl: sender?.avatarUrl,
                size: 36,
              ),
            ),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: bubble,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({required this.reply});

  final ChatMessage reply;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.absoluteBlack.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border(
            left: BorderSide(color: AppColors.holographicBlue, width: 3)),
      ),
      child: Text(
        reply.content.isEmpty ? '🎤 Áudio' : reply.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.caption.copyWith(color: AppColors.holographicBlue),
      ),
    );
  }
}

class _MessageContent extends StatelessWidget {
  const _MessageContent({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.isVoice) {
      return VoicePlayerBubble(
          message: message,
          mine: message.senderId ==
              AppStateScope.maybeOf(context)?.currentUser?.id);
    }
    return Text(
      message.content,
      style: AppTextStyles.body.copyWith(color: AppColors.techWhite),
    );
  }
}

enum _MessageAction { reply, deleteForMe, deleteForEveryone }

class _MessageActionSheet extends StatelessWidget {
  const _MessageActionSheet({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bluishBlack,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionItem(
              icon: Icons.reply_rounded,
              label: 'Responder',
              onTap: () => Navigator.of(context).pop(_MessageAction.reply)),
          _ActionItem(
              icon: Icons.delete_outline_rounded,
              label: 'Excluir para mim',
              onTap: () =>
                  Navigator.of(context).pop(_MessageAction.deleteForMe)),
          _ActionItem(
              icon: Icons.delete_forever_rounded,
              label: 'Excluir para todos',
              onTap: () =>
                  Navigator.of(context).pop(_MessageAction.deleteForEveryone)),
        ],
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.holographicBlue),
      title: Text(label,
          style: AppTextStyles.body.copyWith(color: AppColors.techWhite)),
      onTap: onTap,
    );
  }
}
