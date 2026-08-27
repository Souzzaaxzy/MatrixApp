import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart' show LongPressGestureRecognizer;
import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/profile_navigation.dart';
import '../../core/widgets/nickname_renderer.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/framed_avatar.dart';
import '../../core/widgets/glow_container.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/api_config.dart';
import '../../models/friend_request.dart';
import '../../models/matrix_user.dart';
import '../../models/post.dart';
import '../chat/chat_navigation.dart';
import 'friends_sheet.dart';
import 'settings_sheet.dart';

/// Profile screen — the server is the single source of truth.
///
/// [nickname] null (or equal to the session user's) means "own profile":
/// renders the Edit button and the floating "+" create-post button, and
/// NEVER the friendship button. Another user's profile shows the big
/// Seguir / Solicitado / Amigos friendship button (server-managed state).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.nickname});

  final String? nickname;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _requested = false;
  String? _error;
  bool _sending = false;

  /// The real user id this screen is presenting (once loaded). Used to
  /// register/un-register the profile in the navigation stack and to guard
  /// the photo long-press "view only on another user's profile".
  String? _shownUserId;

  /// The own-profile tab (nickname == null) lives inside a persistent
  /// IndexedStack tab — it must stay registered as open and never un-register
  /// on dispose. A pushed ProfileScreen (nickname != null) pops and un-registers.
  bool get _isTab => widget.nickname == null;

  bool get _isOwn {
    final state = AppStateScope.of(context);
    return widget.nickname == null ||
        widget.nickname!.toLowerCase() ==
            (state.currentUser?.nickname.toLowerCase() ?? '');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) {
      _requested = true;
      // Defer: loadProfile notifies listeners, which is not allowed
      // synchronously during the build phase.
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    // A pushed profile route pops and must release its slot so the same
    // profile can be opened again later. The persistent own-profile tab
    // stays registered for the app lifetime.
    if (!_isTab) {
      final id = _shownUserId;
      if (id != null) closeProfile(id);
    }
    super.dispose();
  }

  Future<void> _load() async {
    final state = AppStateScope.of(context);
    final nickname = widget.nickname ?? state.currentUser?.nickname;
    if (nickname == null) return;
    setState(() => _error = null);
    try {
      await state.loadProfile(nickname);
      if (!mounted) return;
      // Register the profile by its REAL id once it resolves. Called both on
      // the first load and on refresh — re-adding the same id is a no-op.
      final loaded = state.profileFor(widget.nickname)?.user;
      if (loaded != null) {
        _shownUserId = loaded.id;
        markProfileOpen(loaded.id);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'Não foi possível conectar ao MATRIX. '
            'Verifique sua conexão.',
      );
    }
  }

  Future<void> _openEditProfile() async {
    await Navigator.of(context).pushNamed(AppRoutes.editProfile);
    // Reload from the server after editing so the profile always reflects
    // what was actually persisted.
    await _load();
  }

  void _openPost(Post post) {
    Navigator.of(context).pushNamed(AppRoutes.postDetail, arguments: post.id);
  }

  Future<void> _sendFriendRequest(String userId) async {
    setState(() => _sending = true);
    try {
      await AppStateScope.of(context).sendFriendRequest(userId);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro de conexão.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final isOwn = _isOwn;
    final sessionUser = state.currentUser;

    if (sessionUser == null) {
      return Scaffold(
        backgroundColor: AppColors.absoluteBlack,
        body: Center(child: HudLabel(text: 'NOT AUTHENTICATED', dot: true)),
      );
    }

    // The viewed profile is read from ITS OWN keyed slot — never from a
    // shared variable. Visiting B and coming back shows A immediately,
    // because A's slot was never overwritten by B.
    final profile = state.profileFor(widget.nickname);
    final user = profile?.user ?? (isOwn ? sessionUser : null);
    final posts = profile?.posts ?? const <Post>[];
    final friendship = profile?.friendship;
    final loading = state.isLoadingProfile && profile == null;

    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      floatingActionButton: isOwn ? const CreatePostFab() : null,
      body: RefreshIndicator(
        color: AppColors.electricBlue,
        backgroundColor: AppColors.nightBlue,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              automaticallyImplyLeading: false,
              backgroundColor: AppColors.absoluteBlack,
              surfaceTintColor: Colors.transparent,
              // The ☰ settings menu exists ONLY on the own profile — on
              // another user's profile there is no logout/delete entry.
              leading: isOwn
                  ? IconButton(
                      tooltip: 'Configurações',
                      icon: Icon(Icons.menu_rounded,
                          color: AppColors.holographicBlue),
                      onPressed: () => SettingsSheet.open(context),
                    )
                  : null,
              title:
                  Text('PERFIL', style: AppTextStyles.title.copyWith(fontSize: 18)),
            ),
            if (loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: HudLabel(text: 'LOADING PROFILE...', dot: true),
                ),
              )
            else if (_error != null && profile == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'CONNECTION ERROR',
                  hud: 'OFFLINE',
                  subtitle: _error!,
                  action: MatrixButton(
                    label: 'Tentar novamente',
                    icon: Icons.refresh_rounded,
                    onPressed: _load,
                  ),
                ),
              )
            else if (user != null) ...[
              SliverToBoxAdapter(
                child: _ProfileHeader(
                  user: user,
                  isOwn: isOwn,
                  friendship: friendship,
                  sending: _sending,
                  onEdit: _openEditProfile,
                  onSend: () => _sendFriendRequest(user.id),
                  onFriendsTap: () => FriendsSheet.open(context, user),
                  onMessage: () => openChatWithUser(context, user),
                ),
              ),
              SliverToBoxAdapter(
                child: Divider(color: AppColors.deepBlue, height: 1),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: AppDimensions.spaceMd),
                  child: Center(child: HudLabel(text: 'PUBLICAÇÕES')),
                ),
              ),
              if (posts.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.grid_view_rounded,
                    title: 'NO POSTS YET',
                    hud: 'SYSTEM WAITING...',
                    subtitle: isOwn
                        ? 'Você ainda não publicou nada.'
                        : 'Este usuário ainda não publicou nada.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spaceLg,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: AppDimensions.spaceMd,
                      crossAxisSpacing: AppDimensions.spaceMd,
                      childAspectRatio: 0.9,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final post = posts[i];
                        return _ProfilePostTile(
                          post: post,
                          onTap: () => _openPost(post),
                        );
                      },
                      childCount: posts.length,
                    ),
                  ),
                ),
            ],
            // Room for the floating "+" so it never covers the last tile.
            const SliverToBoxAdapter(
              child: SizedBox(height: AppDimensions.spaceHuge * 2),
            ),
          ],
        ),
      ),
    );
  }
}

