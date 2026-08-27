import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/framed_avatar.dart';
import '../../core/widgets/glow_container.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_card.dart';
import '../../core/widgets/matrix_text_field.dart';
import '../../core/widgets/nickname_renderer.dart';
import '../../core/widgets/user_avatar.dart';
import '../../models/conversation.dart';
import '../../models/matrix_user.dart';
import '../../core/utils/chat_format.dart';
import 'chat_navigation.dart';

/// The "💬 Chat" tab — private conversations.
///
/// Layout: user search bar → AKAME (fixed permanent first entry) + 👥 AMIGOS
/// (horizontal row) → 💬 CONVERSAS (one card per conversation with photo,
/// nickname, last message + time). Akame is a special, fixed entry that
/// always leads the friends row — it is never treated as a friend. Tapping
/// it opens the full Akame chat through [onOpenAkame]; all data comes from
/// existing systems (users/friends/conversations); tapping any other entry
/// opens the SAME [ConversationScreen].
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.onOpenAkame});

  /// Invoked when the user taps the fixed Akame card — the caller (Home
  /// shell) raises the standalone Akame overlay. Null renders the card
  /// without an action (e.g. standalone tests).
  final VoidCallback? onOpenAkame;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _search = TextEditingController();
  List<MatrixUser> _searchResults = const [];
  List<MatrixUser> _friends = const [];
  bool _searching = false;
  bool _searched = false;
  StreamSubscription<ChatMessage>? _chatSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_primed) return;
    _primed = true;
    // Defer the first refresh: loadConversations notifies listeners
    // synchronously, which is not allowed during the build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = AppStateScope.maybeOf(context);
      if (state == null) return;
      _chatSub = state.onChatIncoming.listen((_) => _onRealtime());
      // Re-sync the friends row when a friendship changes elsewhere (e.g. a
      // friend removed from their profile) so the list never shows stale rows.
      _friendsChangedSub = state.onFriendsChanged.listen((_) {
        if (mounted) _loadFriends(state);
      });
      _refresh();
    });
  }

  bool _primed = false;
  StreamSubscription<void>? _friendsChangedSub;

  @override
  void dispose() {
    _chatSub?.cancel();
    _friendsChangedSub?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final state = AppStateScope.maybeOf(context);
    if (state == null) return;
    await Future.wait([_loadConversations(state), _loadFriends(state)]);
  }

  Future<void> _loadConversations(AppState state) async {
    await state.loadConversations();
    await state.refreshUnreadConversations();
  }

  Future<void> _loadFriends(AppState state) async {
    final current = state.currentUser;
    if (current == null) return;
    try {
      final page = await state.loadFriends(current.id, pageSize: 30);
      if (!mounted) return;
      setState(() => _friends = page.friends);
    } catch (_) {
      // Friends list best-effort; conversations still render.
    }
  }

  void _onRealtime() {
    // A realtime chat message arrived → refresh list + unread badge.
    final state = AppStateScope.maybeOf(context);
    if (state == null) return;
    _loadConversations(state);
  }

  Future<void> _searchUsers(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = const [];
        _searched = false;
        _searching = false;
      });
      return;
    }
    final state = AppStateScope.maybeOf(context);
    if (state == null) return;
    setState(() => _searching = true);
    try {
      final users = await state.searchUsers(trimmed);
      if (!mounted) return;
      setState(() {
        _searchResults = users;
        _searched = true;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searchResults = const [];
        _searched = true;
        _searching = false;
      });
    }
  }

  void _openSearchResult(MatrixUser user) {
    if (user.id == _me?.id) return; // never DM yourself
    openChatWithUser(context, user);
  }

  MatrixUser? get _me => AppStateScope.of(context).currentUser;

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final conversations = state.conversations;

    final hasQuery = _search.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: AppColors.absoluteBlack,
            surfaceTintColor: Colors.transparent,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('CHAT', style: AppTextStyles.title.copyWith(fontSize: 18)),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.spaceLg,
                AppDimensions.spaceSm,
                AppDimensions.spaceLg,
                AppDimensions.spaceLg,
              ),
              child: MatrixTextField(
                hint: 'Pesquisar usuários',
                controller: _search,
                prefix: Icon(Icons.search_rounded,
                    color: AppColors.holographicBlue, size: 20),
                onChanged: _searchUsers,
              ),
            ),
          ),
          // ── Search results (only while a query is typed) ──
          if (hasQuery) ...[
            if (_searching)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(AppDimensions.spaceXl),
                  child: Center(child: HudLabel(text: 'BUSCANDO...', dot: true)),
                ),
              )
            else if (_searched && _searchResults.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(AppDimensions.spaceXl),
                  child: EmptyState(
                    icon: Icons.person_search_rounded,
                    title: 'SEM RESULTADOS',
                    hud: 'QUERY VAZIA',
                    subtitle: 'Nenhum usuário encontrado.',
                  ),
                ),
              )
            else
              SliverPadding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppDimensions.spaceLg),
                sliver: SliverList.builder(
                  itemCount: _searchResults.length,
                  itemBuilder: (context, i) {
                    final user = _searchResults[i];
                    return MatrixCard(
                      margin: const EdgeInsets.symmetric(
                          vertical: AppDimensions.spaceSm),
                      onTap: () => _openSearchResult(user),
                      child: Row(
                        children: [
                          FramedAvatar(
                            frame: user.frame,
                            size: 42,
                            child: UserAvatar(
                              name: user.nickname,
                              seed: user.avatarSeed ?? user.nickname,
                              imageUrl: user.avatarUrl,
                              size: 36,
                            ),
                          ),
                          const SizedBox(width: AppDimensions.spaceMd),
                          Expanded(
                            child: NicknameRenderer(
                              user.nickname,
                              baseStyle: AppTextStyles.h3,
                              background: AppColors.cardSurface,
                              nameColor: user.nameColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ] else ...[
            // ── AKAME + AMIGOS ──
            // One shared horizontal row: Akame is the FIXED permanent first
            // entry (special chat, never a friend), followed by the friends.
            // Akame stays first no matter how the friend list changes. The
            // section title stays "AMIGOS" (Akame is the special lead-in).
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(
                    left: AppDimensions.spaceLg,
                    right: AppDimensions.spaceLg,
                    bottom: AppDimensions.spaceSm),
                child: HudLabel(text: '👥 AMIGOS'),
              ),
            ),
            _akameFriendsBody(),
            if (_friends.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.spaceLg),
                  child: Text(
                    'Você ainda não possui amigos.',
                    style: AppTextStyles.bodyMuted,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppDimensions.spaceMd),
            ),
            // ── CONVERSAS list ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spaceLg,
                    vertical: AppDimensions.spaceSm),
                child: HudLabel(text: '💬 CONVERSAS'),
              ),
            ),
            _conversationsBody(conversations),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: AppDimensions.spaceXxl)),
        ],
      ),
    );
  }

  /// The horizontal AKAME + AMIGOS row. Akame is ALWAYS the first item,
  /// independent of the friends list contents or loading state — it is a
  /// permanent, special entry of the conversations area, never a friend.
  Widget _akameFriendsBody() {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceLg),
          itemCount: _friends.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: AppDimensions.spaceMd),
          itemBuilder: (context, i) {
            if (i == 0) {
              return _AkameCard(
                onTap: widget.onOpenAkame,
              );
            }
            final friend = _friends[i - 1];
            return GestureDetector(
              onTap: () => _openSearchResult(friend),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FramedAvatar(
                    frame: friend.frame,
                    size: 52,
                    child: UserAvatar(
                      name: friend.nickname,
                      seed: friend.avatarSeed ?? friend.nickname,
                      imageUrl: friend.avatarUrl,
                      size: 46,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spaceXs),
                  SizedBox(
                    width: 64,
                    child: NicknameRenderer(
                      friend.nickname,
                      baseStyle:
                          AppTextStyles.caption.copyWith(fontSize: 11),
                      background: AppColors.absoluteBlack,
                      nameColor: friend.nameColor,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _conversationsBody(List<Conversation> conversations) {
    if (conversations.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(AppDimensions.spaceXl),
          child: EmptyState(
            icon: Icons.forum_outlined,
            title: 'SEM CONVERSAS',
            hud: 'CHAT VAZIO',
            subtitle: 'Suas conversas aparecerão aqui.\n'
                'Comece uma conversa com um amigo.',
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceLg),
      sliver: SliverList.builder(
        itemCount: conversations.length,
        itemBuilder: (context, i) {
          final conv = conversations[i];
          return _ConversationTile(
            conversation: conv,
            onTap: () => openChatConversation(context, conv),
          );
        },
      ),
    );
  }
}

/// A single conversation card: the other user's photo + nickname, the last
/// message (truncated), and its time.
class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final other = conversation.otherUser;
    final last = conversation.lastMessage;
    final lastText = last == null
        ? 'Sem mensagens ainda'
        : (conversation.lastMine ? 'Você: ' : '') + last.content;
    final time = last == null
        ? ''
        : chatListTime(last.createdAt);

    return MatrixCard(
      margin: const EdgeInsets.symmetric(vertical: AppDimensions.spaceSm),
      onTap: onTap,
      child: Row(
        children: [
          FramedAvatar(
            frame: other.frame,
            size: 48,
            child: UserAvatar(
              name: other.nickname,
              seed: other.nickname,
              imageUrl: other.avatarUrl,
              size: 42,
            ),
          ),
          const SizedBox(width: AppDimensions.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                NicknameRenderer(
                  other.nickname,
                  baseStyle: AppTextStyles.h3.copyWith(fontSize: 15),
                  background: AppColors.cardSurface,
                  nameColor: other.nameColor,
                ),
                const SizedBox(height: 2),
                Text(
                  lastText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: conversation.unreadCount > 0
                        ? AppColors.techWhite
                        : AppColors.holographicBlue,
                    fontWeight: conversation.unreadCount > 0
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (time.isNotEmpty) ...[
            const SizedBox(width: AppDimensions.spaceSm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(time, style: AppTextStyles.hud.copyWith(fontSize: 10)),
                if (conversation.unreadCount > 0) ...[
                  const SizedBox(height: 4),
                  _UnreadDot(count: conversation.unreadCount),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primaryBlue,
        borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          color: AppColors.techWhite,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// The fixed, permanent AKAME card of the conversations area. Visually a
/// little chat tile consistent with the friends row (same width/height),
/// reusing the SAME auto-awesome symbol Akame uses across the app. The INSIDE
/// reads IA / Akame under the symbol. It is deliberately distinct from a
/// friend tile — a special chat, not a user. Adapts to the active theme via
/// [AppColors].
class _AkameCard extends StatelessWidget {
  const _AkameCard({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pressed = ValueNotifier(false);
    return ValueListenableBuilder<bool>(
      valueListenable: pressed,
      builder: (context, isPressed, _) {
        return GestureDetector(
          onTapDown: (_) => pressed.value = true,
          onTapUp: (_) => pressed.value = false,
          onTapCancel: () => pressed.value = false,
          onTap: onTap,
          child: AnimatedScale(
            scale: isPressed ? 0.94 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: SizedBox(
              width: 64,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlowContainer(
                    glow: Glow.medium,
                    color: AppColors.glowMedium,
                    background: AppColors.nightBlue,
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                    border: Border.all(
                      color: AppColors.primaryBlue.withValues(alpha: 0.7),
                      width: 1.2,
                    ),
                    child: const SizedBox(
                      width: 52,
                      height: 52,
                      child: Center(
                        child: Icon(Icons.auto_awesome_rounded,
                            color: AppColors.electricBlue, size: 26),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spaceXs),
                  SizedBox(
                    width: 64,
                    child: Column(
                      children: [
                        Text(
                          'IA',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: AppTextStyles.hud.copyWith(
                            fontSize: 9,
                            color: AppColors.electricBlue,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'Akame',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              AppTextStyles.caption.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}