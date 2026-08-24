import 'dart:io';

import 'package:dio/dio.dart';

import '../../models/comment.dart';
import '../../models/matrix_user.dart';
import '../../models/post.dart';
import '../api_client.dart';
import '../dtos/dtos.dart';

/// Authentication repository — register, login, current user, logout,
/// and account recovery. Username-only (no email/phone).
class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  /// Registers a new account. The backend returns a recovery code that
  /// must be shown to the user once — it is never sent again.
  Future<AuthDto> register({
    required String name,
    required String username,
    required String password,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/api/auth/register',
      data: {
        'name': name,
        'username': username,
        'password': password,
      },
    );
    final dto = AuthDto.fromJson(json);
    await _api.tokenStore.save(
      accessToken: dto.accessToken,
      refreshToken: dto.refreshToken,
    );
    return dto;
  }

  Future<AuthDto> login({
    required String username,
    required String password,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/api/auth/login',
      data: {'username': username, 'password': password},
    );
    final dto = AuthDto.fromJson(json);
    await _api.tokenStore.save(
      accessToken: dto.accessToken,
      refreshToken: dto.refreshToken,
    );
    return dto;
  }

  /// Recovers an account using the recovery code + a new password.
  /// Does not return tokens — the user must log in afterwards.
  Future<void> recover({
    required String identifier,
    required String recoveryCode,
    required String newPassword,
  }) async {
    await _api.post(
      '/api/auth/recover',
      data: {
        'identifier': identifier,
        'recoveryCode': recoveryCode,
        'newPassword': newPassword,
      },
    );
  }

  Future<AuthUserDto> me() async {
    final json = await _api.get<Map<String, dynamic>>('/api/auth/me');
    return AuthUserDto.fromJson((json['user'] as Map<String, dynamic>));
  }

  Future<void> logout() async {
    final refresh = await _api.tokenStore.refreshToken;
    try {
      await _api.post('/api/auth/logout', data: {'refreshToken': refresh});
    } finally {
      await _api.tokenStore.clear();
    }
  }
}

/// Posts repository — feed (cursor pagination), create, delete.
class PostRepository {
  PostRepository(this._api);

  final ApiClient _api;

  /// Fetches one page of the feed. Returns the posts and the next cursor
  /// (null when there are no more pages).
  Future<({List<Post> posts, String? nextCursor})> feed({
    String? cursor,
    int limit = 15,
  }) async {
    final query = <String, dynamic>{'limit': limit};
    if (cursor != null) query['cursor'] = cursor;
    final json = await _api.get<Map<String, dynamic>>('/api/posts', queryParameters: query);
    final list = (json['posts'] as List).cast<Map<String, dynamic>>();
    final posts = list.map(FeedPostDto.fromJson).map((d) => d.toModel()).toList();
    final next = json['nextCursor'] as String?;
    return (posts: posts, nextCursor: next);
  }

  /// Fetches a single post by its server id (post detail screen).
  Future<Post> getById(String id) async {
    final json = await _api.get<Map<String, dynamic>>('/api/posts/$id');
    return FeedPostDto.fromJson(json).toModel();
  }

  Future<Post> create({required String text, String? imageUrl}) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/api/posts',
      data: {'text': text, if (imageUrl != null) 'imageUrl': imageUrl},
    );
    return FeedPostDto.fromJson(json).toModel();
  }

  Future<void> delete(String id) async {
    await _api.delete('/api/posts/$id');
  }
}

/// Likes repository — toggle like/unlike.
class LikeRepository {
  LikeRepository(this._api);

  final ApiClient _api;

  /// Toggles the like on a post. Returns the new state and count.
  Future<({bool liked, int likeCount})> toggle(String postId) async {
    final json = await _api.post<Map<String, dynamic>>('/api/posts/$postId/like');
    return (
      liked: json['liked'] as bool,
      likeCount: (json['likeCount'] as num).toInt(),
    );
  }
}

/// Comments repository — list, create, delete.
class CommentRepository {
  CommentRepository(this._api);

  final ApiClient _api;

  Future<List<Comment>> list(String postId) async {
    final json = await _api.get<Map<String, dynamic>>('/api/posts/$postId/comments');
    final list = (json['comments'] as List).cast<Map<String, dynamic>>();
    return list.map(CommentDto.fromJson).map((d) => d.toModel()).toList();
  }

  Future<Comment> create({required String postId, required String text}) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/api/posts/$postId/comments',
      data: {'text': text},
    );
    return CommentDto.fromJson(json).toModel();
  }

  Future<void> delete(String commentId) async {
    await _api.delete('/api/comments/$commentId');
  }
}

/// Users repository — public profile, update own profile, search.
class UserRepository {
  UserRepository(this._api);

  final ApiClient _api;

  /// Fetches a public profile by username, including that user's posts.
  Future<({MatrixUser user, List<Post> posts})> profile(String username) async {
    final json = await _api.get<Map<String, dynamic>>('/api/users/$username');
    final user = PublicUserDto.fromJson(json['user'] as Map<String, dynamic>).toModel();
    final list = (json['posts'] as List).cast<Map<String, dynamic>>();
    final posts = list.map(FeedPostDto.fromJson).map((d) => d.toModel()).toList();
    return (user: user, posts: posts);
  }

  Future<MatrixUser> updateProfile({
    String? name,
    String? username,
    String? bio,
    String? avatarUrl,
  }) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/api/users/me',
      data: {
        if (name != null) 'name': name,
        if (username != null) 'username': username,
        if (bio != null) 'bio': bio,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
      },
    );
    return AuthUserDto.fromJson(json['user'] as Map<String, dynamic>).toModel();
  }

  Future<List<MatrixUser>> search(String query) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/api/users/search',
      queryParameters: {'q': query},
    );
    final list = (json['users'] as List).cast<Map<String, dynamic>>();
    return list.map(PublicUserDto.fromJson).map((d) => d.toModel()).toList();
  }
}

/// Uploads repository — image upload via multipart.
class UploadRepository {
  UploadRepository(this._api);

  final ApiClient _api;

  /// Uploads an image file and returns the public URL.
  Future<String> upload(File file) async {
    final multipart = await MultipartFile.fromFile(file.path);
    final json = await _api.upload<Map<String, dynamic>>(
      '/api/uploads',
      file: multipart,
    );
    return json['url'] as String;
  }
}

/// Bundles all repositories so they can be injected as a unit (e.g. into
/// [AppState] for tests, or constructed once in [Services] for production).
class Repositories {
  const Repositories({
    required this.auth,
    required this.posts,
    required this.likes,
    required this.comments,
    required this.users,
    required this.uploads,
  });

  final AuthRepository auth;
  final PostRepository posts;
  final LikeRepository likes;
  final CommentRepository comments;
  final UserRepository users;
  final UploadRepository uploads;
}
