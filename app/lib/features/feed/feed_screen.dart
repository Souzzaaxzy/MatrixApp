import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import 'comments_sheet.dart';
import 'post_card.dart';

/// MATRIX feed — chronological list of posts loaded from the backend.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  @override
  void initState() {
    super.initState();
    // Load the feed on first build. Use post-frame so AppStateScope is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppStateScope.of(context).loadFeed();
    });
  }

  Future<void> _refresh() async {
    await AppStateScope.of(context).loadFeed();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final posts = state.posts;

    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      body: RefreshIndicator(
        color: AppColors.electricBlue,
        backgroundColor: AppColors.nightBlue,
        onRefresh: _refresh,
        child: CustomScrollView(
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
            if (state.isLoadingFeed && posts.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppDimensions.spaceXxl),
                    child: HudLabel(text: 'LOADING FEED...', dot: true),
                  ),
                ),
              )
            else if (posts.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.grid_view_rounded,
                  title: 'NO POSTS YET',
                  hud: 'SYSTEM WAITING...',
                  subtitle: 'Ainda não existem publicações.',
                  action: MatrixButton(
                    label: 'Recarregar',
                    icon: Icons.refresh_rounded,
                    onPressed: _refresh,
                  ),
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
      ),
    );
  }
}
