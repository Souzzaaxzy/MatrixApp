import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/services/app_state.dart';
import '../../core/utils/chat_format.dart';
import '../../core/utils/profile_navigation.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/matrix_text_field.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/api_config.dart';
import '../../data/dtos/dtos.dart';
import '../../models/conversation.dart';
import '../../app/routes.dart';
import 'chat_navigation.dart';
import 'reply_swipe.dart';
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

class _GroupConversationScreenState extends State<GroupConversationScreen>
    with WidgetsBindingObserver {
  static const _pagesize = 30;

  GroupConversationRouteArgs? _args;
  String? _groupName;
  String? _groupAvatarUrl;
  String _groupDescription = '';
  String? _groupOwnerId;
  int _groupMemberCount = 0;
  StreamSubscription<GroupUpdatedEvent>? _groupSub;

  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
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
  StreamSubscription<GroupBannedEvent>? _bannedSub;
  StreamSubscription<GroupDeletedEvent>? _groupDeletedSub;

  bool _followBottom = true;
  final Set<String> _typingUsers = <String>{};
  final Map<String, String> _typingNames = <String, String>{};
  Timer? _typingAutoClear;
  final Set<String> _recordingUsers = <String>{};
  final Map<String, String> _recordingNames = <String, String>{};
  Timer? _recordingAutoClear;
  Timer? _typingSendDebounce;
  bool _typingLastSent = false;
  bool _loadRequested = false;

  // ── Mentions (@user + @todos) — WhatsApp-style inline suggestions ──
  List<GroupMemberInfoModel> _mentionMembers = const [];
  bool _mentionMembersLoaded = false;

  /// The member picker term the user typed after "@" (empty = show all).
  String _mentionQuery = '';

  /// Whether the inline suggestion bar is currently visible above the
  /// composer. Driven by the composer text + keyboard focus; never a modal.
  bool _showMentionSuggestions = false;

  /// Real user ids selected for the CURRENT draft (sent with the message).
  final Set<String> _draftMentionIds = <String>{};

  bool get _isGroupOwner =>
      _groupOwnerId != null &&
      _groupOwnerId!.isNotEmpty &&
      _state?.currentUser?.id == _groupOwnerId;

  AppState? _resolvedState;
  AppState? get _state => _resolvedState;
  String get _groupId => widget.args.groupId;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scrollListener);
    // Hide the mention suggestions when the composer loses focus (tapping
    // elsewhere, keyboard closed).
    _inputFocus.addListener(() {
      if (!_inputFocus.hasFocus && _showMentionSuggestions) {
        _closeMentionSuggestions();
      }
    });
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
      _groupSub = state?.onGroupUpdated.listen(_onGroupUpdated);
      _bannedSub?.cancel();
      _bannedSub = state?.onGroupBanned.listen(_onGroupBanned);
      _groupDeletedSub?.cancel();
      _groupDeletedSub = state?.onGroupDeleted.listen(_onGroupDeleted);
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
    // Keyboard show/hide (and app-lifecycle changes) re-pin the follow-bottom
    // so the composer never covers the latest bubble — same as the DM chat..
    WidgetsBinding.instance.addObserver(this);
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
    _bannedSub?.cancel();
    _groupDeletedSub?.cancel();
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
    WidgetsBinding.instance.removeObserver(this);
    _recorder.dispose();
    _input.dispose();
    _inputFocus.dispose();
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

  /// Keyboard show/hide (or window/metrics change) — re-pin to the
  /// bottom ONLY when the user was already following the newest message, so
  /// the composer never covers the latest bubble,while mid-thread positions
  /// are preserved (no forced jump). Mirrors the DM conversation behavior..
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted || !_scroll.hasClients || !_followBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _followBottom) _jumpToBottom();
    });
  }

  /// Refreshes the header from the current AppState cache if available —the
  /// cache is fed by the group list and by real-time `group_updated` frames,, so
  /// the AppBar always reflects the persisted group identity (never a stale
  /// snapshot from the route argument)). Falls back to the route payload..
  void _applyFreshHeader() {
    final groups = _state?.groups ?? const <GroupConversation>[];
    GroupConversation? group;
    for (final g in groups) {
      if (g.id == _groupId) {
        group = g;
        break;
      }
    }
    if (group == null) return;
    _groupName = group.group.name;
    _groupAvatarUrl = group.group.avatarUrl;
    _groupDescription = group.group.description;
    _groupOwnerId = group.group.createdById;
    _groupMemberCount = group.group.memberCount;
  }

  /// An owner edited the group (name/avatar/description/membership). The
  /// server pushed a fresh header; update the AppBar and cached fields live.
  /// The frame also carries the CURRENT banned ids — sync the loaded messages
  /// so "banido(a)" tags appear/disappear on the affected senders instantly
  /// (no reload, no app restart).
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
      _syncBannedSenders(event.bannedUserIds);
    });
  }

  /// Syncs every loaded group message's sender to the CURRENT banned set
  /// (both set and clear). Called inside [setState] by realtime frames — the
  /// server is authoritative and provides the full list, so this must only
  /// mutate [\_messages] in place, never rebuild the list.
  void _syncBannedSenders(Set<String> bannedIds) {
    for (var i = 0; i < _messages.length; i++) {
      final sender = _messages[i].sender;
      if (sender == null) continue;
      final banned = bannedIds.contains(sender.id);
      if (sender.banned != banned) {
        _messages[i] =
            _messages[i].copyWith(sender: sender.copyWith(banned: banned));
      }
    }
  }

  /// Marks every loaded message from [senderId] as banned (without clearing
  /// others) — used after the OWNER bans a user on this screen, where the
  /// acting user does NOT receive their own realtime broadcast.
  void _markSenderBanned(String senderId) {
    for (var i = 0; i < _messages.length; i++) {
      final sender = _messages[i].sender;
      if (sender == null || sender.id != senderId || sender.banned) continue;
      _messages[i] =
          _messages[i].copyWith(sender: sender.copyWith(banned: true));
    }
  }

  /// The session user was BANNED from this group (realtime). The server
  /// already revoked membership; close the screen so nothing stays stale.
  void _onGroupBanned(GroupBannedEvent event) {
    if (!mounted) return;
    if (event.groupId != _groupId) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          event.groupName.isEmpty
              ? 'Você foi banido deste grupo.'
              : 'Você foi banido de "${event.groupName}".',
        ),
      ),
    );
    Navigator.of(context).maybePop();
  }

  /// The session user LOST ACCESS to this group (realtime) — the owner
  /// permanently deleted it or the user left. Drop the screen so nothing
  /// stays stale (the server revoked membership already).
  void _onGroupDeleted(GroupDeletedEvent event) {
    if (!mounted) return;
    if (event.groupId != _groupId) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          event.groupName.isEmpty
              ? 'Você não faz mais parte deste grupo.'
              : '"${event.groupName}" já não está disponível.',
        ),
      ),
    );
    Navigator.of(context).maybePop();
  }

  /// Tapping a reply quote scrolls to the ORIGINAL message when it is
  /// currently loaded in this conversation (no-op otherwise — never triggers
  /// a full-list fetch).
  void _openReplyTarget(String messageId) {
    if (!mounted || !_scroll.hasClients) return;
    for (var i = 0; i < _messages.length; i++) {
      if (_messages[i].id == messageId) {
        _followBottom = false; // explicitly navigating away from the bottom
        final extent = _scroll.position.maxScrollExtent;
        final ratio = _messages.isEmpty ? 0.0 : i / (_messages.length - 1);
        _scroll.jumpTo((extent * ratio).clamp(0.0, extent));
        return;
      }
    }
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
    // Pin the newest message AFTER the frame that lays out the new bubble —
    // jumping synchronously inside setState reads a stale maxScrollExtent
    // (the list hasn't sized the new child yet), leaving the latest bubble
    // under the composer when the keyboard is open. This single post-frame
    // pin handles send, incoming realtime and keyboard resizes in the same
    // frame (mirrors the DM conversation behavior).
    if (_followBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpToBottom();
      });
    }
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
    final id = event.userId;
    final idKey = (id == null || id.isEmpty) ? event.chatId : id;
    if (event.typing) {
      if (idKey.isNotEmpty) {
        _typingUsers.add(idKey);
        if (idKey == id &&
            event.nickname != null &&
            event.nickname!.isNotEmpty) {
          _typingNames[idKey] = event.nickname!;
        }
      }
      _typingAutoClear?.cancel();
      _typingAutoClear = Timer(_typingTimeout, () {
        if (mounted) {
          setState(() {
            _typingUsers.clear();
            _typingNames.clear();
          });
        }
      });
    } else {
      _typingUsers.remove(idKey);
      if (id != null) _typingNames.remove(idKey);
      _typingAutoClear?.cancel();
    }
    setState(() {});
  }

  void _onRecording(ChatRecordingEvent event) {
    if (!mounted) return;
    if (event.groupId != _groupId) return;
    final id = event.userId;
    final idKey = (id == null || id.isEmpty) ? event.chatId : id;
    if (event.recording) {
      if (idKey.isNotEmpty) {
        _recordingUsers.add(idKey);
        if (idKey == id &&
            event.nickname != null &&
            event.nickname!.isNotEmpty) {
          _recordingNames[idKey] = event.nickname!;
        }
      }
      _recordingAutoClear?.cancel();
      _recordingAutoClear = Timer(_typingTimeout, () {
        if (mounted) {
          setState(() {
            _recordingUsers.clear();
            _recordingNames.clear();
          });
        }
      });
    } else {
      _recordingUsers.remove(idKey);
      if (id != null) _recordingNames.remove(idKey);
      _recordingAutoClear?.cancel();
    }
    setState(() {});
  }

  void _onRead(ChatReadEvent event) {
    // Group read receipts are coarse — no per-message flip here:the server
    // persists reads; individual readAt comes embedded when available.
  }

  void _scrollListener() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    // Paginate older messages near the top.
    if (position.pixels <= 120.0 && _hasMore && !_loadingOlder) {
      unawaited(_loadOlderMessages());
    }
    // Smart auto-scroll: follow the bottom ONLY when the user is actually AT
    // (or within a tiny threshold of) the newest message. Scrolling up to
    // read history turns _followBottom OFF immediately, so inbound messages
    // are appended without yanking the reader back down.
    final nearBottom = position.maxScrollExtent - position.pixels < 140.0;
    if (nearBottom && !_followBottom) {
      setState(() => _followBottom = true);
    } else if (!nearBottom && _followBottom) {
      setState(() => _followBottom = false);
    }
  }

  void _jumpToBottom() {
    if (!mounted || !_scroll.hasClients) return;
    final pos = _scroll.position.maxScrollExtent;
    _scroll.jumpTo(pos);
    _followBottom = true;
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final reply = _replyTarget;
    // Snapshot the draft mentions (real user ids) and clear them so the next
    // draft starts fresh.
    final mentionIds = _draftMentionIds.toList();
    final mentionAll = text.contains('@todos');
    setState(() {
      _sending = true;
      _draftMentionIds.clear();
    });
    try {
      final message = await _state!.sendGroupChatMessage(
        _groupId,
        text,
        replyToMessageId: reply?.id,
        mentionUserIds: mentionIds,
        mentionAll: mentionAll,
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
      // Re-add the draft mentions on failure so the user can retry.
      setState(() => _draftMentionIds.addAll(mentionIds));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível enviar a mensagem.')),
      );
      setState(() => _draftMentionIds.addAll(mentionIds));
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
    // An outgoing voice reply reuses the same reply reference as texts:the
    // quote is captured BEFORE clearing so the audio bubble keeps its link.

    final voiceReply = _replyTarget;
    if (voiceReply != null) {
      setState(() {
        _replyTarget = null;
      });
    }
    try {
      final message = await _state!.sendGroupVoiceMessage(
        _groupId,
        file,
        durationMs: durationMs,
        replyToMessageId: voiceReply?.id,
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
    final isOwner = _groupOwnerId != null &&
        _groupOwnerId!.isNotEmpty &&
        _state?.currentUser?.id == _groupOwnerId;
    final canDeleteAnyone = message.mine || isOwner;
    final canBan = isOwner && !message.mine;
    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      isScrollControlled: true,
      builder: (_) => _MessageActionSheet(
        message: message,
        canDeleteAnyone: canDeleteAnyone,
        canBan: canBan,
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _MessageAction.reply:
        _startReply(_messages.indexOf(message));
      case _MessageAction.seenInfo:
        await _openSeenInfo(message);
      case _MessageAction.deleteForMe:
        await _confirmDeleteForMe(message);
      case _MessageAction.deleteForEveryone:
        await _confirmDeleteForEveryone(message);
      case _MessageAction.banUser:
        await _confirmBanUser(message);
    }
  }

  /// Visto/Enviado — opens the bottom panel listing WHO read this own
  /// message ([VISTO]) and who has not ([ENVIADO]). The chat stays visible
  /// behind; tapping outside closes it.
  Future<void> _openSeenInfo(ChatMessage message) async {
    if (!message.mine || message.groupId == null) return;
    final state = _state;
    if (state == null) return;
    final messenger = ScaffoldMessenger.of(context);
    var ok = true;
    var readers = <ChatUser>[];
    var unread = <ChatUser>[];
    try {
      final result = await state.groupMessageReaders(_groupId, message.id);
      readers = result.read;
      unread = result.unread;
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Não foi possível carregar as leituras.')),
      );
      return;
    }
    // Live updates: a `chat_read` frame for THIS message moves the reader
    // from ENVIADO → VISTO while the sheet is open.
    final stateNotifier =
        ValueNotifier<({List<ChatUser> read, List<ChatUser> unread})>(
      (read: readers, unread: unread),
    );
    final readSub = state.onChatRead.listen((event) {
      if (!mounted) return;
      if (event.groupId != _groupId) return;
      if (!event.messageIds.contains(message.id)) return;
      final readerId = event.userId;
      if (readerId == null) return;
      final current = stateNotifier.value;
      final remainingUnread =
          current.unread.where((u) => u.id != readerId).toList();
      var updatedRead = current.read;
      if (!updatedRead.any((r) => r.id == readerId)) {
        updatedRead = [
          ...updatedRead,
          ChatUser(
            id: readerId,
            nickname: _state?.currentUser?.id == readerId
                ? _state?.currentUser?.nickname ?? ''
                : '...',
            avatarUrl: _state?.currentUser?.id == readerId
                ? _state?.currentUser?.avatarUrl
                : null,
          ),
        ];
      }
      stateNotifier.value = (read: updatedRead, unread: remainingUnread);
    });
    try {
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.5),
        isScrollControlled: true,
        builder: (_) => ValueListenableBuilder<
            ({List<ChatUser> read, List<ChatUser> unread})>(
          valueListenable: stateNotifier,
          builder: (context, snapshot, _) => _SeenInfoSheet(
            read: snapshot.read,
            unread: snapshot.unread,
            message: message,
            onRefresh: () async {
              try {
                final result =
                    await state.groupMessageReaders(_groupId, message.id);
                if (!mounted) return;
                stateNotifier.value =
                    (read: result.read, unread: result.unread);
              } catch (_) {
                // keep current state
              }
            },
          ),
        ),
      );
    } finally {
      await readSub.cancel();
      stateNotifier.dispose();
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

  /// Owner-only action: ban the sender of [message] from the group. Shows a
  /// confirmation before calling the server; the server re-validates the
  /// owner permission and rejects banning the OWNER (forge-proof).
  Future<void> _confirmBanUser(ChatMessage message) async {
    if (!mounted) return;
    final sender = message.sender;
    final nickname = sender?.nickname ?? 'este usuário';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bluishBlack,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          side: BorderSide(color: AppColors.deepBlue),
        ),
        title: Text(
          'Banir usuário?',
          style: AppTextStyles.hud
              .copyWith(fontSize: 16, color: AppColors.techWhite),
        ),
        content: Text(
          'Banir $nickname do grupo? Ele não poderá mais acessar nem enviar mensagens.',
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
            child: Text('Banir', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await _state?.banGroupMember(_groupId, message.senderId);
    if (!mounted) return;
    if (ok == true) {
      // The owner's screen does NOT receive their own realtime fan-out —
      // tag the banned user's messages locally so "banido(a)" appears
      // immediately on this device too.
      setState(() => _markSenderBanned(message.senderId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$nickname foi banido do grupo.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível banir o usuário.')),
      );
    }
  }

  void _onComposerChanged(String value) {
    final typing = value.trim().isNotEmpty;
    if (typing != _typingLastSent) {
      _typingLastSent = typing;
      _typingSendDebounce?.cancel();
      _typingSendDebounce = Timer(const Duration(milliseconds: 400), () {
        _state?.sendGroupTyping(_groupId, typing);
      });
    }
    _updateMentionState(value);
  }

  /// Detects a TRAILING "@query" token in [value] (the cursor is at the end
  /// while composing) and drives the inline suggestion bar state. The bar is
  /// visible only while there is a valid mention intention at the caret:
  ///   "Oi @le   " → query "le", bar visible
  ///   "Oi @leonardo " → no trailing token, bar hidden
  ///   "Oi " → no token, bar hidden
  bool _currentMentionToken(String value, {bool atCaret = true}) {
    if (!atCaret) return false;
    final at = value.lastIndexOf('@');
    if (at == -1) return false;
    // The @ must be at a word boundary (start or after whitespace).
    if (at > 0 && !RegExp(r'\s').hasMatch(value[at - 1])) return false;
    // After the '@' there must be only nickname chars (no spaces yet).
    final tail = value.substring(at + 1);
    if (tail.contains(' ')) return false;
    return true;
  }

  String _mentionTokenQuery(String value) {
    final at = value.lastIndexOf('@');
    return at == -1 ? '' : value.substring(at + 1);
  }

  void _updateMentionState(String value) {
    final hasToken = _currentMentionToken(value);
    final query = hasToken ? _mentionTokenQuery(value) : '';
    if (!hasToken) {
      if (_showMentionSuggestions || _mentionQuery.isNotEmpty) {
        setState(() {
          _showMentionSuggestions = false;
          _mentionQuery = '';
        });
      }
      return;
    }
    setState(() {
      _mentionQuery = query;
      _showMentionSuggestions = true;
    });
    // Lazy-load the group members the first time a mention token appears.
    if (!_mentionMembersLoaded) {
      _loadMentionMembers();
    }
  }

  Future<void> _loadMentionMembers() async {
    final state = _state;
    if (state == null) return;
    try {
      final info = await state.fetchGroupInfo(_groupId);
      if (!mounted) return;
      setState(() {
        _mentionMembers = info.members;
        _mentionMembersLoaded = true;
      });
    } catch (_) {
      // best-effort — a second "@" retries
    }
  }

  /// Called when the composer loses focus or the keyboard closes — hide the
  /// inline suggestion bar so nothing stays stuck.
  void _closeMentionSuggestions() {
    if (!_showMentionSuggestions && _mentionQuery.isEmpty) return;
    setState(() {
      _showMentionSuggestions = false;
      _mentionQuery = '';
    });
  }

  void _insertMention(_MentionPick pick) {
    final controller = _input;
    final text = controller.text;
    final at = text.lastIndexOf('@');
    // Replace the exact "@token" (everything from @ to the next whitespace
    // or end of text); keep any text typed AFTER the token (WhatsApp inserts
    // at the caret, preserving the rest).
    var tokenEnd = text.length;
    if (at != -1) {
      final afterAt = text.substring(at + 1);
      var idx = 0;
      while (idx < afterAt.length && !RegExp(r'\s').hasMatch(afterAt[idx])) {
        idx++;
      }
      tokenEnd = at + 1 + idx;
    }
    final before = at == -1 ? text : text.substring(0, at);
    final after = at == -1 ? '' : text.substring(tokenEnd);
    final inserted = '${pick.all ? '@todos' : '@${pick.nickname}'} ';
    controller
      ..text = '$before$inserted$after'
      ..selection = TextSelection.collapsed(offset: controller.text.length);
    setState(() {
      _showMentionSuggestions = false;
      _mentionQuery = '';
      if (pick.all) {
        _draftMentionIds.clear();
      } else {
        _draftMentionIds.add(pick.userId);
      }
    });
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
    final avatar =
        _groupAvatarUrl ?? _args?.groupAvatarUrl ?? widget.args.groupAvatarUrl;
    final title = GestureDetector(
      onTap: _openGroupProfile,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GroupAvatar(size: 40, url: avatar, name: name),
          const SizedBox(width: AppDimensions.spaceMd),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.hud.copyWith(
                    fontSize: 17,
                    color: AppColors.techWhite,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_groupMemberCount > 0)
                  Text(
                    '$_groupMemberCount membro${_groupMemberCount == 1 ? '' : 's'}',
                    style: AppTextStyles.caption.copyWith(
                        fontSize: 11, color: AppColors.holographicBlue),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      // Default IME handling — the Scaffold resizes with the Android keyboard so
      // the composer sits directly above it (same proven behavior as the DM chat;
      // no fixed-pixel hacks for the nav bar or insets).
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppColors.absoluteBlack,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        centerTitle: true,
        leading: BackButton(
          color: AppColors.holographicBlue,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppDimensions.spaceSm),
            child: _buildActivityIndicator(maxWidth: 140),
          ),
        ],
        title: title,
      ),
      body: SafeArea(
        top: false,
        child: _buildBody(),
      ),
    );
  }

  /// Builds the realtime activity indicator for the header (right area):who
  /// is typing / recording audio, with plural/count handling, truncated to
  /// fit — never overflows whatever the name/count.
  Widget _buildActivityIndicator({double maxWidth = 160}) {
    final typingNames = _typingUsers
        .map((u) => displayNickname(_typingNames[u] ?? 'Alguém'))
        .toList();
    final recordingNames = _recordingUsers
        .map((u) => displayNickname(_recordingNames[u] ?? 'Alguém'))
        .toList();
    String? label;
    if (typingNames.isNotEmpty && recordingNames.isEmpty) {
      if (typingNames.length == 1) {
        label = '${typingNames.first} está digitando';
      } else {
        label = '${typingNames.length} usuários estão digitando';
      }
    }
    if (recordingNames.isNotEmpty && typingNames.isEmpty) {
      if (recordingNames.length == 1) {
        label = '${recordingNames.first} está gravando áudio';
      } else {
        label = '${recordingNames.length} usuários estão gravando áudio';
      }
    }
    if (typingNames.isNotEmpty && recordingNames.isNotEmpty) {
      if (typingNames.length == 1 && recordingNames.length == 1) {
        label =
            '${typingNames.first} digita e ${recordingNames.first} grava áudio';
      } else {
        label =
            '${typingNames.length} digitando • ${recordingNames.length} gravando áudio';
      }
    }
    final visible = label != null;
    return AnimatedSize(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      child: visible
          ? ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: AppTextStyles.caption.copyWith(
                  fontSize: 12,
                  color: AppColors.holographicBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : const SizedBox(width: 0, height: 0),
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
        initialAvatarUrl: _groupAvatarUrl ??
            _args?.groupAvatarUrl ??
            widget.args.groupAvatarUrl,
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
        // Reply-to preview above the composer when a message is selected —
        // mirrors the DM chat so the user always sees what they're replying
        // to and can cancel with the ✕.
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
              ? _GroupReplyPreviewBar(
                  key: ValueKey(_replyTarget!.id),
                  target: _replyTarget!,
                  onCancel: _cancelReply,
                )
              : const SizedBox.shrink(),
        ),
        // WhatsApp-style mention suggestions: an INLINE bar anchored directly
        // above the composer (driven by the typing state, never a modal).
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          transitionBuilder: (child, anim) => SizeTransition(
            sizeFactor: anim,
            axisAlignment: -1,
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: _showMentionSuggestions
              ? _MentionSuggestionsBar(
                  key: const ValueKey('mention-bar'),
                  query: _mentionQuery,
                  members: _mentionMembers,
                  showAll: _isGroupOwner,
                  selfId: _state?.currentUser?.id,
                  onPick: _insertMention,
                  onClose: _closeMentionSuggestions,
                )
              : const SizedBox.shrink(),
        ),
        _composer(),
      ],
    );
  }

  void _cancelReply() {
    setState(() => _replyTarget = null);
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
        onStartReply: () => _startReply(i),
        replySelected: _replyTarget?.id == m.id,
        replyingTo: (_replyTarget?.id == m.id) ? _replyTarget : null,
        onOpenReplyTarget: _openReplyTarget,
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
              focusNode: _inputFocus,
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
    return UserAvatar(
      name: name ?? 'G',
      seed: name,
      imageUrl: (url == null || url!.isEmpty) ? null : url,
      size: size,
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
    this.onOpenReplyTarget,
    this.onStartReply,
    this.replySelected = false,
  });

  final ChatMessage message;
  final bool mine;
  final VoidCallback? onLongPress;
  final ChatMessage? replyingTo;

  /// Tapping a reply quote scrolls to the ORIGINAL message (when loaded).
  final void Function(String messageId)? onOpenReplyTarget;

  /// Called when a horizontal swipe (left→right on received / right→left on
  /// mine) crosses the reply threshold — activates the reply composer.
  final VoidCallback? onStartReply;

  /// True while this message is the currently-selected reply target (the
  /// bubble stays pinned at the swipe offset until canceled).
  final bool replySelected;

  /// Opens the REAL sender's profile (id/nickname come from the embedded
  /// sender identity — never the session user, never client-inferred state).
  void _openSenderProfile(BuildContext context, ChatUser sender) {
    if (sender.id.isEmpty || sender.nickname.isEmpty) return;
    openProfileById(context, id: sender.id, nickname: sender.nickname);
  }

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
            GestureDetector(
              onTap: () => _openSenderProfile(context, sender),
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      displayNickname(sender.nickname),
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 11,
                        color: AppColors.holographicBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Group-scoped ban state: the sender is CURRENTLY banned
                  // from THIS group (server-embedded per group; a private DM
                  // peer never gets the tag). Keeps the message history
                  // intact while labeling the author.
                  if (sender.banned) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        'banido(a)',
                        style: AppTextStyles.caption.copyWith(
                          fontSize: 9,
                          color: AppColors.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 2),
          ],
          if (replyingTo != null) _ReplyQuote(reply: replyingTo!),
          // The server-resolved original this message answers (received
          // replies carry it on the wire). Tapping it locates the original
          // message when it's loaded locally.
          if (message.replyTo != null)
            GestureDetector(
              onTap: onOpenReplyTarget == null
                  ? null
                  : () => onOpenReplyTarget!(message.replyTo!.id),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.absoluteBlack.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    left:
                        BorderSide(color: AppColors.holographicBlue, width: 3),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 10,
                        color: AppColors.holographicBlue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      message.replyTo!.exists &&
                              message.replyTo!.content.isNotEmpty
                          ? message.replyTo!.content
                          : '🎤 Áudio',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.techWhite),
                    ),
                  ],
                ),
              ),
            ),
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
              child: GestureDetector(
                onTap: sender == null
                    ? null
                    : () => _openSenderProfile(context, sender),
                behavior: HitTestBehavior.opaque,
                child: UserAvatar(
                  name: sender?.nickname ?? '?',
                  seed: sender?.nickname,
                  imageUrl: sender?.avatarUrl,
                  size: 36,
                ),
              ),
            ),
          ],
          Flexible(
            child: ReplySwipe(
              mine: mine,
              bubble: bubble,
              onStartReply: onStartReply ?? () {},
              onLongPress: onLongPress ?? () {},
              replySelected: replySelected,
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
    final selfId = AppStateScope.maybeOf(context)?.currentUser?.id;
    final spans = <TextSpan>[];
    final mentionAll = message.mentionAll;
    final mentionById = <String, String>{
      for (final m in message.mentions) m.userId: m.nickname,
    };
    final reg = RegExp(r'@(\w+)');
    var last = 0;
    for (final match in reg.allMatches(message.content)) {
      if (match.start > last) {
        spans.add(TextSpan(
            text: message.content.substring(last, match.start),
            style: AppTextStyles.body.copyWith(color: AppColors.techWhite)));
      }
      final token = match.group(0)!;
      final nickname = match.group(1)!;
      final isMention = mentionAll ||
          mentionById.values
              .any((n) => n.toLowerCase() == nickname.toLowerCase());
      final isSelf = mentionAll ||
          (selfId != null &&
              mentionById[selfId]?.toLowerCase() == nickname.toLowerCase());
      spans.add(TextSpan(
        text: token,
        style: AppTextStyles.body.copyWith(
          // The MENTIONED user sees @me highlighted (WhatsApp-style); other
          // mentions stay subtle. @todos lights up for everyone.
          color: isSelf ? AppColors.electricBlue : AppColors.holographicBlue,
          fontWeight: isMention ? FontWeight.w800 : FontWeight.w600,
          backgroundColor: isSelf
              ? AppColors.electricBlue.withValues(alpha: 0.22)
              : Colors.transparent,
        ),
      ));
      last = match.end;
    }
    if (last < message.content.length) {
      spans.add(TextSpan(
          text: message.content.substring(last),
          style: AppTextStyles.body.copyWith(color: AppColors.techWhite)));
    }
    return Text.rich(TextSpan(children: spans),
        style: AppTextStyles.body.copyWith(color: AppColors.techWhite));
  }
}

