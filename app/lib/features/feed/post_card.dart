import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/date_utils.dart';
import '../../data/api_config.dart';
import '../../models/post.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/matrix_card.dart';
import '../../core/widgets/nickname_renderer.dart';
import '../../core/widgets/user_avatar.dart';

/// Reusable post card for the feed.
///
/// Likes are toggled remotely via AppState (optimistic update with
/// server confirmation and rollback on failure). Tapping the card opens
/// the post detail screen using the post's real server id.
class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.onComment,
  });

  final Post post;
  final VoidCallback onComment;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _likeController;

  @override
  void initState() {
    super.initState();
    _likeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      lowerBound: 1.0,
      upperBound: 1.35,
    );
  }

  @override
  void dispose() {
    _likeController.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    _likeController.forward(from: 1.0).then((_) => _likeController.reverse());
    final ok = await AppStateScope.of(context).toggleLike(widget.post.id);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível atualizar a curtida. Tente novamente.'),
        ),
      );
    }
  }

  void _openDetail() {
    Navigator.of(context)
        .pushNamed(AppRoutes.postDetail, arguments: widget.post.id);
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    return MatrixCard(
      margin: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spaceLg,
        vertical: AppDimensions.spaceSm,
      ),
      child: InkWell(
        onTap: _openDetail,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(
                  name: post.authorName,
                  seed: post.avatarSeed,
                  imageUrl: post.authorAvatarUrl,
                ),
                const SizedBox(width: AppDimensions.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NicknameRenderer(
                        post.authorName,
                        baseStyle: AppTextStyles.h3,
                        background: AppColors.cardSurface,
                        nameColor: post.authorNameColor,
                        effect: post.authorNameEffect,
                        lightweight: true,
                      ),
                      Text(
                        '@${post.authorUsername} • ${relativeTime(post.createdAt)}',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (post.text.isNotEmpty) ...[
              const SizedBox(height: AppDimensions.spaceLg),
              Text(post.text, style: AppTextStyles.body),
            ],
            if (post.imageUrl != null) ...[
              const SizedBox(height: AppDimensions.spaceMd),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: CachedNetworkImage(
                    imageUrl: ApiConfig.resolveUrl(post.imageUrl!),
                    fit: BoxFit.cover,
                    placeholder: (context, _) => _imagePlaceholder(),
                    errorWidget: (context, _, __) => _imagePlaceholder(),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppDimensions.spaceLg),
            Row(
              children: [
                ScaleTransition(
                  scale: _likeController,
                  child: _ActionButton(
                    icon: post.liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    label: post.likes.toString(),
                    color: post.liked ? AppColors.error : AppColors.holographicBlue,
                    onTap: _toggleLike,
                    semanticLabel: post.liked
                        ? 'Descurtir publicação'
                        : 'Curtir publicação',
                  ),
                ),
                const SizedBox(width: AppDimensions.spaceXl),
                _ActionButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: post.commentCount.toString(),
                  color: AppColors.holographicBlue,
                  onTap: widget.onComment,
                  semanticLabel: 'Abrir comentários',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder() => Container(
        color: AppColors.nightBlue,
        alignment: Alignment.center,
        child: Icon(Icons.broken_image_outlined,
            color: AppColors.deepBlue, size: 32),
      );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spaceSm,
            vertical: AppDimensions.spaceXs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: AppDimensions.spaceSm),
              Text(
                label,
                style: AppTextStyles.caption.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
