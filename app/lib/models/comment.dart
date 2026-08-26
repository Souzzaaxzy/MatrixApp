import 'name_effect.dart';

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
    this.authorNicknameEffect,
    required this.text,
    required this.createdAt,
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
        authorNicknameEffect = null,
        text = '',
        createdAt = null;

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

  /// The comment AUTHOR's own nickname effect (null → "Nenhum").
  final NameEffect? authorNicknameEffect;

  final String text;
  final DateTime? createdAt;
}