/// The "Respondendo a …" bar shown above the group composer while a reply is
/// selected:the original message's author + truncated preview + a ✕ close.
/// Mirrors the DM chat's reply-bar so the group flow feels identical.
class _GroupReplyPreviewBar extends StatelessWidget {
  const _GroupReplyPreviewBar({
    super.key,
    required this.target,
    required this.onCancel,
  });

  final ChatMessage target;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final sender = target.sender;
    final author = sender != null && sender.nickname.isNotEmpty
        ? sender.nickname
        : 'mensagem';
    final preview = target.content.isNotEmpty ? target.content : '🎤 Áudio';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.navBarBackground,
        border: Border(
          top: BorderSide(color: AppColors.holographicBlue, width: 1),
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
          Icon(Icons.reply_rounded, color: AppColors.holographicBlue),
          SizedBox(width: AppDimensions.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Respondendo a $author',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.holographicBlue,
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
                    color: AppColors.techWhite,
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

enum _MessageAction {
  reply,
  deleteForMe,
  deleteForEveryone,
  banUser,
  seenInfo,
}

class _MessageActionSheet extends StatelessWidget {
  const _MessageActionSheet({
    required this.message,
    this.canDeleteAnyone = false,
    this.canBan = false,
  });

  final ChatMessage message;

  /// Whether the session user may delete this message for everyone — the
  /// sender of the message OR the group owner (server-validated). The
  /// menu hides the action otherwise (cosmetic only).
  final bool canDeleteAnyone;

  /// Whether the session user (group owner) may BAN the sender of this
  /// message. Only shown for OTHER participants' messages (never own, never
  /// the owner). Server re-validates.
  final bool canBan;

  @override
  Widget build(BuildContext context) {
    // Keep the whole sheet inside the SAFE area of the screen: the Android
    // navigation bar is accounted for by [SafeArea] (bottom padding from
    // MediaQuery), an OPEN keyboard by [viewInsets.bottom], and the content
    // is capped to the remaining height and made scrollable so every action
    // ("Banir usuário" included) is always fully visible and tappable —
    // never behind the nav bar, never clipped, on any device/rotation. No
    // fixed offsets. `useSafeArea` on the route stays OFF; this explicit
    // SafeArea is the single source of truth.
    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;
    final bottomSafe = media.padding.bottom;
    final availableHeight = media.size.height - keyboardInset - bottomSafe;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (availableHeight - 16).clamp(0.0, availableHeight),
          ),
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.bluishBlack,
              borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
            ),
            // The Container's box decoration creates a DecoratedBox — ListTile
            // paints its ink splash on the nearest Material ancestor, so a
            // transparent Material is required here (same pattern as the DM
            // menu) or newer Flutter versions assert "ListTile background
            // color or ink splashes may be invisible".
            child: Material(
              color: Colors.transparent,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionItem(
                        icon: Icons.reply_rounded,
                        label: 'Responder',
                        onTap: () =>
                            Navigator.of(context).pop(_MessageAction.reply)),
                    if (message.mine)
                      _ActionItem(
                          icon: Icons.done_all_rounded,
                          label: 'Visto/Enviado',
                          onTap: () => Navigator.of(context)
                              .pop(_MessageAction.seenInfo)),
                    _ActionItem(
                        icon: Icons.delete_outline_rounded,
                        label: 'Excluir para mim',
                        onTap: () => Navigator.of(context)
                            .pop(_MessageAction.deleteForMe)),
                    if (canDeleteAnyone)
                      _ActionItem(
                          icon: Icons.delete_forever_rounded,
                          label: 'Excluir para todos',
                          onTap: () => Navigator.of(context)
                              .pop(_MessageAction.deleteForEveryone)),
                    if (canBan)
                      _ActionItem(
                          icon: Icons.block_rounded,
                          label: 'Banir usuário',
                          onTap: () => Navigator.of(context)
                              .pop(_MessageAction.banUser)),
                  ],
                ),
              ),
            ),
          ),
        ),
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

