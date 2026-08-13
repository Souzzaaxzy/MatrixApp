import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/hud_label.dart';
import 'comments_sheet.dart';
import 'post_card.dart';

/// MATRIX feed — chronological list of posts.
class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final posts = state.posts;

    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.absoluteBlack,
            surfaceTintColor: Colors.transparent,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('MATRIX', style: AppTextStyles.title.copyWith(fontSize: 22)),
                const SizedBox(width: AppDimensions.spaceLg),
                const HudLabel(text: 'ONLINE', color: AppColors.success, dot: true),
              ],
            ),
          ),
          if (posts.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.grid_view_rounded,
                title: 'NO POSTS YET',
                hud: 'SYSTEM WAITING...',
                subtitle: 'Ainda não existem publicações.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(
                bottom: AppDimensions.spaceXxl,
                top: AppDimensions.spaceSm,
              ),
              sliver: SliverList.builder(
                itemCount: posts.length,
                itemBuilder: (context, i) {
                  final post = posts[i];
                  return PostCard(
                    post: post,
                    onComment: () => CommentsSheet.show(context, post: post),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