/// The centered header: big avatar, @nickname with a subtle glow on the @,
/// and either the edit CTA (own profile) or the friendship button.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.user,
    required this.isOwn,
    required this.friendship,
    required this.sending,
    required this.onEdit,
    required this.onSend,
    required this.onFriendsTap,
    required this.onMessage,
  });

  final MatrixUser user;
  final bool isOwn;
  final Friendship? friendship;
  final bool sending;
  final VoidCallback onEdit;
  final VoidCallback onSend;
  final VoidCallback onFriendsTap;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final avatar = GlowContainer(
      glow: Glow.medium,
      color: AppColors.glowSmall,
      background: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: FramedAvatar(
        frame: user.frame,
        size: 110,
        child: UserAvatar(
          name: user.nickname,
          seed: user.avatarSeed ?? user.nickname,
          imageUrl: user.avatarUrl,
          size: 98,
          ring: true,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(AppDimensions.spaceXl),
      child: Column(
        children: [
          // Long-press (≈2s) on ANOTHER user's profile enlarges their photo
          // (view-only, circular, dismiss on outside tap). This behavior is
          // LOCAL to the profile screen — it never activates in the feed,
          // comments, search, friends or any other list. A simple tap does
          // nothing here (the photo is not a navigation element on its own
          // profile).
          RawGestureDetector(
            // Long press must be held ~2 seconds before it fires — a plain
            // tap never opens the enlarged photo.
            gestures: {
              LongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  duration: const Duration(seconds: 2),
                ),
                (instance) {
                  if (!isOwn) {
                    instance.onLongPress = () => _showProfilePhotoZoom(
                          context,
                          user: user,
                          enabled: true,
                        );
                  }
                },
              ),
            },
            behavior: HitTestBehavior.opaque,
            child: avatar,
          ),
          const SizedBox(height: AppDimensions.spaceLg),
          // The nickname rendered plain (never '@') — the single visual
          // identity of the account.
          NicknameRenderer(
            user.nickname,
            baseStyle: AppTextStyles.h2.copyWith(fontSize: 22),
            background: AppColors.absoluteBlack,
            nameColor: user.nameColor,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppDimensions.spaceLg),
          // Real counters (server): Amigos opens the friends bottom sheet.
          _ProfileStats(user: user, onFriendsTap: onFriendsTap),
          if (user.bio.isNotEmpty) ...[
            const SizedBox(height: AppDimensions.spaceMd),
            Text(
              user.bio,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMuted,
            ),
          ],
          const SizedBox(height: AppDimensions.spaceXl),
          if (isOwn)
            MatrixButton(
              label: 'Editar perfil',
              icon: Icons.edit_rounded,
              variant: MatrixButtonVariant.outline,
              expanded: true,
              onPressed: onEdit,
            )
          else if (friendship == Friendship.friends)
            // Friends → two equal buttons side by side: Amigos + Mensagem.
            Row(
              children: [
                Expanded(
                  child: MatrixButton(
                    label: 'Amigos',
                    icon: Icons.favorite_rounded,
                    variant: MatrixButtonVariant.outline,
                    onPressed: null,
                  ),
                ),
                const SizedBox(width: AppDimensions.spaceMd),
                Expanded(
                  child: MatrixButton(
                    label: 'Mensagem',
                    icon: Icons.chat_bubble_rounded,
                    onPressed: onMessage,
                  ),
                ),
              ],
            )
          else
            FriendshipButton(
              friendship: friendship,
              sending: sending,
              onSend: onSend,
            ),
        ],
      ),
    );
  }
}

