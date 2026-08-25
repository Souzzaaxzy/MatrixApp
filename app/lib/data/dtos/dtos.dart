import '../../models/comment.dart';
import '../../models/friend_request.dart';
import '../../models/matrix_notification.dart';
import '../../models/matrix_user.dart';
import '../../models/post.dart';

/// Mappers that convert backend JSON responses into the app's domain models.
///
/// Keeping these in one place means the UI never touches raw maps and the
/// API response shape can evolve without rippling through every screen.

class AuthDto {
  final String accessToken;
  final String refreshToken;
  final AuthUserDto user;
  final String? recoveryCode;

  const AuthDto({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    this.recoveryCode,
  });

  factory AuthDto.fromJson(Map<String, dynamic> json) => AuthDto(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        user: AuthUserDto.fromJson(json['user'] as Map<String, dynamic>),
        recoveryCode: json['recoveryCode'] as String?,
      );
}

class AuthUserDto {
  final String id;
  final String name;
  final String username;
  final String? avatarUrl;
  final String bio;

  const AuthUserDto({
    required this.id,
    required this.name,
    required this.username,
    this.avatarUrl,
    required this.bio,
  });

  MatrixUser toModel() => MatrixUser(
        id: id,
        name: name,
        username: username,
        bio: bio,
        avatarUrl: avatarUrl,
      );

  factory AuthUserDto.fromJson(Map<String, dynamic> json) => AuthUserDto(
        id: json['id'] as String,
        name: json['name'] as String,
        username: json['username'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        bio: (json['bio'] as String?) ?? '',
      );
}

class FeedPostDto {
  final String id;
  final String text;
  final String? imageUrl;
  final DateTime createdAt;
  final String authorId;
  final String authorName;
  final String authorUsername;
  final String? authorAvatarUrl;
  final int likeCount;
  final bool liked;
  final int commentCount;

  const FeedPostDto({
    required this.id,
    required this.text,
    this.imageUrl,
    required this.createdAt,
    required this.authorId,
    required this.authorName,
    required this.authorUsername,
    this.authorAvatarUrl,
    required this.likeCount,
    required this.liked,
    required this.commentCount,
  });

  Post toModel() => Post(
        id: id,
        authorId: authorId,
        authorName: authorName,
        authorUsername: authorUsername,
        text: text,
        createdAt: createdAt,
        avatarSeed: authorUsername,
        authorAvatarUrl: authorAvatarUrl,
        imageUrl: imageUrl,
        likes: likeCount,
        liked: liked,
        commentCount: commentCount,
      );

  factory FeedPostDto.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>;
    return FeedPostDto(
      id: json['id'] as String,
      text: (json['text'] as String?) ?? '',
      imageUrl: json['imageUrl'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      authorId: (author['id'] as String?) ?? '',
      authorName: author['name'] as String,
      authorUsername: author['username'] as String,
      authorAvatarUrl: author['avatarUrl'] as String?,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      liked: (json['liked'] as bool?) ?? false,
      commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class CommentDto {
  final String id;
  final String text;
  final DateTime createdAt;
  final String authorId;
  final String authorName;
  final String authorUsername;
  final String? authorAvatarUrl;

  const CommentDto({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.authorId,
    required this.authorName,
    required this.authorUsername,
    this.authorAvatarUrl,
  });

  Comment toModel() => Comment(
        id: id,
        authorId: authorId,
        author: authorName,
        authorUsername: authorUsername,
        authorAvatarUrl: authorAvatarUrl,
        text: text,
        createdAt: createdAt,
      );

  factory CommentDto.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>;
    return CommentDto(
      id: json['id'] as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      authorId: author['id'] as String,
      authorName: author['name'] as String,
      authorUsername: author['username'] as String,
      authorAvatarUrl: author['avatarUrl'] as String?,
    );
  }
}

class PublicUserDto {
  final String id;
  final String name;
  final String username;
  final String? avatarUrl;
  final String bio;

  const PublicUserDto({
    required this.id,
    required this.name,
    required this.username,
    this.avatarUrl,
    required this.bio,
  });

  MatrixUser toModel() => MatrixUser(
        id: id,
        name: name,
        username: username,
        bio: bio,
        avatarUrl: avatarUrl,
      );

  factory PublicUserDto.fromJson(Map<String, dynamic> json) => PublicUserDto(
        id: json['id'] as String,
        name: json['name'] as String,
        username: json['username'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        bio: (json['bio'] as String?) ?? '',
      );
}

/// A pending friend request (sender embedded).
class FriendRequestDto {
  final String id;
  final String status;
  final DateTime createdAt;
  final PublicUserDto sender;

  const FriendRequestDto({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.sender,
  });

  FriendRequest toModel() => FriendRequest(
        id: id,
        status: status,
        createdAt: createdAt,
        sender: sender.toModel(),
      );

  factory FriendRequestDto.fromJson(Map<String, dynamic> json) {
    final senderJson = json['sender'] as Map<String, dynamic>;
    return FriendRequestDto(
      id: json['id'] as String,
      status: (json['status'] as String?) ?? 'PENDING',
      createdAt: DateTime.parse(json['createdAt'] as String),
      sender: PublicUserDto.fromJson(senderJson),
    );
  }
}

/// A notification (actor embedded; references post/comment/request).
class NotificationDto {
  final String id;
  final String type;
  final bool read;
  final DateTime createdAt;
  final PublicUserDto actor;
  final String? postId;
  final String? commentId;
  final String? friendRequestId;
  final String? friendRequestStatus;

  const NotificationDto({
    required this.id,
    required this.type,
    required this.read,
    required this.createdAt,
    required this.actor,
    this.postId,
    this.commentId,
    this.friendRequestId,
    this.friendRequestStatus,
  });

  MatrixNotification toModel() => MatrixNotification(
        id: id,
        type: type,
        read: read,
        createdAt: createdAt,
        actorId: actor.id,
        actorName: actor.name,
        actorUsername: actor.username,
        actorAvatarUrl: actor.avatarUrl,
        postId: postId,
        commentId: commentId,
        friendRequestId: friendRequestId,
        friendRequestStatus: friendRequestStatus,
      );

  factory NotificationDto.fromJson(Map<String, dynamic> json) {
    final actorJson = json['actor'] as Map<String, dynamic>;
    return NotificationDto(
      id: json['id'] as String,
      type: json['type'] as String,
      read: (json['read'] as bool?) ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      actor: PublicUserDto.fromJson(actorJson),
      postId: json['postId'] as String?,
      commentId: json['commentId'] as String?,
      friendRequestId: json['friendRequestId'] as String?,
      friendRequestStatus: json['friendRequestStatus'] as String?,
    );
  }
}
