import 'dart:io';

import 'package:matrix_app/data/api_config.dart';
import 'package:matrix_app/data/dtos/dtos.dart';
import 'package:matrix_app/data/repositories/repositories.dart';
import 'package:matrix_app/models/comment.dart';
import 'package:matrix_app/models/matrix_user.dart';
import 'package:matrix_app/models/post.dart';

/// In-memory fake repositories for widget/unit tests.
///
/// Each fake `implements` the real repository interface, so [AppState]
/// exercises its real optimistic-update / caching logic against data that
/// lives in memory — no network, no platform storage. Data is seeded
/// deterministically so tests are reproducible.
class FakeRepositories extends Repositories {
  FakeRepositories._({
    required super.auth,
    required super.posts,
    required super.likes,
    required super.comments,
    required super.users,
    required super.uploads,
  });

  factory FakeRepositories({
    bool failLikes = false,
    Map<String, List<Comment>> seedComments = const {},
  }) {
    final store = _Store();
    seedComments.forEach((postId, comments) {
      store.commentsByPost[postId] = List.of(comments);
    });
    return FakeRepositories._(
      auth: _FakeAuthRepository(store),
      posts: _FakePostRepository(store),
      likes: _FakeLikeRepository(store, fail: failLikes),
      comments: _FakeCommentRepository(store),
      users: _FakeUserRepository(store),
      uploads: const _FakeUploadRepository(),
    );
  }
}

class _Store {
  _Store() {
    users = {
      'u0': MatrixUser(
        id: 'u0',
        name: 'Leonardo',
        username: 'leonardo',
        bio: 'Construindo o futuro. ⚡',
        avatarSeed: 'leonardo',
      ),
    };
    currentUserId = 'u0';
    posts = [
      Post(
        id: 'p1',
        authorId: 'u0',
        authorName: 'Leonardo',
        authorUsername: 'leonardo',
        text: 'Test post',
        createdAt: DateTime(2024, 1, 1),
        avatarSeed: 'leonardo',
        likes: 5,
        liked: false,
        comments: const [],
      ),
      // A post by ANOTHER user — lets tests verify the author-only affordances
      // (delete menu) are hidden for non-owners.
      Post(
        id: 'p2',
        authorId: 'u2',
        authorName: 'João',
        authorUsername: 'joao',
        text: 'Post de outro usuário',
        createdAt: DateTime(2024, 1, 2),
        avatarSeed: 'joao',
        likes: 2,
        liked: false,
        comments: const [],
      ),
    ];
    likedPostIds = <String>{};
    // Authoritative like counts, independent of AppState's optimistic writes.
    likeCountByPost = {'p1': 5};
    commentsByPost = <String, List<Comment>>{};
  }

  late final Map<String, MatrixUser> users;
  late String currentUserId;
  late List<Post> posts;
  late Set<String> likedPostIds;
  late Map<String, int> likeCountByPost;
  late Map<String, List<Comment>> commentsByPost;

  MatrixUser get currentUser => users[currentUserId]!;
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._store);

  final _Store _store;

  @override
  Future<AuthDto> register({
    required String name,
    required String username,
    required String password,
  }) async {
    final user = MatrixUser(
      id: 'u${_store.users.length}',
      name: name,
      username: username,
      bio: '',
    );
    _store.users[user.id] = user;
    _store.currentUserId = user.id;
    return AuthDto(
      accessToken: 'fake-access',
      refreshToken: 'fake-refresh',
      user: AuthUserDto(
        id: user.id,
        name: user.name,
        username: user.username,
        avatarUrl: user.avatarUrl,
        bio: user.bio,
      ),
      recoveryCode: '829147206153',
    );
  }

  @override
  Future<AuthDto> login({
    required String username,
    required String password,
  }) async {
    final u = _store.currentUser;
    return AuthDto(
      accessToken: 'fake-access',
      refreshToken: 'fake-refresh',
      user: AuthUserDto(
        id: u.id,
        name: u.name,
        username: u.username,
        avatarUrl: u.avatarUrl,
        bio: u.bio,
      ),
    );
  }

  @override
  Future<void> recover({
    required String identifier,
    required String recoveryCode,
    required String newPassword,
  }) async {}

  @override
  Future<AuthUserDto> me() async {
    final u = _store.currentUser;
    return AuthUserDto(
      id: u.id,
      name: u.name,
      username: u.username,
      avatarUrl: u.avatarUrl,
      bio: u.bio,
    );
  }

  @override
  Future<void> logout() async {}
}

class _FakePostRepository implements PostRepository {
  _FakePostRepository(this._store);

  final _Store _store;