/// Result of choosing a member (or @todos) in the mention sheet.
class _MentionPick {
  const _MentionPick({
    this.userId = '',
    this.nickname = '',
    this.all = false,
  });

  final String userId;
  final String nickname;
  final bool all;
}

/// WhatsApp-style INLINE mention suggestion bar. Rendered directly above the
/// composer inside the chat Column (NOT a modal): it sits under the keyboard,
/// filters as the user types, and disappears when the mention intention ends.
/// Lists the group's members (nickname WITHOUT the @ prefix, per MATRIX) and
/// `@todos` for the owner.
class _MentionSuggestionsBar extends StatelessWidget {
  const _MentionSuggestionsBar({
    super.key,
    required this.query,
    required this.members,
    required this.showAll,
    required this.selfId,
    required this.onPick,
    required this.onClose,
  });

  final String query;
  final List<GroupMemberInfoModel> members;
  final bool showAll;
  final String? selfId;
  final void Function(_MentionPick pick) onPick;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final filtered = members
        .where((m) =>
            m.id != selfId &&
            (query.isEmpty ||
                m.nickname.toLowerCase().contains(query.toLowerCase())))
        .toList();
    final hasResults = showAll || filtered.isNotEmpty;
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      margin: const EdgeInsets.fromLTRB(AppDimensions.spaceMd, 0,
          AppDimensions.spaceMd, AppDimensions.spaceXs),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(color: AppColors.deepBlue),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Text('MENCIONAR',
                      style: AppTextStyles.hud.copyWith(
                          fontSize: 10, color: AppColors.holographicBlue)),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded,
                        size: 16, color: AppColors.holographicBlue),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showAll)
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.groups_rounded,
                            color: AppColors.holographicBlue),
                        title: Text('@todos',
                            style: AppTextStyles.body
                                .copyWith(color: AppColors.techWhite)),
                        subtitle: Text('mencionar todos os participantes',
                            style: AppTextStyles.caption.copyWith(
                                fontSize: 10,
                                color: AppColors.holographicBlue)),
                        onTap: () => onPick(const _MentionPick(
                            userId: '', nickname: '', all: true)),
                      ),
                    for (final m in filtered)
                      ListTile(
                        dense: true,
                        leading: UserAvatar(
                            name: m.nickname,
                            seed: m.nickname,
                            imageUrl: m.avatarUrl,
                            size: 32),
                        title: Text(displayNickname(m.nickname),
                            style: AppTextStyles.body
                                .copyWith(color: AppColors.techWhite)),
                        onTap: () => onPick(
                            _MentionPick(userId: m.id, nickname: m.nickname)),
                      ),
                    if (!hasResults)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('Nenhum membro encontrado',
                            style: AppTextStyles.bodyMuted),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Visto/Enviado bottom panel: lists who already read (VISTO) and who has
