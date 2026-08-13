import 'package:flutter/foundation.dart';

import '../../models/akame_message.dart';
import '../../models/comment.dart';
import '../../models/matrix_user.dart';
import '../../models/post.dart';
import '../utils/mock_data_service.dart';

/// Central local state for Phase 1.
///
/// All mutations are in-memory only. This class is the seam where a real
/// backend/repository will be wired in a future phase.
class AppState extends ChangeNotifier {
  AppState() {
    _posts = MockDataService.initialPosts();
    _akameMessages = MockDataService.initialAkameMessages();
  }

  List<Post> _posts = [];
  List<AkameMessage> _akameMessages = [];
  MatrixUser _currentUser = MockDataService.currentUser;
  bool _disposed = false;

  List<Post> get posts => List.unmodifiable(_posts);
  List<AkameMessage> get akameMessages => List.unmodifiable(_akameMessages);
  MatrixUser get currentUser => _currentUser;

  /// Toggle like locally.
  void toggleLike(String postId) {
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;
    final post = _posts[index];
    post.liked = !post.liked;
    post.likes += post.liked ? 1 : -1;
    notifyListeners();
  }

  /// Add a comment to a post locally.
  void addComment(String postId, String text) {
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index == -1 || text.trim().isEmpty) return;
    _posts[index].comments = [
      ..._posts[index].comments,
      Comment(
        id: 'c${DateTime.now().millisecondsSinceEpoch}',
        author: _currentUser.name,
        text: text.trim(),
        createdAt: DateTime.now(),
      ),
    ];
    notifyListeners();
  }

  /// Create a post locally and return its id.
  String createPost({required String text, String? imageUrl}) {
    final post = Post(
      id: 'p${DateTime.now().millisecondsSinceEpoch}',
      authorName: _currentUser.name,
      authorUsername: _currentUser.username,
      text: text.trim(),
      createdAt: DateTime.now(),
      avatarSeed: _currentUser.avatarSeed,
      imageUrl: imageUrl,
      likes: 0,
      liked: false,
      comments: const [],
    );
    _posts = [post, ..._posts];
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

  /// Update the current user profile locally.
  void updateProfile({String? name, String? username, String? bio}) {
    _currentUser = _currentUser.copyWith(
      name: name,
      username: username,
      bio: bio,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
