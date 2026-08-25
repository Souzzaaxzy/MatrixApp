import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/api_config.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services.dart';
import '../../models/akame_message.dart';
import '../../models/comment.dart';
import '../../models/matrix_user.dart';
import '../../models/post.dart';
import '../utils/mock_data_service.dart';

/// Central app state for Phase 2.
///
/// Wires the UI to the real backend via the repository layer in
/// [Services]. Holds the current user session, the cached feed, and the
/// Akame chat (still mock — no AI backend yet). All network mutations go
/// through this class so the UI can stay declarative.
class AppState extends ChangeNotifier {
  /// When [repositories] is null (production), the real repositories from
  /// [Services.instance] are used. Tests inject an in-memory set so the
  /// optimistic-update / caching logic can be exercised without a network.
  AppState({Repositories? repositories})
      : _repos = repositories,
        _akameMessages = MockDataService.initialAkameMessages();

  final Repositories? _repos;
  List<AkameMessage> _akameMessages = [];
  MatrixUser? _currentUser;
  String? _feedCursor;
  bool _loadingFeed = false;
  bool _disposed = false;

  final List<Post> _posts = [];

  /// Posts of the profile currently being viewed (server source of truth —
  /// loaded via GET /api/users/:username, never derived from the feed cache).
  final List<Post> _profilePosts = [];
  MatrixUser? _profileUser;
  bool _loadingProfile = false;

  /// Posts fetched individually (detail screen) that may not be present in
  /// the feed/profile caches. Lets likes/comments work uniformly by id.
  final Map<String, Post> _postCache = {};

  List<Post> get posts => List.unmodifiable(_posts);
  List<Post> get profilePosts => List.unmodifiable(_profilePosts);
  MatrixUser? get profileUser => _profileUser;
  bool get isLoadingProfile => _loadingProfile;
  List<AkameMessage> get akameMessages => List.unmodifiable(_akameMessages);
  MatrixUser? get currentUser => _currentUser;
  bool get isLoadingFeed => _loadingFeed;
  bool get isAuthenticated => _currentUser != null;

  AuthRepository get _auth => _repos?.auth ?? Services.instance.auth;
  PostRepository get _postsRepo => _repos?.posts ?? Services.instance.posts;
  LikeRepository get _likes => _repos?.likes ?? Services.instance.likes;
  CommentRepository get _comments =>
      _repos?.comments ?? Services.instance.comments;
  UserRepository get _users => _repos?.users ?? Services.instance.users;