/// Shows a large, centered, circular view of another user's profile photo
/// over the current interface. It is intentionally VIEW-ONLY: it never edits
/// the photo, never opens an image picker and never navigates. Tapping
/// OUTSIDE the circle closes it; tapping inside does nothing (avoids
/// accidental dismissal and conflicts with tap/long-press/navigation).
///
/// This is invoked ONLY from the profile screen's header when viewing
/// someone else's profile — it is not reachable from the feed, comments,
/// search, friends or any other surface.
void _showProfilePhotoZoom(
  BuildContext context, {
  required MatrixUser user,
  required bool enabled,
}) {
  if (!enabled) return;
  showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    barrierDismissible: true,
    builder: (dialogContext) {
      final screen = MediaQuery.sizeOf(dialogContext);
      final diameter = screen.shortestSide * 0.72;
      return GestureDetector(
        // Tapping the dark outside area closes it (the dialog barrier also
        // dismisses, but the explicit GestureDetector makes "tap outside the
        // circle" deterministic on every surface).
        onTap: () => Navigator.of(dialogContext).pop(),
        behavior: HitTestBehavior.opaque,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: EdgeInsets.zero,
          child: Center(
            child: GestureDetector(
              // Tapping INSIDE the photo does nothing — no accidental close.
              onTap: () {},
              child: SizedBox(
                width: diameter,
                height: diameter,
                child: ClipOval(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      UserAvatar(
                        name: user.nickname,
                        seed: user.avatarSeed ?? user.nickname,
                        imageUrl: user.avatarUrl,
                        size: diameter,
                        ring: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Real counters row — Amigos (tappable → friends bottom sheet) and Posts.
/// The numbers come from the server profile payload, so a viewed profile
/// always shows THAT user's counts, never the session user's.
class _ProfileStats extends StatelessWidget {
  const _ProfileStats({required this.user, required this.onFriendsTap});

  final MatrixUser user;
  final VoidCallback onFriendsTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StatColumn(
          count: user.friendsCount,
          label: 'Amigos',
          onTap: onFriendsTap,
        ),
        const SizedBox(width: AppDimensions.spaceXxl),
        _StatColumn(count: user.postsCount, label: 'Posts'),
      ],
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.count, required this.label, this.onTap});

  final int count;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spaceMd,
          vertical: AppDimensions.spaceXs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: AppTextStyles.h3.copyWith(
                fontSize: 20,
                color: AppColors.electricBlue,
                shadows: const [
                  Shadow(color: AppColors.electricBlue, blurRadius: 12),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: AppTextStyles.hud.copyWith(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}


/// The big friendship button with the three server-managed states:
/// Adicionar (sends a request) / Solicitado (disabled) / Amigos (disabled).
class FriendshipButton extends StatelessWidget {
  const FriendshipButton({
    super.key,
    required this.friendship,
    required this.sending,
    required this.onSend,
  });

  final Friendship? friendship;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final state = friendship ?? Friendship.none;
    switch (state) {
      case Friendship.friends:
        return const MatrixButton(
          label: 'Amigos',
          icon: Icons.favorite_rounded,
          variant: MatrixButtonVariant.outline,
          expanded: true,
          onPressed: null,
        );
      case Friendship.outgoingPending:
      case Friendship.incomingPending:
        return const MatrixButton(
          label: 'Solicitado',
          icon: Icons.watch_later_rounded,
          variant: MatrixButtonVariant.outline,
          expanded: true,
          onPressed: null,
        );
      case Friendship.none:
        return MatrixButton(
          label: 'Adicionar',
          icon: Icons.person_add_rounded,
          expanded: true,
          isLoading: sending,
          onPressed: onSend,
        );
    }
  }
}

/// The floating "+" button — only rendered on the own profile. Reuses the
/// existing create-post flow (same target the old menu entry used).
class CreatePostFab extends StatelessWidget {
  const CreatePostFab({super.key});

  @override
  Widget build(BuildContext context) {
    return GlowContainer(
      glow: Glow.medium,
      color: AppColors.glowMedium,
      background: AppColors.primaryBlue,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.createPost),
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: EdgeInsets.all(AppDimensions.spaceLg),
          child: Icon(Icons.add_rounded, size: 28, color: AppColors.techWhite),
        ),
      ),
    );
  }
}

/// A tappable grid tile for a profile post. Opens the post detail screen.
class _ProfilePostTile extends StatelessWidget {
  const _ProfilePostTile({required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bluishBlack,
      borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (post.imageUrl != null)
                CachedNetworkImage(
                  imageUrl: ApiConfig.resolveUrl(post.imageUrl!),
                  fit: BoxFit.cover,
                  placeholder: (_, __) => _placeholder(),
                  errorWidget: (_, __, ___) => _placeholder(),
                )
              else
                _placeholder(),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(AppDimensions.spaceSm),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Row(
                    children: [
                      // The heart reflects the REAL like state, the same
                      // everywhere (feed, detail, profile): filled when the
                      // authenticated user liked the post, empty otherwise —
                      // driven by post.liked, which the server computes from
                      // the AUTHENTICATED token user.
                      Icon(
                        post.liked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: post.liked
                            ? AppColors.error
                            : AppColors.holographicBlue,
                        size: 14,
                      ),
                      const SizedBox(width: AppDimensions.spaceXs),
                      Text('${post.likes}', style: AppTextStyles.caption),
                      const SizedBox(width: AppDimensions.spaceMd),
                      Icon(Icons.chat_bubble_outline_rounded,
                          color: AppColors.holographicBlue, size: 13),
                      const SizedBox(width: AppDimensions.spaceXs),
                      Text('${post.commentCount}', style: AppTextStyles.caption),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.nightBlue,
      padding: const EdgeInsets.all(AppDimensions.spaceSm),
      alignment: Alignment.center,
      child: Text(
        post.text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: AppTextStyles.caption,
      ),
    );
  }
}