/// NOT yet (ENVIADO) — the chat stays visible behind; tapping outside closes.
class _SeenInfoSheet extends StatefulWidget {
  const _SeenInfoSheet({
    required this.read,
    required this.unread,
    required this.message,
    required this.onRefresh,
  });

  final List<ChatUser> read;
  final List<ChatUser> unread;
  final ChatMessage message;
  final Future<void> Function() onRefresh;

  @override
  State<_SeenInfoSheet> createState() => _SeenInfoSheetState();
}

class _SeenInfoSheetState extends State<_SeenInfoSheet> {
  bool _refreshing = false;

  @override
  void didUpdateWidget(covariant _SeenInfoSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent refreshes the lists live (inbound chat_read frames) — the
    // sheet just re-renders the new snapshots.
    if (oldWidget.read != widget.read || oldWidget.unread != widget.unread) {
      // no local state — we read straight from widget
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bluishBlack,
          borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
          border: Border.all(color: AppColors.deepBlue),
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text('VISTO/ENVIADO',
                        style: AppTextStyles.hud.copyWith(
                            fontSize: 12, color: AppColors.techWhite)),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.refresh_rounded,
                          size: 18, color: AppColors.holographicBlue),
                      onPressed: _refreshing
                          ? null
                          : () async {
                              setState(() => _refreshing = true);
                              await widget.onRefresh();
                              if (mounted) setState(() => _refreshing = false);
                            },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              _readerSection('VISTO', widget.read, AppColors.success),
              _readerSection(
                  'ENVIADO', widget.unread, AppColors.holographicBlue),
            ],
          ),
        ),
      ),
    );
  }

  Widget _readerSection(String label, List<ChatUser> users, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.done_all_rounded, size: 16, color: color),
              const SizedBox(width: 6),
              Text('$label (${users.length})',
                  style: AppTextStyles.caption.copyWith(
                      fontSize: 11, color: color, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          if (users.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('Nenhum',
                  style: AppTextStyles.caption.copyWith(
                      fontSize: 11, color: AppColors.holographicBlue)),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final u in users)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserAvatar(
                          name: u.nickname,
                          seed: u.nickname,
                          imageUrl: u.avatarUrl,
                          size: 26),
                      const SizedBox(width: 4),
                      Text(displayNickname(u.nickname),
                          style: AppTextStyles.caption.copyWith(
                              fontSize: 11, color: AppColors.techWhite)),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
