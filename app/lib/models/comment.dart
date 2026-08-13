/// A comment on a post.
class Comment {
  const Comment({
    required this.id,
    required this.author,
    required this.text,
    required this.createdAt,
  });

  /// Placeholder used when only the comment *count* is known (e.g. in feed
  /// summaries). The real list is fetched lazily when the comments sheet
  /// opens.
  const Comment.placeholder()
      : id = '',
        author = '',
        text = '',
        createdAt = null;

  final String id;
  final String author;
  final String text;
  final DateTime? createdAt;
}
