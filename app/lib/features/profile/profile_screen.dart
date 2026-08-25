import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/glow_container.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/api_config.dart';
import '../../models/friend_request.dart';
import '../../models/matrix_user.dart';
import '../../models/post.dart';
import 'friends_sheet.dart';
import 'settings_sheet.dart';

/// Profile screen — the server is the single source of truth.
///
/// [username] null (or equal to the session user's) means "own profile":
/// renders the Edit button and the floating "+" create-post button, and
/// NEVER the friendship button. Another user's profile shows the big
/// Seguir / Solicitado / Amigos friendship button (server-managed state).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.username});

  final String? username;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _requested = false;
  String? _error;
  bool _sending = false;

  bool get _isOwn {
    final state = AppStateScope.of(context);
    return widget.username == null ||
        widget.username!.toLowerCase() ==
            (state.currentUser?.username.toLowerCase() ?? '');
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

  Future<void> _load() async {
    final state = AppStateScope.of(context);
    final username = widget.username ?? state.currentUser?.username;
    if (username == null) return;
    setState(() => _error = null);
    try {
      await state.loadProfile(username);
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
    final profile = state.profileFor(widget.username);
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
  });

  final MatrixUser user;
  final bool isOwn;
  final Friendship? friendship;
  final bool sending;
  final VoidCallback onEdit;
  final VoidCallback onSend;
  final VoidCallback onFriendsTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppDimensions.spaceXl),
      child: Column(
        children: [
          GlowContainer(
            glow: Glow.medium,
            color: AppColors.glowSmall,
            background: Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            child: UserAvatar(
              name: user.name,
              seed: user.avatarSeed ?? user.username,
              imageUrl: user.avatarUrl,
              size: 110,
              ring: true,
            ),
          ),
          const SizedBox(height: AppDimensions.spaceLg),
          // The server username (not the display name) with a discreet
          // glowing "@" — blurred shadow per the design spec.
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '@',
                  style: TextStyle(
                    color: AppColors.holographicBlue,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    shadows: const [
                      Shadow(color: AppColors.electricBlue, blurRadius: 10),
                    ],
                  ),
                ),
                TextSpan(
                  text: user.username,
                  style: AppTextStyles.h2.copyWith(fontSize: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spaceMd),
          if (user.name.isNotEmpty)
            Text(user.name, style: AppTextStyles.bodyMuted),
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
                      const Icon(Icons.favorite_rounded,
                          color: AppColors.error, size: 14),
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