  @override
  Future<({List<Post> posts, String? nextCursor})> feed({
    String? cursor,
    int limit = 15,
  }) async {
    return (posts: List.of(_store.posts), nextCursor: null);
  }

  @override
  Future<Post> getById(String id) async {
    return _store.posts.firstWhere((p) => p.id == id);
  }

  @override
  Future<Post> create({required String text, String? imageUrl}) async {
    final u = _store.currentUser;
    final post = Post(
      id: 'p${DateTime.now().millisecondsSinceEpoch}',
      authorId: u.id,
      authorName: u.name,
      authorUsername: u.username,
      text: text,
      createdAt: DateTime.now(),
      avatarSeed: u.avatarSeed,
      authorAvatarUrl: u.avatarUrl,
      imageUrl: imageUrl,
      likes: 0,
      liked: false,
      comments: const [],
    );
    _store.posts.insert(0, post);
    return post;
  }

  @override
  Future<void> delete(String id) async {
    _store.posts.removeWhere((p) => p.id == id);
  }
}

class _FakeLikeRepository implements LikeRepository {
  _FakeLikeRepository(this._store, {this.fail = false});

  final _Store _store;

  /// When true, every toggle throws — simulates an API failure so tests can
  /// verify the optimistic update is rolled back.
  final bool fail;

  @override
  Future<({bool liked, int likeCount})> toggle(String postId) async {
    if (fail) {
      throw const ApiException(
        statusCode: 500,
        message: 'Erro interno do servidor.',
      );
    }
    final post = _store.posts.firstWhere((p) => p.id == postId);
    final wasLiked = _store.likedPostIds.contains(postId);
    final nowLiked = !wasLiked;
    if (nowLiked) {
      _store.likedPostIds.add(postId);
    } else {
      _store.likedPostIds.remove(postId);
    }
    // Compute from the authoritative store count, not the optimistically
    // mutated post.likes AppState may have already written.
    final base = _store.likeCountByPost[postId] ?? post.likes;
    final trueCount = (base + (nowLiked ? 1 : -1)).clamp(0, 1 << 31);
    _store.likeCountByPost[postId] = trueCount;
    post.liked = nowLiked;
    post.likes = trueCount;
    return (liked: nowLiked, likeCount: trueCount);
  }
}

class _FakeCommentRepository implements CommentRepository {
  _FakeCommentRepository(this._store);

  final _Store _store;

  @override
  Future<List<Comment>> list(String postId) async {
    return List.of(_store.commentsByPost[postId] ?? const []);
  }

  @override
  Future<Comment> create({required String postId, required String text}) async {
    final comment = Comment(
      id: 'c${DateTime.now().millisecondsSinceEpoch}',
      authorId: _store.currentUser.id,
      author: _store.currentUser.name,
      authorUsername: _store.currentUser.username,
      authorAvatarUrl: _store.currentUser.avatarUrl,
      text: text,
      createdAt: DateTime.now(),
    );
    _store.commentsByPost.putIfAbsent(postId, () => []).add(comment);
    return comment;
  }

  @override
  Future<void> delete(String commentId) async {
    for (final list in _store.commentsByPost.values) {
      list.removeWhere((c) => c.id == commentId);
    }
  }
}

class _FakeUserRepository implements UserRepository {
  _FakeUserRepository(this._store);

  final _Store _store;

  @override
  Future<({MatrixUser user, List<Post> posts})> profile(String username) async {
    final user = _store.users.values.firstWhere(
      (u) => u.username == username,
      orElse: () => _store.currentUser,
    );
    final userPosts =
        _store.posts.where((p) => p.authorUsername == username).toList();
    return (user: user, posts: userPosts);
  }

  @override
  Future<MatrixUser> updateProfile({
    String? name,
    String? username,
    String? bio,
    String? avatarUrl,
  }) async {
    final old = _store.currentUser;
    final updated = MatrixUser(
      id: old.id,
      name: name ?? old.name,
      username: username ?? old.username,
      bio: bio ?? old.bio,
      avatarSeed: old.avatarSeed,
      avatarUrl: avatarUrl ?? old.avatarUrl,
    );
    _store.users[old.id] = updated;
    return updated;
  }

  @override
  Future<List<MatrixUser>> search(String query) async {
    final users = _store.users.values.toList();
    if (query.trim().isEmpty) return users;
    final q = query.toLowerCase();
    return users
        .where((u) =>
            u.name.toLowerCase().contains(q) ||
            u.username.toLowerCase().contains(q))
        .toList();
  }
}

class _FakeUploadRepository implements UploadRepository {
  const _FakeUploadRepository();

  @override
  Future<String> upload(File file) async => 'https://fake.matrix.app/u/test.png';
}
