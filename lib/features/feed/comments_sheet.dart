import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/date_utils.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/user_avatar.dart';
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
      backgroundColor: AppColors.nightBlue,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimensions.radiusXl),
        ),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: CommentsSheet(post: post),
      ),
    );
  }

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    AppStateScope.of(context).addComment(widget.post.id, text);
    _controller.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    // Re-read comments from state so the sheet reflects additions.
    final post = state.posts.firstWhere(
      (p) => p.id == widget.post.id,
      orElse: () => widget.post,
    );
    final comments = post.comments;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: AppDimensions.spaceMd),
            decoration: BoxDecoration(
              color: AppColors.deepBlue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const HudLabel(text: 'COMMENTS'),
          const Divider(color: AppColors.deepBlue, height: AppDimensions.spaceXl),
          Expanded(
            child: comments.isEmpty
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
                        const Divider(color: AppColors.deepBlue, height: 1),
                    itemBuilder: (context, i) {
                      final c = comments[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppDimensions.spaceMd,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            UserAvatar(name: c.author, size: 32),
                            const SizedBox(width: AppDimensions.spaceMd),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(c.author, style: AppTextStyles.label),
                                      const SizedBox(width: AppDimensions.spaceSm),
                                      Text(
                                        relativeTime(c.createdAt),
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
            decoration: const BoxDecoration(
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
    );
  }
}
