import 'comment.dart';

/// A post in the MATRIX feed.
class Post {
  Post({
    required this.id,
    required this.authorName,
    required this.authorUsername,
    required this.text,
    required this.createdAt,
    this.avatarSeed,
    this.imageUrl,
    this.likes = 0,
    this.liked = false,
    this.comments = const [],
  });

  final String id;
  final String authorName;
  final String authorUsername;
  final String text;
  final DateTime createdAt;
  final String? avatarSeed;
  final String? imageUrl;

  int likes;
  bool liked;
  List<Comment> comments;

  Post copyWith({
    String? text,
    String? imageUrl,
    int? likes,
    bool? liked,
    List<Comment>? comments,
  }) =>
      Post(
        id: id,
        authorName: authorName,
        authorUsername: authorUsername,
        text: text ?? this.text,
        createdAt: createdAt,
        avatarSeed: avatarSeed,
        imageUrl: imageUrl ?? this.imageUrl,
        likes: likes ?? this.likes,
        liked: liked ?? this.liked,
        comments: comments ?? this.comments,
      );
}
