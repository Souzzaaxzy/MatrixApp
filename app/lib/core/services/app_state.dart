import 'dart:async';

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
  List<Post> get posts => List.unmodifiable(_posts);
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

  /// Toggles a like remotely and updates the local post in place.
  Future<void> toggleLike(String postId) async {
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;
    final post = _posts[index];
    // Optimistic update.
    final wasLiked = post.liked;
    post.liked = !wasLiked;
    post.likes += wasLiked ? -1 : 1;
    notifyListeners();
    try {
      final result = await _likes.toggle(postId);
      post.liked = result.liked;
      post.likes = result.likeCount;
    } catch (_) {
      // Roll back on failure.
      post.liked = wasLiked;
      post.likes += wasLiked ? 1 : -1;
    }
    notifyListeners();
  }

  /// Loads the real comment list for a post (replaces placeholders).
  Future<List<Comment>> loadComments(String postId) async {
    return _comments.list(postId);
  }

  /// Adds a comment remotely and returns it.
  Future<Comment> addComment(String postId, String text) async {
    return _comments.create(postId: postId, text: text.trim());
  }

  /// Creates a post remotely and prepends it to the local feed.
  Future<String> createPost({required String text, String? imageUrl}) async {
    final post = await _postsRepo.create(text: text.trim(), imageUrl: imageUrl);
    _posts.insert(0, post);
    notifyListeners();
    return post.id;
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

  /// Updates the current user profile remotely.
  Future<void> updateProfile({String? name, String? bio}) async {
    final updated = await _users.updateProfile(name: name, bio: bio);
    _currentUser = updated;
    notifyListeners();
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
