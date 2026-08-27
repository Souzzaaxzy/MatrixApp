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

/// Number of replies rendered under a comment before the collapsible
/// "mais comentários..." affordance appears. Purely a visual limit.
const int _maxVisibleReplies = 5;

/// Bottom sheet showing comments for a post, with per-comment likes and
/// nested replies (limited to [_maxVisibleReplies] visible by default).
class CommentsSheet extends StatefulWidget {
  const CommentsSheet({super.key, required this.post});

  final Post post;

  static Future<void> show(BuildContext context, {required Post post}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Fully opaque: nothing behind the comments leaks through.
      backgroundColor: AppColors.bluishBlack,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimensions.radiusXl),
        ),
      ),
      isDismissible: true,
      enableDrag: true,
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

class _CommentsSheetState extends State<CommentsSheet>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  List<Comment>? _comments;
  bool _loading = true;
  String? _error;

  /// Comment id the user is currently replying to (null → top-level).
  String? _replyingTo;

  /// Cached replies per top-level comment id. Loaded lazily and reused so
  /// toggling a reply like doesn't re-fetch the whole tree.
  final Map<String, List<Comment>> _replies = {};

  /// Top-level comment ids whose replies failed to load.
  final Map<String, bool> _repliesError = {};

  /// Top-level comment ids whose replies were expanded past the 5-reply cap.
  final Set<String> _expandedReplies = {};

  late final AnimationController _popController;
  final FocusNode _inputFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      lowerBound: 1.0,
      upperBound: 1.3,
    );
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
    _popController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  /// Toggles a like optimistically and reconciles with the server result.
  Future<void> _toggleLike(Comment c) async {
    // Only animate outward on like.
    if (!c.liked) {
      _popController.forward(from: 1.0).then((_) => _popController.reverse());
    }
    final next = c.copyWith(liked: !c.liked, likeCount: c.likeCount + (c.liked ? -1 : 1));
    _replaceComment(next);
    final result = await AppStateScope.of(context)
        .toggleCommentLike(c.id, liked: !c.liked);
    if (!mounted) return;
    if (result == null) {
      // Server failed: revert to the last known good state.
      _replaceComment(c);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível atualizar a curtida.'),
        ),
      );
      return;
    }
    _replaceComment(
      c.copyWith(liked: result.liked, likeCount: result.likeCount),
    );
  }

  /// Toggles a like on a reply (independent from the parent comment).
  Future<void> _toggleReplyLike(String parentId, Comment reply) async {
    if (!reply.liked) {
      _popController.forward(from: 1.0).then((_) => _popController.reverse());
    }
    final next = reply.copyWith(
      liked: !reply.liked,
      likeCount: reply.likeCount + (reply.liked ? -1 : 1),
    );
    _replaceReply(parentId, next);
    final result = await AppStateScope.of(context)
        .toggleCommentLike(reply.id, liked: !reply.liked);
    if (!mounted) return;
    if (result == null) {
      _replaceReply(parentId, reply);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível atualizar a curtida.'),
        ),
      );
      return;
    }
    _replaceReply(
      parentId,
      reply.copyWith(liked: result.liked, likeCount: result.likeCount),
    );
  }

  void _replaceReply(String parentId, Comment updated) {
    final list = _replies[parentId];
    if (list == null) return;
    final idx = list.indexWhere((r) => r.id == updated.id);
    if (idx < 0) return;
    setState(() {
      list[idx] = updated;
    });
  }

  /// Swaps a top-level comment in the local list in place, leaving everything
  /// else untouched so a single like doesn't rebuild the whole sheet.
  void _replaceComment(Comment updated) {
    final current = _comments;
    if (current == null) return;
    final idx = current.indexWhere((c) => c.id == updated.id);
    if (idx < 0) return;
    setState(() {
      current[idx] = updated;
    });
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    final replyTo = _replyingTo;
    _controller.clear();
    _replyingTo = null;
    FocusScope.of(context).unfocus();
    try {
      if (replyTo == null) {
        final comment = await AppStateScope.of(context)
            .addComment(widget.post.id, text);
        setState(() {
          _comments = [...?_comments, comment];
        });
      } else {
        final reply = await AppStateScope.of(context).addReply(
          parentCommentId: replyTo,
          postId: widget.post.id,
          text: text,
        );
        setState(() {
          _repliesOf(replyTo).add(reply);
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao enviar comentário.')),
      );
    }
  }

  void _startReply(Comment c) {
    _replyingTo = c.id;
    setState(() {});
    FocusScope.of(context).requestFocus(_inputFocusNode);
  }

  void _cancelReply() {
    _replyingTo = null;
    setState(() {});
  }

  List<Comment> _repliesOf(String parentId) {
    return _replies.putIfAbsent(parentId, () => <Comment>[]);
  }

  Future<void> _loadReplies(Comment c) async {
    if (_replies.containsKey(c.id)) {
      setState(() {});
      return;
    }
    setState(() {}); // show a lightweight loading hint under the comment
    try {
      final replies = await AppStateScope.of(context).loadReplies(c.id);
      if (!mounted) return;
      setState(() {
        _replies[c.id] = replies;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _repliesError[c.id] = true;
      });
    }
  }

  /// Nickname shown in the "Respondendo a …" hint while replying.
  String get _replyTargetNickname {
    if (_replyingTo == null) return '';
    for (final c in _comments ?? <Comment>[]) {
      if (c.id == _replyingTo) return c.authorNickname;
    }
    final lists = _replies.values.expand((r) => r);
    for (final r in lists) {
      if (r.id == _replyingTo) return r.authorNickname;
    }
    return '';
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
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimensions.spaceLg,
                          vertical: AppDimensions.spaceSm,
                        ),
                        itemCount: comments.length,
                        itemBuilder: (context, i) {
                          final c = comments[i];
                          return _CommentTile(
                            key: ValueKey(c.id),
                            comment: c,
                            isAuthor: c.authorId.isNotEmpty &&
                                c.authorId == widget.post.authorId,
                            replies: _replies[c.id],
                            repliesError: _repliesError[c.id] == true,
                            expanded: _expandedReplies.contains(c.id),
                            popController: _popController,
                            onLike: () => _toggleLike(c),
                            onReply: () => _startReply(c),
                            onToggleExpand: () => setState(() {
                              if (_expandedReplies.contains(c.id)) {
                                _expandedReplies.remove(c.id);
                              } else {
                                _expandedReplies.add(c.id);
                              }
                            }),
                            onLoadReplies: () => _loadReplies(c),
                            onReplyLike: (reply) =>
                                _toggleReplyLike(c.id, reply),
                            onReplyReply: (reply) => _startReply(c),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_replyingTo != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Respondendo a $_replyTargetNickname...',
                            style: AppTextStyles.hud.copyWith(
                              fontSize: 11,
                              color: AppColors.electricBlue,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: _cancelReply,
                          behavior: HitTestBehavior.opaque,
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: AppColors.holographicBlue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.spaceXs),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _inputFocusNode,
                          style: AppTextStyles.body,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: _replyingTo != null
                                ? 'Digite sua resposta...'
                                : 'Escreva um comentário...',
                            hintStyle: AppTextStyles.bodyMuted,
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      ScaleTransition(
                        scale: _popController,
                        child: IconButton(
                          icon: const Icon(Icons.send_rounded,
                              color: AppColors.electricBlue),
                          onPressed: _send,
                        ),
                      ),
                    ],
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

/// One top-level comment plus its (lazily loaded) nested replies.
///
/// The heart sits on the right of the comment body, matching the app-wide
/// like interaction. Replies are indented under their parent and capped at
/// [_maxVisibleReplies] until the user taps "mais comentários...".
class _CommentTile extends StatelessWidget {
  const _CommentTile({
    super.key,
    required this.comment,
    required this.isAuthor,
    required this.replies,
    required this.repliesError,
    required this.expanded,
    required this.popController,
    required this.onLike,
    required this.onReply,
    required this.onToggleExpand,
    required this.onLoadReplies,
    required this.onReplyLike,
    required this.onReplyReply,
  });

  final Comment comment;
  final bool isAuthor;
  final List<Comment>? replies;
  final bool repliesError;
  final bool expanded;
  final Animation<double> popController;
  final VoidCallback onLike;
  final VoidCallback onReply;
  final VoidCallback onToggleExpand;
  final VoidCallback onLoadReplies;
  final void Function(Comment reply) onReplyLike;
  final void Function(Comment reply) onReplyReply;

  @override
  Widget build(BuildContext context) {
    final replyCount = replies?.length ?? 0;
    final hasReplies = replyCount > 0;
    final visibleReplies =
        expanded ? replyCount : (replyCount > _maxVisibleReplies ? _maxVisibleReplies : replyCount);
    final hiddenCount = replyCount - _maxVisibleReplies;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CommentRow(
          comment: comment,
          isAuthor: isAuthor,
          popController: popController,
          onLike: onLike,
          onReply: onReply,
        ),
        // Lazy "responses" toggle — loads the reply tree on first tap.
        if (replies == null)
          Padding(
            padding: const EdgeInsets.only(left: 44, top: 4),
            child: repliesError
                ? GestureDetector(
                    onTap: onLoadReplies,
                    child: Text('Erro — toque para tentar novamente.',
                        style: _miniLinkStyle(context)),
                  )
                : GestureDetector(
                    onTap: onLoadReplies,
                    child: Text('Ver respostas', style: _miniLinkStyle(context)),
                  ),
          ),
        if (hasReplies)
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                ...(replies ?? <Comment>[])
                    .take(visibleReplies)
                    .map<Widget>((r) => _CommentRow(
                          comment: r,
                          isAuthor: isAuthor,
                          asReply: true,
                          popController: popController,
                          onLike: () => onReplyLike(r),
                          onReply: () => onReplyReply(r),
                        )),
                if (!expanded && hiddenCount > 0)
                  GestureDetector(
                    onTap: onToggleExpand,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: double.infinity,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 44 + AppDimensions.spaceMd, top: 6),
                      child: Text(
                        'mais comentários...',
                        style: _miniLinkStyle(context),
                      ),
                    ),
                  )
                else if (expanded && hiddenCount > 0)
                  GestureDetector(
                    onTap: onToggleExpand,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: double.infinity,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 44 + AppDimensions.spaceMd, top: 6),
                      child: Text(
                        'recolher resposta',
                        style: _miniLinkStyle(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Divider(color: AppColors.deepBlue, height: AppDimensions.spaceLg)
      ],
    );
  }

  TextStyle _miniLinkStyle(BuildContext context) {
    return AppTextStyles.bodyMuted.copyWith(
      fontSize: 12,
      color: AppColors.electricBlue,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.electricBlue.withValues(alpha: 0.5),
    );
  }
}

/// A single comment (top-level or a reply) row: avatar, nickname + time,
/// text, and a heart aligned on the RIGHT of the body.
class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    required this.isAuthor,
    this.asReply = false,
    required this.popController,
    required this.onLike,
    required this.onReply,
  });

  final Comment comment;
  final bool isAuthor;
  final bool asReply;
  final Animation<double> popController;
  final VoidCallback onLike;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: asReply ? 40 : 0,
        top: AppDimensions.spaceMd,
        right: 0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => openProfileById(
              context,
              id: comment.authorId,
              nickname: comment.authorNickname,
            ),
            behavior: HitTestBehavior.opaque,
            child: FramedAvatar(
              frame: comment.authorFrameId == null
                  ? null
                  : CosmeticItem(
                      id: comment.authorFrameId!,
                      slot: CosmeticItem.avatarFrame,
                      name: comment.authorFrameId!,
                      assetUrl: comment.authorFrameAsset ?? '',
                    ),
              size: asReply ? 26 : 32,
              child: UserAvatar(
                name: comment.authorNickname,
                imageUrl: comment.authorAvatarUrl,
                size: asReply ? 22 : 27,
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
                          id: comment.authorId,
                          nickname: comment.authorNickname,
                        ),
                        behavior: HitTestBehavior.opaque,
                        child: NicknameRenderer(
                          comment.authorNickname,
                          baseStyle: AppTextStyles.label,
                          background: AppColors.nightBlue,
                          nameColor: comment.authorNicknameColor,
                        ),
                      ),
                    ),
                    if (comment.authorId.isNotEmpty && isAuthor) ...[
                      const SizedBox(width: AppDimensions.spaceXs),
                      const _AuthorBadge(),
                    ],
                    const SizedBox(width: AppDimensions.spaceSm),
                    Text(
                      relativeTimeString(comment.createdAt),
                      style: AppTextStyles.hud.copyWith(fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: AppDimensions.spaceXs),
                Text(comment.text, style: AppTextStyles.body),
                // Actions row: Responder on the left, heart on the right.
                const SizedBox(height: AppDimensions.spaceXs),
                Row(
                  children: [
                    // Reply affordance. Tapping a reply row's "Responder"
                    // replies to that reply's parent comment in the UI.
                    GestureDetector(
                      onTap: onReply,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'Responder',
                          style: AppTextStyles.hud.copyWith(
                            fontSize: 10,
                            color: AppColors.holographicBlue,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    ScaleTransition(
                      scale: popController,
                      child: GestureDetector(
                        onTap: onLike,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (comment.likeCount > 0)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Text(
                                    comment.likeCount.toString(),
                                    style: AppTextStyles.hud.copyWith(
                                      fontSize: 11,
                                      color: comment.liked
                                          ? AppColors.error
                                          : AppColors.holographicBlue,
                                    ),
                                  ),
                                ),
                              Icon(
                                comment.liked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 18,
                                color: comment.liked
                                    ? AppColors.error
                                    : AppColors.holographicBlue,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
