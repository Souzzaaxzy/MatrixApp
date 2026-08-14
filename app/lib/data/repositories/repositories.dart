import 'dart:io';

import 'package:dio/dio.dart';

import '../../models/comment.dart';
import '../../models/matrix_user.dart';
import '../../models/post.dart';
import '../api_client.dart';
import '../dtos/dtos.dart';

/// Authentication repository — register, login, current user, logout.
class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  Future<AuthDto> register({
    required String name,
    required String username,
    required String email,
    required String password,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/auth/register',
      data: {
        'name': name,
        'username': username,
        'email': email,
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
    required String identifier,
    required String password,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'identifier': identifier, 'password': password},
    );
    final dto = AuthDto.fromJson(json);
    await _api.tokenStore.save(
      accessToken: dto.accessToken,
      refreshToken: dto.refreshToken,
    );
    return dto;
  }

  Future<AuthUserDto> me() async {
    final json = await _api.get<Map<String, dynamic>>('/auth/me');
    return AuthUserDto.fromJson((json['user'] as Map<String, dynamic>));
  }

  Future<void> logout() async {
    final refresh = await _api.tokenStore.refreshToken;
    try {
      await _api.post('/auth/logout', data: {'refreshToken': refresh});
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
    final json = await _api.get<Map<String, dynamic>>('/posts', queryParameters: query);
    final list = (json['posts'] as List).cast<Map<String, dynamic>>();
    final posts = list.map(FeedPostDto.fromJson).map((d) => d.toModel()).toList();
    final next = json['nextCursor'] as String?;
    return (posts: posts, nextCursor: next);
  }

  Future<Post> create({required String text, String? imageUrl}) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/posts',
      data: {'text': text, if (imageUrl != null) 'imageUrl': imageUrl},
    );
    return FeedPostDto.fromJson(json).toModel();
  }

  Future<void> delete(String id) async {
    await _api.delete('/posts/$id');
  }
}

/// Likes repository — toggle like/unlike.
class LikeRepository {
  LikeRepository(this._api);

  final ApiClient _api;

  /// Toggles the like on a post. Returns the new state and count.
  Future<({bool liked, int likeCount})> toggle(String postId) async {
    final json = await _api.post<Map<String, dynamic>>('/posts/$postId/like');
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
    final json = await _api.get<Map<String, dynamic>>('/posts/$postId/comments');
    final list = (json['comments'] as List).cast<Map<String, dynamic>>();
    return list.map(CommentDto.fromJson).map((d) => d.toModel()).toList();
  }

  Future<Comment> create({required String postId, required String text}) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/posts/$postId/comments',
      data: {'text': text},
    );
    return CommentDto.fromJson(json).toModel();
  }

  Future<void> delete(String commentId) async {
    await _api.delete('/comments/$commentId');
  }
}

/// Users repository — public profile, update own profile, search.
class UserRepository {
  UserRepository(this._api);

  final ApiClient _api;

  /// Fetches a public profile by username, including that user's posts.
  Future<({MatrixUser user, List<Post> posts})> profile(String username) async {
    final json = await _api.get<Map<String, dynamic>>('/users/$username');
    final user = PublicUserDto.fromJson(json['user'] as Map<String, dynamic>).toModel();
    final list = (json['posts'] as List).cast<Map<String, dynamic>>();
    final posts = list.map(FeedPostDto.fromJson).map((d) => d.toModel()).toList();
    return (user: user, posts: posts);
  }

  Future<MatrixUser> updateProfile({String? name, String? bio}) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/users/me',
      data: {if (name != null) 'name': name, if (bio != null) 'bio': bio},
    );
    return AuthUserDto.fromJson(json['user'] as Map<String, dynamic>).toModel();
  }

  Future<List<MatrixUser>> search(String query) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/users/search',
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
      '/uploads',
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
