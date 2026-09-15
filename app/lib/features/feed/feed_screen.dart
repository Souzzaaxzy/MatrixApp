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
import 'stories_header.dart';

/// MATRIX feed — chronological list of posts loaded from the backend.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final ScrollController _scroll = ScrollController();

  /// Id of the post whose video preview should be playing (single-active).
  /// Updated on scroll; passed down so only ONE video ever autoplays.
  String? _activeVideoId;

  /// Global keys for the video posts, used to compute the most visible one.
  final Map<String, GlobalKey> _videoKeys = {};

  @override
  void initState() {
    super.initState();
    // Load the feed on first build. Use post-frame so AppStateScope is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppStateScope.of(context).loadFeed();
      // Stories strip at the top of the feed (independent load: a failure
      // there must never affect the posts).
      AppStateScope.of(context).loadStories();
    });
    _scroll.addListener(_updateActiveVideo);
  }

  @override
  void dispose() {
    _scroll.removeListener(_updateActiveVideo);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    // Captura o state ANTES de qualquer await (evita BuildContext após gap).
    final state = AppStateScope.of(context);
    await state.loadFeed();
    // Stories refresh alongside the feed (same gesture) — a failure there
    // never blocks the posts.
    await state.loadStories();
    _updateActiveVideo();
  }

  /// Picks the video post that is CLOSEST to the viewport center and makes
  /// it the active (playing) preview; all others pause.
  void _updateActiveVideo() {
    if (!mounted || _videoKeys.isEmpty) return;
    final renderView = View.of(context);
    final viewportHeight =
        renderView.physicalSize.height / renderView.devicePixelRatio;
    double? closestDist;
    String? closestId;
    for (final entry in _videoKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      final h = box.size.height;
      final center = y + h / 2;
      final dist = (center - viewportHeight / 2).abs();
      if (closestDist == null || dist < closestDist) {
        closestDist = dist;
        closestId = entry.key;
      }
    }
    if (closestId != _activeVideoId) {
      setState(() => _activeVideoId = closestId);
    }
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
          controller: _scroll,
          slivers: [
            SliverAppBar(
              pinned: true,
              automaticallyImplyLeading: false,
              backgroundColor: AppColors.absoluteBlack,
              surfaceTintColor: Colors.transparent,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('MATRIX',
                      style: AppTextStyles.title.copyWith(fontSize: 22)),
                  const SizedBox(width: AppDimensions.spaceLg),
                  const HudLabel(
                      text: 'ONLINE', color: AppColors.success, dot: true),
                ],
              ),
            ),
            // Stories ficam ANTES dos posts, claramente separados do feed
            // (mesmo sliver, mas com o divisor da própria faixa). Só aparece
            // para usuários autenticados — o feed em si continua público.
            if (state.isAuthenticated)
              SliverToBoxAdapter(
                child: StoriesHeader(state: state),
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
                    final isVideo = post.isVideo;
                    // Register a key for video posts so the feed can pick the
                    // most-visible one for autoplay.
                    final videoKey =
                        isVideo ? (_videoKeys[post.id] ??= GlobalKey()) : null;
                    return KeyedSubtree(
                      key: ObjectKey(post.id),
                      child: PostCard(
                        post: post,
                        onComment: () =>
                            CommentsSheet.show(context, post: post),
                        videoActive: isVideo && _activeVideoId == post.id,
                        videoKey: videoKey,
                      ),
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