  /// Restores the session from a stored refresh token. Called at startup.
  /// Returns true when the user is authenticated afterwards.
  Future<bool> restoreSession() async {
    try {
      _currentUser = (await _auth.me()).toModel();
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _auth.logout();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Logs in with a username + password.
  Future<void> login({required String username, required String password}) async {
    final dto = await _auth.login(username: username, password: password);
    _currentUser = dto.user.toModel();
    notifyListeners();
  }

  /// Registers a new account and logs in. Returns the one-time recovery
  /// code the backend generated so the UI can display it to the user.
  Future<String> register({
    required String name,
    required String username,
    required String password,
  }) async {
    final dto = await _auth.register(
      name: name,
      username: username,
      password: password,
    );
    _currentUser = dto.user.toModel();
    notifyListeners();
    return dto.recoveryCode ?? '';
  }

  /// Recovers an account via recovery code + new password. The user must
  /// log in again afterwards.
  Future<void> recover({
    required String identifier,
    required String recoveryCode,
    required String newPassword,
  }) async {
    await _auth.recover(
      identifier: identifier,
      recoveryCode: recoveryCode,
      newPassword: newPassword,
    );
  }

  /// Logs out and clears local state.
  Future<void> logout() async {
    await _auth.logout();
    _currentUser = null;
    _posts.clear();
    _profilePosts.clear();
    _profileUser = null;
    _feedCursor = null;
    notifyListeners();
  }

  /// Loads the first page of the feed (replaces existing posts).
  Future<void> loadFeed() async {
    if (_loadingFeed) return;
    _loadingFeed = true;
    notifyListeners();
    try {
      final result = await _postsRepo.feed();
      _posts
        ..clear()
        ..addAll(result.posts);
      _feedCursor = result.nextCursor;
    } finally {
      _loadingFeed = false;
      notifyListeners();
    }
  }

  /// Loads the next page of the feed (appends). No-op when no cursor.
  Future<void> loadMoreFeed() async {
    if (_loadingFeed || _feedCursor == null) return;
    _loadingFeed = true;
    notifyListeners();
    try {
      final result = await _postsRepo.feed(cursor: _feedCursor);
      _posts.addAll(result.posts);
      _feedCursor = result.nextCursor;
    } finally {
      _loadingFeed = false;
      notifyListeners();
    }
  }

  /// Finds a post by id in the feed cache, the profile cache, or the
  /// individual-post cache.
  Post? _findPost(String postId) {
    for (final p in _posts) {
      if (p.id == postId) return p;
    }
    for (final p in _profilePosts) {
      if (p.id == postId) return p;
    }
    return _postCache[postId];
  }

  /// Toggles a like remotely (server is the source of truth) and updates
  /// the local post in place with an optimistic update.
  ///
  /// Returns true when the server confirmed the change. On failure the
  /// optimistic change is rolled back and false is returned so the UI can
  /// surface a discreet error — the local state NEVER diverges silently
  /// from the server.
  Future<bool> toggleLike(String postId) async {
    final post = _findPost(postId);
    if (post == null) return false;
    // Optimistic update.
    final wasLiked = post.liked;
    final wasCount = post.likes;
    post.liked = !wasLiked;
    post.likes += wasLiked ? -1 : 1;
    notifyListeners();
    try {
      final result = await _likes.toggle(postId);
      post.liked = result.liked;
      post.likes = result.likeCount;
      notifyListeners();
      return true;
    } catch (_) {
      // Roll back on failure — the server state wins.
      post.liked = wasLiked;
      post.likes = wasCount;
      notifyListeners();
      return false;
    }
  }

  /// Loads the real comment list for a post (replaces placeholders).
  Future<List<Comment>> loadComments(String postId) async {
    return _comments.list(postId);
  }

  /// Adds a comment remotely and returns it. Bumps the cached comment
  /// count so the feed/profile reflect the new comment immediately.
  Future<Comment> addComment(String postId, String text) async {
    final comment = await _comments.create(postId: postId, text: text.trim());
    final post = _findPost(postId);
    if (post != null) {
      post.commentCount += 1;
      notifyListeners();
    }
    return comment;
  }

  /// Creates a post remotely and prepends it to the local feed (and to the
  /// profile grid when the viewed profile is the author's own).
  Future<String> createPost({required String text, String? imageUrl}) async {
    final post = await _postsRepo.create(text: text.trim(), imageUrl: imageUrl);
    _posts.insert(0, post);
    if (_profileUser?.username == post.authorUsername) {
      _profilePosts.insert(0, post);
    }
    notifyListeners();
    return post.id;
  }

  /// Deletes a post owned by the current user. The server enforces
  /// ownership (403 otherwise); on success the post is removed from every
  /// local cache so the feed/profile update without a restart.
  Future<bool> deletePost(String postId) async {
    try {
      await _postsRepo.delete(postId);
      _posts.removeWhere((p) => p.id == postId);
      _profilePosts.removeWhere((p) => p.id == postId);
      _postCache.remove(postId);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fetches a single post by id straight from the server (post detail).
  /// The returned post is cached by id so likes/comments keep working even
  /// when the post is not part of the feed/profile caches.
  Future<Post> getPost(String postId) async {
    final post = await _postsRepo.getById(postId);
    _postCache[postId] = post;
    syncPost(post);
    return _findPost(postId) ?? post;
  }

  /// Copies the mutable engagement state (likes/liked/comment count) of
  /// [updated] into every cached copy of the same post, so a like made on
  /// the detail screen is reflected in the feed and the profile grid.
  void syncPost(Post updated) {
    for (final list in [_posts, _profilePosts]) {
      for (final p in list) {
        if (p.id == updated.id && !identical(p, updated)) {
          p.liked = updated.liked;
          p.likes = updated.likes;
          p.commentCount = updated.commentCount;
        }
      }
    }
    final cached = _postCache[updated.id];
    if (cached != null && !identical(cached, updated)) {
      cached.liked = updated.liked;
      cached.likes = updated.likes;
      cached.commentCount = updated.commentCount;
    }
    notifyListeners();
  }

  /// Loads a profile (user + their posts) from the server. This is the
  /// ONLY source for the profile screen — never the local feed cache.
  Future<void> loadProfile(String username) async {
    if (_loadingProfile) return;
    _loadingProfile = true;
    notifyListeners();
    try {
      final result = await _users.profile(username);
      _profileUser = result.user;
      _profilePosts
        ..clear()
        ..addAll(result.posts);
      // Keep the session user fresh when viewing our own profile.
      if (_currentUser?.username == result.user.username) {
        _currentUser = _currentUser!.copyWith(
          name: result.user.name,
          bio: result.user.bio,
          avatarUrl: result.user.avatarUrl,
        );
      }
    } finally {
      _loadingProfile = false;
      notifyListeners();
    }
  }

  /// Refreshes the session user from the server (GET /api/auth/me).
  Future<void> refreshCurrentUser() async {
    _currentUser = (await _auth.me()).toModel();
    notifyListeners();
  }

  /// Send a user message and produce a deterministic Akame mock reply.
  void sendAkameMessage(String text) {
    if (text.trim().isEmpty) return;
    final now = DateTime.now();
    _akameMessages = [
      ..._akameMessages,
      AkameMessage(
        id: 'm${now.millisecondsSinceEpoch}',
        text: text.trim(),
        fromUser: true,
        createdAt: now,
      ),
    ];
    notifyListeners();

    // Simulated typing + canned reply. Replace with a real AI API call later.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (_disposed) return;
      final reply = MockDataService.akameReplies[
          _akameMessages.length % MockDataService.akameReplies.length];
      _akameMessages = [
        ..._akameMessages,
        AkameMessage(
          id: 'a${DateTime.now().millisecondsSinceEpoch}',
          text: reply,
          fromUser: false,
          createdAt: DateTime.now(),
        ),
      ];
      notifyListeners();
    });
  }

  /// Updates the current user profile remotely (PATCH /api/users/me).
  /// The server response is authoritative — local state is replaced with
  /// whatever the server persisted.
  Future<void> updateProfile({
    String? name,
    String? username,
    String? bio,
    String? avatarUrl,
  }) async {
    final updated = await _users.updateProfile(
      name: name,
      username: username,
      bio: bio,
      avatarUrl: avatarUrl,
    );
    _currentUser = updated;
    notifyListeners();
  }

  /// Uploads a new avatar image and persists it on the profile.
  /// Returns the public URL of the stored image. Each upload gets a new
  /// unique filename server-side, so the new URL naturally busts any
  /// client-side image cache.
  Future<String> changeAvatar(File image) async {
    final uploads = _repos?.uploads ?? Services.instance.uploads;
    final url = await uploads.upload(image);
    await updateProfile(avatarUrl: url);
    return url;
  }

  /// Searches users by name / username.
  Future<List<MatrixUser>> searchUsers(String query) async {
    return _users.search(query);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
