import 'comment.dart';
import 'name_effect.dart';

/// A post in the MATRIX feed.
class Post {
  Post({
    required this.id,
    required this.authorNickname,
    required this.text,
    required this.createdAt,
    this.authorId,
    this.avatarSeed,
    this.authorAvatarUrl,
    this.authorNicknameColor,
    this.authorNicknameEffect,
    this.imageUrl,
    this.likes = 0,
    this.liked = false,
    this.commentCount = 0,
    this.comments = const [],
  });

  /// Unique server-side id. ALL operations (like, comment, detail, delete)
  /// key off this — never off the position in a list.
  final String id;

  /// The author's nickname — the single visual identity, rendered as plain
  /// text (never '@').
  final String authorNickname;

  /// Server-side id of the author (stable; nickname is mutable).
  final String? authorId;
  final String text;
  final DateTime createdAt;
  final String? avatarSeed;

  /// Remote URL of the author's profile photo (null → initials fallback).
  final String? authorAvatarUrl;

  /// The AUTHOR's own nickname color (hex), embedded by the server. Null →
  /// default color. Never the viewer's color.
  final String? authorNicknameColor;

  /// The AUTHOR's own nickname effect (server catalog entry with its render
  /// config). Null → "Nenhum" (plain colored nickname). Fully independent
  /// from [authorNicknameColor].
  final NameEffect? authorNicknameEffect;
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
        authorNickname: authorNickname,
        authorId: authorId,
        text: text ?? this.text,
        createdAt: createdAt,
        avatarSeed: avatarSeed,
        authorAvatarUrl: authorAvatarUrl,
        authorNicknameColor: authorNicknameColor,
        authorNicknameEffect: authorNicknameEffect,
        imageUrl: imageUrl ?? this.imageUrl,
        likes: likes ?? this.likes,
        liked: liked ?? this.liked,
        commentCount: commentCount ?? this.commentCount,
        comments: comments ?? this.comments,
      );
}
