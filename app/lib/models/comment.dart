/// Comment model — real comments come from the server with the author's
/// identity (id, nickname, avatar). Placeholders exist only for legacy
/// count-only contexts.
class Comment {
  const Comment({
    required this.id,
    required this.authorId,
    required this.authorNickname,
    this.authorAvatarUrl,
    this.authorNicknameColor,
    this.authorFrameId,
    this.authorFrameAsset,
    required this.text,
    required this.createdAt,
    this.parentCommentId,
    this.likeCount = 0,
    this.liked = false,
  });

  /// Placeholder used when only the comment *count* is known (e.g. in feed
  /// summaries). The real list is fetched lazily when the comments sheet
  /// opens.
  const Comment.placeholder()
      : id = '',
        authorId = '',
        authorNickname = '',
        authorAvatarUrl = null,
        authorNicknameColor = null,
        authorFrameId = null,
        authorFrameAsset = null,
        text = '',
        createdAt = null,
        parentCommentId = null,
        likeCount = 0,
        liked = false;

  final String id;

  /// Unique user id of the comment author — used to detect when the
  /// commenter is also the post author (the "Autor" badge). Never compare
  /// nicknames: they are mutable.
  final String authorId;

  /// The author's nickname — rendered as plain text (never '@').
  final String authorNickname;

  /// Profile photo URL (absolute or server-relative /static path), same
  /// avatar used everywhere else in the app. Null → default avatar.
  final String? authorAvatarUrl;

  /// The comment AUTHOR's own nickname color (hex), embedded by the
  /// server. Null → default color.
  final String? authorNicknameColor;

  /// The comment AUTHOR's own equipped profile frame (assets key), embedded
  /// by the server. Null → default. Never the viewer's frame.
  final String? authorFrameId;
  final String? authorFrameAsset;

  final String text;
  final DateTime? createdAt;

  /// Null for top-level comments; equals the parent comment id for replies.
  final String? parentCommentId;

  /// Total number of likes (from the server, the source of truth).
  final int likeCount;

  /// Whether the CURRENT session user already liked this comment.
  final bool liked;

  Comment copyWith({
    String? text,
    int? likeCount,
    bool? liked,
  }) {
    return Comment(
      id: id,
      authorId: authorId,
      authorNickname: authorNickname,
      authorAvatarUrl: authorAvatarUrl,
      authorNicknameColor: authorNicknameColor,
      authorFrameId: authorFrameId,
      authorFrameAsset: authorFrameAsset,
      text: text ?? this.text,
      createdAt: createdAt,
      parentCommentId: parentCommentId,
      likeCount: likeCount ?? this.likeCount,
      liked: liked ?? this.liked,
    );
  }
}
