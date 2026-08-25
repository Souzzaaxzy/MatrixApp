/// Comment model — real comments come from the server with the author's
/// identity (id, username, avatar). Placeholders exist only for legacy
/// count-only contexts.
class Comment {
  const Comment({
    required this.id,
    required this.authorId,
    required this.author,
    required this.authorUsername,
    this.authorAvatarUrl,
    required this.text,
    required this.createdAt,
  });

  /// Placeholder used when only the comment *count* is known (e.g. in feed
  /// summaries). The real list is fetched lazily when the comments sheet
  /// opens.
  const Comment.placeholder()
      : id = '',
        authorId = '',
        author = '',
        authorUsername = '',
        authorAvatarUrl = null,
        text = '',
        createdAt = null;

  final String id;

  /// Unique user id of the comment author — used to detect when the
  /// commenter is also the post author (the "Autor" badge). Never compare
  /// usernames: they are mutable.
  final String authorId;

  /// Display name of the author.
  final String author;

  /// Public handle of the account (@username) — what the UI shows.
  final String authorUsername;

  /// Profile photo URL (absolute or server-relative /static path), same
  /// avatar used everywhere else in the app. Null → default avatar.
  final String? authorAvatarUrl;

  final String text;
  final DateTime? createdAt;
}
