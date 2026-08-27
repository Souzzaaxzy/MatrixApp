import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/profile_navigation.dart';
import '../../core/widgets/nickname_renderer.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/framed_avatar.dart';
import '../../core/widgets/theme_watcher.dart';
import '../../core/widgets/user_avatar.dart';
import '../../models/comment.dart';
import '../../models/cosmetic_item.dart';
import '../../models/post.dart';

/// Bottom sheet showing comments for a post.
///
/// New comments are added locally in Phase 1.
class CommentsSheet extends StatefulWidget {
  const CommentsSheet({super.key, required this.post});

  final Post post;

  static Future<void> show(BuildContext context, {required Post post}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimensions.radiusXl),
        ),
      ),
      // ThemeWatcher keeps the sheet on the active palette when the theme
      // flips while it is open.
      builder: (_) => ThemeWatcher(
        builder: (_) => CommentsSheet(post: post),
      ),
    );
  }

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _controller = TextEditingController();
  List<Comment>? _comments;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Defer: AppStateScope.of() cannot be called from initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadComments();
    });
  }

  Future<void> _loadComments() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final comments =
          await AppStateScope.of(context).loadComments(widget.post.id);
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar comentários.';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    FocusScope.of(context).unfocus();
    try {
      final comment =
          await AppStateScope.of(context).addComment(widget.post.id, text);
      setState(() {
        _comments = [...?_comments, comment];
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao enviar comentário.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final comments = _comments ?? <Comment>[];

    // Respect the Android system navigation bar (gesture/nav-bar inset) AND
    // the IME (keyboard) inset so the input bar is never hidden behind either
    // of them. No fixed margins/paddings: both insets come from the platform.
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final bottomInset = viewInsets.bottom > 0
        ? viewInsets.bottom
        : viewPadding.bottom;
    final viewportHeight = MediaQuery.sizeOf(context).height;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: viewportHeight * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin:
                  const EdgeInsets.symmetric(vertical: AppDimensions.spaceMd),
              decoration: BoxDecoration(
                color: AppColors.deepBlue,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const HudLabel(text: 'COMMENTS'),
            Divider(
                color: AppColors.deepBlue, height: AppDimensions.spaceXl),
            Flexible(
            child: _loading
                ? const Center(
                    child: HudLabel(text: 'LOADING...', dot: true),
                  )
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, style: AppTextStyles.bodyMuted),
                            const SizedBox(height: AppDimensions.spaceMd),
                            TextButton(
                              onPressed: _loadComments,
                              child: const Text('Tentar novamente'),
                            ),
                          ],
                        ),
                      )
                    : comments.isEmpty
                        ? Center(
                            child: Text(
                              'Seja o primeiro a comentar.',
                              style: AppTextStyles.bodyMuted,
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDimensions.spaceLg,
                            ),
                            itemCount: comments.length,
                    separatorBuilder: (_, __) =>
                        Divider(color: AppColors.deepBlue, height: 1),
                    itemBuilder: (context, i) {
                      final c = comments[i];
                      // Tapping the COMMENT AUTHOR's photo or nickname opens
                      // THEIR profile (by real id), never the session user's
                      // and never the post author's by mistake.
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppDimensions.spaceMd,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () => openProfileById(
                                context,
                                id: c.authorId,
                                nickname: c.authorNickname,
                              ),
                              behavior: HitTestBehavior.opaque,
                              child: FramedAvatar(
                                frame: c.authorFrameId == null
                                    ? null
                                    : CosmeticItem(
                                        id: c.authorFrameId!,
                                        slot: CosmeticItem.avatarFrame,
                                        name: c.authorFrameId!,
                                        assetUrl: c.authorFrameAsset ?? '',
                                      ),
                                size: 32,
                                child: UserAvatar(
                                  name: c.authorNickname,
                                  imageUrl: c.authorAvatarUrl,
                                  size: 27,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppDimensions.spaceMd),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: GestureDetector(
                                          onTap: () => openProfileById(
                                            context,
                                            id: c.authorId,
                                            nickname: c.authorNickname,
                                          ),
                                          behavior: HitTestBehavior.opaque,
                                          child: NicknameRenderer(
                                            c.authorNickname,
                                            baseStyle: AppTextStyles.label,
                                            background: AppColors.nightBlue,
                                            nameColor: c.authorNicknameColor,
                                          ),
                                        ),
                                      ),
                                      if (c.authorId.isNotEmpty &&
                                          c.authorId ==
                                              widget.post.authorId) ...[
                                        const SizedBox(
                                            width: AppDimensions.spaceXs),
                                        const _AuthorBadge(),
                                      ],
                                      const SizedBox(width: AppDimensions.spaceSm),
                                      Text(
                                        relativeTimeString(c.createdAt),
                                        style: AppTextStyles.hud.copyWith(fontSize: 10),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppDimensions.spaceXs),
                                  Text(c.text, style: AppTextStyles.body),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.spaceLg,
                vertical: AppDimensions.spaceSm,
              ),
              decoration: BoxDecoration(
                color: AppColors.bluishBlack,
                border: Border(
                  top: BorderSide(color: AppColors.deepBlue, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: AppTextStyles.body,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Escreva um comentário...',
                        hintStyle: AppTextStyles.bodyMuted,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send_rounded,
                        color: AppColors.electricBlue),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small "Autor" badge shown next to the nickname when the commenter is
/// the author of the post (compared by user id, never by nickname).
class _AuthorBadge extends StatelessWidget {
  const _AuthorBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.electricBlue.withValues(alpha: 0.15),
        border: Border.all(color: AppColors.electricBlue, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'AUTOR',
        style: AppTextStyles.hud.copyWith(
          fontSize: 9,
          color: AppColors.electricBlue,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
