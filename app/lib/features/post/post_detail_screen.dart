import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/date_utils.dart';
import '../../core/widgets/nickname_renderer.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/api_config.dart';
import '../../models/post.dart';
import '../feed/comments_sheet.dart';

/// Post detail screen — opened by tapping a post in the feed or in the
/// profile grid. Loads the post fresh from the server by its real id.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  Post? _post;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Defer: AppStateScope.of() cannot be called from initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final post = await AppStateScope.of(context).getPost(widget.postId);
      if (!mounted) return;
      setState(() {
        _post = post;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível carregar a publicação.';
        _loading = false;
      });
    }
  }

  bool _deleting = false;

  /// Only the author sees the delete option — and the server enforces it
  /// again with a 403 for non-owners, so hiding the menu is just UX.
  bool get _isAuthor {
    final me = AppStateScope.of(context).currentUser;
    final post = _post;
    return me != null && post != null && post.authorId == me.id;
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bluishBlack,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          side: BorderSide(color: AppColors.deepBlue),
        ),
        title: Text('Excluir publicação?', style: AppTextStyles.h3),
        content: Text(
          'Essa ação não pode ser desfeita.',
          style: AppTextStyles.bodyMuted,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancelar',
                style: AppTextStyles.label
                    .copyWith(color: AppColors.holographicBlue)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Excluir',
                style: AppTextStyles.label.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _delete();
  }

  Future<void> _delete() async {
    final post = _post;
    if (post == null || _deleting) return;
    setState(() => _deleting = true);
    final ok = await AppStateScope.of(context).deletePost(post.id);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Publicação excluída.')),
      );
      Navigator.of(context).pop(true);
    } else {
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível excluir a publicação.'),
        ),
      );
    }
  }

  Future<void> _toggleLike() async {
    final post = _post;
    if (post == null) return;
    // AppState mutates this very object (it comes from its cache): the
    // optimistic update is applied immediately, confirmed or rolled back
    // by the server response.
    final ok = await AppStateScope.of(context).toggleLike(post.id);
    if (!mounted) return;
    setState(() {});
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível atualizar a curtida. Tente novamente.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.techWhite),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('PUBLICAÇÃO', style: AppTextStyles.title.copyWith(fontSize: 18)),
        actions: [
          if (_isAuthor)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded,
                  color: AppColors.techWhite),
              color: AppColors.bluishBlack,
              enabled: !_deleting,
              onSelected: (value) {
                if (value == 'delete') _confirmDelete();
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete_outline_rounded,
                          color: AppColors.error, size: 20),
                      const SizedBox(width: AppDimensions.spaceSm),
                      Flexible(
                        child: Text('Excluir publicação',
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body
                                .copyWith(color: AppColors.error)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: HudLabel(text: 'LOADING POST...', dot: true));
    }
    if (_error != null) {
      return Center(
        child: EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'ERROR',
          hud: 'REQUEST FAILED',
          subtitle: _error!,
          action: MatrixButton(
            label: 'Tentar novamente',
            icon: Icons.refresh_rounded,
            onPressed: _load,
          ),
        ),
      );
    }
    final post = _post!;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppDimensions.spaceLg),
          if (post.imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
              child: CachedNetworkImage(
                imageUrl: ApiConfig.resolveUrl(post.imageUrl!),
                fit: BoxFit.cover,
                placeholder: (_, __) => _imagePlaceholder(),
                errorWidget: (_, __, ___) => _imagePlaceholder(),
              ),
            ),
          const SizedBox(height: AppDimensions.spaceLg),
          Row(
            children: [
              UserAvatar(
                name: post.authorNickname,
                seed: post.avatarSeed,
                imageUrl: post.authorAvatarUrl,
              ),
              const SizedBox(width: AppDimensions.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NicknameRenderer(
                      post.authorNickname,
                      baseStyle: AppTextStyles.h3,
                      background: AppColors.cardSurface,
                      nameColor: post.authorNicknameColor,
                    ),
                    Text(
                      '${post.authorNickname} • ${relativeTime(post.createdAt)}',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.spaceLg),
          Row(
            children: [
              _DetailAction(
                icon: post.liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                label: '${post.likes}',
                color: post.liked ? AppColors.error : AppColors.holographicBlue,
                onTap: _toggleLike,
                semanticLabel:
                    post.liked ? 'Descurtir publicação' : 'Curtir publicação',
              ),
              const SizedBox(width: AppDimensions.spaceXl),
              _DetailAction(
                icon: Icons.chat_bubble_outline_rounded,
                label: '${post.commentCount}',
                color: AppColors.holographicBlue,
                onTap: () async {
                  await CommentsSheet.show(context, post: post);
                  if (mounted) setState(() {});
                },
                semanticLabel: 'Abrir comentários',
              ),
            ],
          ),
          if (post.text.isNotEmpty) ...[
            const SizedBox(height: AppDimensions.spaceLg),
            Text(post.text, style: AppTextStyles.body),
          ],
          const SizedBox(height: AppDimensions.spaceXxl),
        ],
      ),
    );
  }

  Widget _imagePlaceholder() => Container(
        height: 220,
        color: AppColors.nightBlue,
        alignment: Alignment.center,
        child: Icon(Icons.broken_image_outlined,
            color: AppColors.deepBlue, size: 32),
      );
}

class _DetailAction extends StatelessWidget {
  const _DetailAction({
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
              Icon(icon, size: 20, color: color),
              const SizedBox(width: AppDimensions.spaceSm),
              Text(label, style: AppTextStyles.body.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
