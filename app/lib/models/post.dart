import 'comment.dart';

/// A post in the MATRIX feed.
class Post {
  Post({
    required this.id,
    required this.authorName,
    required this.authorUsername,
    required this.text,
    required this.createdAt,
    this.authorId,
    this.avatarSeed,
    this.authorAvatarUrl,
    this.imageUrl,
    this.likes = 0,
    this.liked = false,
    this.commentCount = 0,
    this.comments = const [],
  });

  /// Unique server-side id. ALL operations (like, comment, detail, delete)
  /// key off this — never off the position in a list.
  final String id;
  final String authorName;
  final String authorUsername;

  /// Server-side id of the author (stable; username is mutable).
  final String? authorId;
  final String text;
  final DateTime createdAt;
  final String? avatarSeed;

  /// Remote URL of the author's profile photo (null → initials fallback).
  final String? authorAvatarUrl;
  final String? imageUrl;

  int likes;
  bool liked;

  /// Server-reported comment count (the full comment list is loaded on
  /// demand by the comments sheet).
  int commentCount;
  List<Comment> comments;

  Post copyWith({
    String? text,
    String? imageUrl,
    int? likes,
    bool? liked,
    int? commentCount,
    List<Comment>? comments,
  }) =>
      Post(
        id: id,
        authorName: authorName,
        authorUsername: authorUsername,
        authorId: authorId,
        text: text ?? this.text,
        createdAt: createdAt,
        avatarSeed: avatarSeed,
        authorAvatarUrl: authorAvatarUrl,
        imageUrl: imageUrl ?? this.imageUrl,
        likes: likes ?? this.likes,
        liked: liked ?? this.liked,
        commentCount: commentCount ?? this.commentCount,
        comments: comments ?? this.comments,
      );
}
