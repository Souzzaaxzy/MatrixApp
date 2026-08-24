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
import '../../models/post.dart';

/// Profile screen — the server is the single source of truth.
///
/// Every time the tab is opened the profile (user + posts) is fetched
/// fresh from GET /api/users/:username; nothing here is derived from the
/// local feed cache.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _requested = false;
  String? _error;

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
    final username = state.currentUser?.username;
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

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final sessionUser = state.currentUser;

    if (sessionUser == null) {
      return const Scaffold(
        backgroundColor: AppColors.absoluteBlack,
        body: Center(child: HudLabel(text: 'NOT AUTHENTICATED', dot: true)),
      );
    }

    // The server profile wins over the session snapshot when available.
    final user = state.profileUser ?? sessionUser;
    final posts = state.profilePosts;
    final loading = state.isLoadingProfile && state.profileUser == null;

    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
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
            else if (_error != null && state.profileUser == null)
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
            else ...[
              SliverToBoxAdapter(
                child: Padding(
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
                          size: 96,
                          ring: true,
                        ),
                      ),
                      const SizedBox(height: AppDimensions.spaceLg),
                      Text(user.name, style: AppTextStyles.h1.copyWith(fontSize: 22)),
                      const SizedBox(height: AppDimensions.spaceXs),
                      Text('@${user.username}', style: AppTextStyles.caption),
                      const SizedBox(height: AppDimensions.spaceMd),
                      const HudLabel(text: 'USER CONNECTED', dot: true),
                      const SizedBox(height: AppDimensions.spaceLg),
                      if (user.bio.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDimensions.spaceXl,
                          ),
                          child: Text(
                            user.bio,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMuted,
                          ),
                        ),
                      const SizedBox(height: AppDimensions.spaceXl),
                      MatrixButton(
                        label: 'Editar perfil',
                        icon: Icons.edit_rounded,
                        variant: MatrixButtonVariant.outline,
                        expanded: true,
                        onPressed: _openEditProfile,
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: Divider(color: AppColors.deepBlue, height: 1),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: AppDimensions.spaceMd),
                  child: Center(child: HudLabel(text: 'PUBLICAÇÕES')),
                ),
              ),
              if (posts.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.grid_view_rounded,
                    title: 'NO POSTS YET',
                    hud: 'SYSTEM WAITING...',
                    subtitle: 'Você ainda não publicou nada.',
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
            const SliverToBoxAdapter(
              child: SizedBox(height: AppDimensions.spaceXxl),
            ),
          ],
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
                      const Icon(Icons.chat_bubble_outline_rounded,
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
