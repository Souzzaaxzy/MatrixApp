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
import '../../models/post.dart';

/// Profile screen showing the current user and their posts grid.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final user = state.currentUser;
    final userPosts = user == null
        ? <Post>[]
        : state.posts.where((p) => p.authorUsername == user.username).toList();

    if (user == null) {
      return Scaffold(
        backgroundColor: AppColors.absoluteBlack,
        body: const Center(
          child: HudLabel(text: 'NOT AUTHENTICATED', dot: true),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.absoluteBlack,
            surfaceTintColor: Colors.transparent,
            title: Text('PERFIL', style: AppTextStyles.title.copyWith(fontSize: 18)),
          ),
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
                      seed: user.avatarSeed,
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
                    onPressed: () =>
                        Navigator.of(context).pushNamed(AppRoutes.editProfile),
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
          if (userPosts.isEmpty)
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
                    final post = userPosts[i];
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
                      child: Container(
                        color: AppColors.bluishBlack,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (post.imageUrl != null)
                              Image.network(
                                post.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _profileTilePlaceholder(post.text),
                              )
                            else
                              _profileTilePlaceholder(post.text),
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
                                    Text(
                                      '${post.likes}',
                                      style: AppTextStyles.caption,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: userPosts.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(
            child: SizedBox(height: AppDimensions.spaceXxl),
          ),
        ],
      ),
    );
  }

  Widget _profileTilePlaceholder(String text) {
    return Container(
      color: AppColors.nightBlue,
      padding: const EdgeInsets.all(AppDimensions.spaceSm),
      alignment: Alignment.center,
      child: Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: AppTextStyles.caption,
      ),
    );
  }
}
