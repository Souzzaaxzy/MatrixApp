import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/api_config.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services.dart';
import '../../models/akame_message.dart';
import '../../models/comment.dart';
import '../../models/conversation.dart';
import '../../models/cosmetic_item.dart';
import '../../models/friend_request.dart';
import '../../models/matrix_notification.dart';
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

  /// Viewed profiles, keyed by lowercase nickname. This is the core
  /// currentUser/viewedUser separation: the authenticated user lives ONLY
  /// in [_currentUser]; every viewed profile (including our own, once
  /// loaded) is a standalone entry in this map that never overwrites
  /// [_currentUser]. Opening A → B → C never corrupts A.
  final Map<String, ProfileData> _profiles = {};
  bool _loadingProfile = false;

  /// Notifications of the session user (persistent server-side list).
  final List<MatrixNotification> _notifications = [];
  bool _loadingNotifications = false;

  /// Cosmetics equipped by the SESSION user, keyed by slot. Server-owned:
  /// loaded from `/api/customization/equipped` and refreshed after every
  /// equip/unequip. Viewed users' cosmetics live in their [ProfileData].
  CosmeticMap _myCosmetics = const {};
  bool _loadingCosmetics = false;

  /// Server-owned NAME_COLOR catalog (the official palette). Loaded once
  /// per session — the app never hardcodes which colors exist.
  List<CosmeticItem> _nameColorCatalog = const [];
  bool _loadingNameColorCatalog = false;

  /// Server-owned AVATAR_FRAME catalog (the official MOLDURAS list). Loaded
  /// once per session — the app never hardcodes which frames exist (the
  /// sprite for each comes bundled, keyed by the server's assetUrl).
  List<CosmeticItem> _frameCatalog = const [];
  bool _loadingFrameCatalog = false;

  /// Posts fetched individually (detail screen) that may not be present in
  /// the feed/profile caches. Lets likes/comments work uniformly by id.
  final Map<String, Post> _postCache = {};

  /// Private chat: the authenticated user's conversations (Chat tab).
  final List<Conversation> _conversations = [];
  bool _loadingConversations = false;

  /// Total unread conversations, shown as a badge on the 💬 Chat tab.
  int _unreadConversations = 0;

  /// Real-time incoming chat messages (from the shared WebSocket). The
  /// conversation screen listens so an open DM updates live; the Chat tab
  /// listens (while open) to refresh the list/unread badge.
  final _chatIncoming = StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get onChatIncoming => _chatIncoming.stream;

  /// Emits whenever a friendship relationship changes (request sent/cancelled,
  /// removed, accepted). Screens that render the live friends list subscribe
  /// so removal on a profile reflects immediately when they become visible.
  final _friendsChanged = StreamController<void>.broadcast();
  Stream<void> get onFriendsChanged => _friendsChanged.stream;

  List<Post> get posts => List.unmodifiable(_posts);
  bool get isLoadingProfile => _loadingProfile;

  /// The viewed-profile snapshot for [nickname] (null/empty → the session
  /// user's own). Returns null until the first server load completes.
  ProfileData? profileFor(String? nickname) {
    final key = (nickname == null || nickname.isEmpty)
        ? _currentUser?.nickname
        : nickname;
    if (key == null) return null;
    return _profiles[key.toLowerCase()];
  }
  List<MatrixNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadNotifications => _notifications.where((n) => !n.read).length;
  bool get isLoadingNotifications => _loadingNotifications;

  /// Private chat getters.
  List<Conversation> get conversations => List.unmodifiable(_conversations);
  bool get isLoadingConversations => _loadingConversations;
  int get unreadConversations => _unreadConversations;

  /// Cosmetics equipped by the session user (slot → item). Empty means
  /// "all defaults" — the spec's "Nenhuma" state.
  CosmeticMap get myCosmetics => Map.unmodifiable(_myCosmetics);
  bool get isLoadingCosmetics => _loadingCosmetics;

  /// The official nickname color palette (server catalog), empty until
  /// [loadNameColorCatalog] completes.
  List<CosmeticItem> get nameColorCatalog => List.unmodifiable(_nameColorCatalog);

  /// The official profile frame catalog (server), empty until
  /// [loadFrameCatalog] completes.
  List<CosmeticItem> get frameCatalog => List.unmodifiable(_frameCatalog);
  bool get isLoadingFrameCatalog => _loadingFrameCatalog;

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
  FriendRepository get _friends => _repos?.friends ?? Services.instance.friends;
  NotificationRepository get _notificationRepo =>
      _repos?.notifications ?? Services.instance.notifications;
  CustomizationRepository get _customizationRepo =>
      _repos?.customization ?? Services.instance.customization;
  ChatRepository get _chat => _repos?.chat ?? Services.instance.chat;

  /// Restores the session from a stored refresh token. Called at startup.
  /// Returns true when the user is authenticated afterwards.
  Future<bool> restoreSession() async {
    try {
      _currentUser = (await _auth.me()).toModel();
      notifyListeners();
      _syncPush();
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

  /// Logs in with a nickname + password.
  Future<void> login({required String nickname, required String password}) async {
    final dto = await _auth.login(nickname: nickname, password: password);
    _currentUser = dto.user.toModel();
    notifyListeners();
    _syncPush();
  }

  /// Registers a new account and logs in. Returns the one-time recovery
  /// code the backend generated so the UI can display it to the user.
  Future<String> register({
    required String nickname,
    required String password,
  }) async {
    final dto = await _auth.register(
      nickname: nickname,
      password: password,
    );
    _currentUser = dto.user.toModel();
    notifyListeners();
    _syncPush();
    return dto.recoveryCode ?? '';
  }

  /// Binds the push pipeline to the session (device token + realtime
  /// socket). No-op in tests: they inject repositories and never touch the
  /// real Services singleton.
  void _syncPush() {
    if (_repos != null || !Services.isInitialized) return;
    Services.instance.push.sync();
  }

  void _stopPush() {
    if (_repos != null || !Services.isInitialized) return;
    Services.instance.push.stop();
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
    _stopPush();
    await _auth.logout();
    _clearSessionCaches();
    notifyListeners();
  }

  /// Permanently deletes the account on the server, then clears every
  /// local trace (session + caches) like a logout. The server-side delete
  /// cascades posts/comments/likes/friendships/notifications/devices.
  Future<void> deleteAccount() async {
    _stopPush();
    await _auth.deleteAccount();
    _clearSessionCaches();
    notifyListeners();
  }

  void _clearSessionCaches() {
    _currentUser = null;
    _posts.clear();
    _profiles.clear();
    _notifications.clear();
    _postCache.clear();
    _feedCursor = null;
    _myCosmetics = const {};
    _nameColorCatalog = const [];
    _frameCatalog = const [];
    _akameMessages = MockDataService.initialAkameMessages();
    _clearConversations();
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

  /// Finds a post by id in the feed cache, any viewed-profile cache, or
  /// the individual-post cache.
  Post? _findPost(String postId) {
    for (final p in _posts) {
      if (p.id == postId) return p;
    }
    for (final profile in _profiles.values) {
      for (final p in profile.posts) {
        if (p.id == postId) return p;
      }
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
      // Propagate the confirmed state to every cached copy of the same post
      // (feed ↔ every viewed-profile cache ↔ detail cache). The SAME post
      // must show the SAME heart everywhere — a like made on a profile's
      // post is reflected in the feed and vice-versa. [post] itself is
      // already updated above, so skip it inside _syncPost.
      _syncPost(post, skip: post);
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

  /// Loads the replies of a top-level comment.
  Future<List<Comment>> loadReplies(String parentCommentId) async {
    return _comments.listReplies(parentCommentId);
  }

  /// Creates a reply under [parentCommentId] and returns it. Bumps the
  /// post's comment count like a regular comment.
  Future<Comment> addReply({
    required String parentCommentId,
    required String postId,
    required String text,
  }) async {
    final reply = await _comments.reply(
      parentCommentId: parentCommentId,
      text: text.trim(),
    );
    final post = _findPost(postId);
    if (post != null) {
      post.commentCount += 1;
      notifyListeners();
    }
    return reply;
  }

  /// Toggles a like on a comment/reply. The server is the source of truth;
  /// on failure we simply don't change anything (the UI optimistically
  /// reflects the change and reconciles with the confirmed state).
  Future<({bool liked, int likeCount})?> toggleCommentLike(
    String commentId, {
    required bool liked,
  }) async {
    try {
      final result = await _comments.toggleLike(commentId, liked: liked);
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Creates a post remotely and prepends it to the local feed (and to the
  /// profile grid when the viewed profile is the author's own).
  Future<String> createPost({required String text, String? imageUrl}) async {
    final post = await _postsRepo.create(text: text.trim(), imageUrl: imageUrl);
    _posts.insert(0, post);
    // Reflect on the author's viewed profile, if loaded: posts list grows
    // and the server-side counter bumps by one (matches Part 2.3).
    final key = post.authorNickname.toLowerCase();
    final profile = _profiles[key];
    if (profile != null) {
      _profiles[key] = profile.copyWith(
        user: profile.user
            .copyWith(postsCount: profile.user.postsCount + 1),
        posts: [post, ...profile.posts],
      );
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
      // Remove from every viewed-profile cache and keep the author's
      // counter in sync with the server (Posts: 9 → 8).
      _profiles.updateAll((key, profile) {
        if (!profile.posts.any((p) => p.id == postId)) return profile;
        return profile.copyWith(
          user: profile.user.copyWith(
            postsCount: (profile.user.postsCount - 1).clamp(0, 1 << 31),
          ),
          posts: profile.posts.where((p) => p.id != postId).toList(),
        );
      });
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
  /// [updated] into every OTHER cached copy of the same post, so a like made
  /// on the detail screen is reflected in the feed and the profile grid —
  /// the SAME post always shows the SAME engagement state everywhere.
  void syncPost(Post updated, {Post? skip}) {
    _syncPost(updated, skip: skip ?? updated);
  }

  void _syncPost(Post updated, {required Post skip}) {
    for (final p in _posts) {
      if (p.id == updated.id && !identical(p, skip)) {
        p.liked = updated.liked;
        p.likes = updated.likes;
        p.commentCount = updated.commentCount;
      }
    }
    for (final profile in _profiles.values) {
      for (final p in profile.posts) {
        if (p.id == updated.id && !identical(p, skip)) {
          p.liked = updated.liked;
          p.likes = updated.likes;
          p.commentCount = updated.commentCount;
        }
      }
    }
    final cached = _postCache[updated.id];
    if (cached != null && !identical(cached, skip)) {
      cached.liked = updated.liked;
      cached.likes = updated.likes;
      cached.commentCount = updated.commentCount;
    }
  }

  /// Loads a profile (user + their posts + friendship state) from the
  /// server into its OWN keyed slot. This is the ONLY source for the
  /// profile screen — never the local feed cache, and never the data of
  /// another profile: a concurrent visit to B never rewrites A's slot.
  Future<void> loadProfile(String nickname) async {
    if (_loadingProfile) return;
    _loadingProfile = true;
    notifyListeners();
    try {
      final result = await _users.profile(nickname);
      final key = result.user.nickname.toLowerCase();
      _profiles[key] = ProfileData(
        user: result.user,
        posts: result.posts,
        friendship: result.friendship,
      );
      // Keep the session user fresh when viewing our own profile — a copy
      // of name/bio/avatar only, identity fields (id/nickname) are NEVER
      // overwritten by a viewed profile.
      if (_currentUser?.nickname.toLowerCase() == key) {
        _currentUser = _currentUser!.copyWith(
          nickname: result.user.nickname,
          bio: result.user.bio,
          avatarUrl: result.user.avatarUrl,
          customization: result.user.customization,
          nameColor: () => result.user.nameColor,
        );
      }
    } finally {
      _loadingProfile = false;
      notifyListeners();
    }
  }

  /// Reloads the notifications list (server is the source of truth).
  Future<void> loadNotifications() async {
    if (_loadingNotifications) return;
    _loadingNotifications = true;
    notifyListeners();
    try {
      final result = await _notificationRepo.list();
      _notifications
        ..clear()
        ..addAll(result.notifications);
    } finally {
      _loadingNotifications = false;
      notifyListeners();
    }
  }

  /// Marks a notification as read remotely (the unread badge is derived).
  Future<void> markNotificationRead(String id) async {
    try {
      await _notificationRepo.markRead(id);
    } catch (_) {
      // A failed mark-read is non-blocking: the badge may stay for a bit.
    }
    for (var i = 0; i < _notifications.length; i++) {
      if (_notifications[i].id == id && !_notifications[i].read) {
        _notifications[i] = _notifications[i].copyWith(read: true);
      }
    }
    notifyListeners();
  }

  /// Marks every notification as read.
  Future<void> markAllNotificationsRead() async {
    try {
      await _notificationRepo.markAllRead();
    } catch (_) {
      // Non-blocking (see above).
    }
    for (var i = 0; i < _notifications.length; i++) {
      if (!_notifications[i].read) {
        _notifications[i] = _notifications[i].copyWith(read: true);
      }
    }
    notifyListeners();
  }

  /// Loads the session user's equipped cosmetics from the server. The
  /// server is the single source of truth — a fresh app start always
  /// restores the exact same equipped state.
  Future<void> loadMyCosmetics() async {
    if (_loadingCosmetics) return;
    _loadingCosmetics = true;
    notifyListeners();
    try {
      _myCosmetics = await _customizationRepo.equipped();
      _syncMyNameCosmetics();
      _syncMyFrame();
    } catch (_) {
      // Non-blocking: the preview simply shows defaults until a retry.
    } finally {
      _loadingCosmetics = false;
      notifyListeners();
    }
  }

  /// Loads the server-owned nickname color palette once per session. The
  /// catalog is cached: rendering a colored nickname NEVER hits the
  /// network — only opening the picker does (and only the first time).
  Future<void> loadNameColorCatalog() async {
    if (_loadingNameColorCatalog || _nameColorCatalog.isNotEmpty) return;
    _loadingNameColorCatalog = true;
    try {
      _nameColorCatalog =
          await _customizationRepo.catalog(type: CosmeticItem.nameColor);
    } catch (_) {
      // Non-blocking: the picker retries on the next open.
    } finally {
      _loadingNameColorCatalog = false;
      notifyListeners();
    }
  }

  /// Loads the server-owned profile frame catalog once per session. The
  /// server is the source of truth for WHICH frames exist and their display
  /// names; the sprite for each rides along bundled in the APK.
  Future<void> loadFrameCatalog() async {
    if (_loadingFrameCatalog || _frameCatalog.isNotEmpty) return;
    _loadingFrameCatalog = true;
    try {
      _frameCatalog =
          await _customizationRepo.catalog(type: CosmeticItem.avatarFrame);
    } catch (_) {
      // Non-blocking: the picker retries on the next open.
    } finally {
      _loadingFrameCatalog = false;
      notifyListeners();
    }
  }

  /// Consolidated save of the pending nickname customization in ONE server
  /// operation: `{nameColorId, frameId}` (null removes the slot). The server
  /// validates each id against the active catalog and persists it; the
  /// server-confirmed equipped map is then reloaded and propagated globally
  /// so every nickname/avatar of the session user updates immediately.
  Future<void> saveCosmetics({String? nameColorId, String? frameId}) async {
    await _customizationRepo.saveCosmetics(
      nameColorId: nameColorId,
      frameId: frameId,
    );
    // The server is the source of truth: reload the equipped map so the
    // whole app reflects the confirmed state (not a local guess).
    _myCosmetics = await _customizationRepo.equipped();
    _syncMyNameCosmetics();
    _syncMyFrame();
    notifyListeners();
  }

  /// Equips an owned item and refreshes the local equipped map from the
  /// server response (ownership/expiry are validated server-side).
  Future<void> equipCosmetic(String itemId) async {
    final item = await _customizationRepo.equip(itemId);
    _myCosmetics = {..._myCosmetics, item.slot: item};
    if (item.slot == CosmeticItem.nameColor) {
      _syncMyNameCosmetics();
    }
    notifyListeners();
  }

  /// Removes whatever is equipped in [slot].
  Future<void> unequipCosmetic(String slot) async {
    await _customizationRepo.unequip(slot);
    _myCosmetics = {..._myCosmetics}..remove(slot);
    if (slot == CosmeticItem.nameColor) {
      _syncMyNameCosmetics();
    }
    notifyListeners();
  }

  /// Propagates the session user's equipped nickname color into the global
  /// state (currentUser + the own-profile cache) so EVERY component that
  /// renders the user's nickname reflects a change immediately — no
  /// restart, no re-login, no screen refresh.
  void _syncMyNameCosmetics() {
    final hex = _myCosmetics[CosmeticItem.nameColor]?.hexColor;
    final me = _currentUser;
    if (me == null) return;
    _currentUser = me.copyWith(nameColor: () => hex);
    final key = me.nickname.toLowerCase();
    final profile = _profiles[key];
    if (profile != null) {
      _profiles[key] = profile.copyWith(
        user: profile.user.copyWith(nameColor: () => hex),
      );
    }
  }

  /// Propagates the session user's equipped frame into the global state
  /// (currentUser + the own-profile cache) so every avatar reflects it
  /// immediately after a save — no restart, no re-login.
  void _syncMyFrame() {
    final frame = _myCosmetics[CosmeticItem.avatarFrame];
    final me = _currentUser;
    if (me == null) return;
    final id = frame?.id;
    final asset = frame?.assetUrl;
    _currentUser = me.copyWith(
      customization: {..._myCosmetics},
      frameId: () => id,
      frameAsset: () => asset,
    );
    final key = me.nickname.toLowerCase();
    final profile = _profiles[key];
    if (profile != null) {
      _profiles[key] = profile.copyWith(
        user: profile.user.copyWith(
          customization: {..._myCosmetics},
          frameId: () => id,
          frameAsset: () => asset,
        ),
      );
    }
  }

  /// Sends a friend request to another user. On success the friendship
  /// state of that user's viewed profile moves to Solicitado
  /// (OUTGOING_PENDING) — only that profile's slot is touched.
  Future<void> sendFriendRequest(String userId) async {
    await _friends.send(userId);
    _profiles.updateAll((key, profile) => profile.user.id == userId
        ? profile.copyWith(friendship: Friendship.outgoingPending)
        : profile);
    _emitFriendsChanged();
    notifyListeners();
  }

  /// Cancels the PENDING request the current user sent to [userId]. The
  /// server removes the request + its notification; the profile state
  /// returns to SOLICITAR (NONE). State is server-confirmed — a fresh
  /// profile load after this reports NONE too.
  Future<void> cancelFriendRequest(String userId) async {
    await _friends.cancel(userId);
    _profiles.updateAll((key, profile) => profile.user.id == userId
        ? profile.copyWith(friendship: Friendship.none)
        : profile);
    _emitFriendsChanged();
    notifyListeners();
  }

  /// Removes the ACCEPTED friendship between the current user and [userId].
  /// The server validates the requester and deletes the row; the profile
  /// state returns to SOLICITAR (NONE) and the Amigos counters of both
  /// affected cached profiles (mine + the other user's) drop by one.
  Future<void> removeFriend(String userId) async {
    await _friends.removeFriend(userId);
    final me = _currentUser?.id;
    _profiles.updateAll((key, profile) {
      final uid = profile.user.id;
      final isMine = uid == me;
      final isOther = uid == userId;
      if (!isMine && !isOther) return profile;
      return profile.copyWith(
        user: profile.user.copyWith(
          friendsCount: (profile.user.friendsCount - 1).clamp(0, 1 << 31).toInt(),
        ),
        friendship: Friendship.none,
      );
    });
    _emitFriendsChanged();
    notifyListeners();
  }

  /// Accepts a pending friend request received by the current user. The
  /// actionable notification card disappears, the relation becomes Amigos
  /// on both sides (server-managed) and the Amigos counters of the two
  /// affected profiles (mine + the sender's, when cached) bump by one.
  Future<void> acceptFriendRequest(String requestId) async {
    // Resolve the sender BEFORE the actionable card disappears so the
    // counters of the two affected profiles can be updated.
    final senderId = _notifications
        .where((n) => n.friendRequestId == requestId)
        .map((n) => n.actorId)
        .firstOrNull;
    await _friends.accept(requestId);
    _removeNotificationWhere((n) => n.friendRequestId == requestId);
    final me = _currentUser?.id;
    _profiles.updateAll((key, profile) {
      final uid = profile.user.id;
      final isMine = uid == me;
      final isSender = uid == senderId;
      if (!isMine && !isSender) return profile;
      return profile.copyWith(
        user: profile.user
            .copyWith(friendsCount: profile.user.friendsCount + 1),
        friendship: isSender ? Friendship.friends : profile.friendship,
      );
    });
    _emitFriendsChanged();
    notifyListeners();
  }

  void _emitFriendsChanged() {
    if (!_friendsChanged.isClosed) _friendsChanged.add(null);
  }

  /// Loads one page of the friends list of [userId] (own or another
  /// user's profile — the server returns accepted friendships only).
  Future<({List<MatrixUser> friends, int total, int page, int pageSize})>
      loadFriends(String userId, {int page = 1, int pageSize = 20}) {
    return _friends.list(userId, page: page, pageSize: pageSize);
  }

  /// Rejects a pending friend request. The card disappears and the sender
  /// can request again later.
  Future<void> rejectFriendRequest(String requestId) async {
    await _friends.reject(requestId);
    _removeNotificationWhere((n) => n.friendRequestId == requestId);
    notifyListeners();
  }

  void _removeNotificationWhere(bool Function(MatrixNotification n) kill) {
    _notifications.removeWhere(kill);
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
    String? nickname,
    String? bio,
    String? avatarUrl,
  }) async {
    final updated = await _users.updateProfile(
      nickname: nickname,
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

  /// Searches users by name / nickname.
  Future<List<MatrixUser>> searchUsers(String query) async {
    return _users.search(query);
  }

  // ── Private chat ───────────────────────────────────────────

  /// Loads the authenticated user's conversations into state. Called when
  /// the Chat tab opens and after logout/login to refresh the cache.
  Future<void> loadConversations() async {
    _loadingConversations = true;
    notifyListeners();
    try {
      final list = await _chat.conversations();
      _conversations
        ..clear()
        ..addAll(list);
    } finally {
      _loadingConversations = false;
      notifyListeners();
    }
  }

  /// Refreshes just the unread conversations badge (light — used after a
  /// real-time message arrives or the tab reopens).
  Future<void> refreshUnreadConversations() async {
    try {
      _unreadConversations = await _chat.unreadCount();
    } catch (_) {
      // Best-effort: keep the last known badge on failure.
    }
    notifyListeners();
  }

  /// Opens (or creates) the single conversation with [otherUserId] and
  /// returns it. The server enforces the friends-only rule.
  Future<Conversation> getOrCreateConversation(String otherUserId) {
    return _chat.getOrCreate(otherUserId);
  }

  /// Latest messages of a conversation (newest batch, chronological).
  Future<({List<ChatMessage> messages, bool hasMore})> loadMessages(
    String conversationId, {
    String? before,
    int limit = 30,
  }) {
    return _chat.messages(conversationId, before: before, limit: limit);
  }

  /// Sends a chat message and, on success, optimistically records it in the
  /// cached conversation's last-message slot (the server response is
  /// authoritative and returned for the screen to append).
  Future<ChatMessage> sendChatMessage(
    String conversationId,
    String content, {
    ChatUser? otherUser,
  }) async {
    final message = await _chat.send(conversationId, content);
    _applyChatMessage(message, otherUser: otherUser ?? _peerOf(conversationId));
    return message;
  }

  /// Marks a conversation as read by the session user and clears its unread
  /// badge from the local cache.
  Future<void> markConversationRead(String conversationId) async {
    try {
      await _chat.markRead(conversationId);
    } catch (_) {
      // Best-effort: reading is not fatal.
    }
    var modified = false;
    for (var i = 0; i < _conversations.length; i++) {
      if (_conversations[i].id == conversationId &&
          _conversations[i].unreadCount > 0) {
        final c = _conversations[i];
        _conversations[i] = c.copyWith(unreadCount: 0);
        modified = true;
      }
    }
    if (modified) _recomputeUnreadBadge();
    notifyListeners();
  }

  /// A real-time chat message arrived on the WebSocket. If it belongs to a
  /// conversation we have cached, update that conversation (last message +
  /// unread badge); the peer (needed for the preview) is the message sender
  /// when we don't already know it.
  /// Emits on [onChatIncoming] for open conversation screens.
  void handleIncomingChatMessage(ChatMessage message) {
    if (_disposed) return;
    final cached = _conversations.indexWhere((c) => c.id == message.conversationId);
    if (cached != -1) {
      final peer = _peerOf(message.conversationId);
      _applyChatMessage(message, otherUser: peer, selfMade: false);
    }
    if (!_chatIncoming.isClosed) _chatIncoming.add(message);
    notifyListeners();
  }

  ChatUser? _peerOf(String conversationId) {
    for (final c in _conversations) {
      if (c.id == conversationId) return c.otherUser;
    }
    return null;
  }

  /// Applies a chat message to the cached conversation last-message slot.
  /// [selfMade] keeps the unread badge untouched for our own sends (incoming
  /// messages may bump the unread counter of the OTHER side's cached slot —
  /// but this user's own badge only counts the OTHER side's messages sent to
  /// them, so incoming self messages can never add to the session user's
  /// badge; the flag just makes the intent explicit).
  void _applyChatMessage(
    ChatMessage message, {
    ChatUser? otherUser,
    bool selfMade = true,
  }) {
    for (var i = 0; i < _conversations.length; i++) {
      final c = _conversations[i];
      if (c.id != message.conversationId) continue;
      final last = ConversationLastMessage(
        id: message.id,
        content: message.content,
        senderId: message.senderId,
        createdAt: message.createdAt,
      );
      _conversations.removeAt(i);
      _conversations.insert(
        0,
        c.copyWith(
          lastMessage: last,
          lastMine: selfMade || message.mine,
          updatedAt: message.createdAt,
        ),
      );
      if (!selfMade && !message.mine) {
        // Incoming message from the other side → mark this conversation unread.
        _conversations[0] =
            _conversations[0].copyWith(unreadCount: c.unreadCount + 1);
      }
      return;
    }
    // Conversation not cached yet: if we know the peer, synthesize a preview
    // entry so the list is immediately coherent (the screen refreshes on
    // focus anyway).
    if (otherUser != null) {
      _conversations.insert(
        0,
        Conversation(
          id: message.conversationId,
          otherUser: otherUser,
          lastMessage: ConversationLastMessage(
            id: message.id,
            content: message.content,
            senderId: message.senderId,
            createdAt: message.createdAt,
          ),
          lastMine: message.mine,
          unreadCount: selfMade ? 0 : 1,
          updatedAt: message.createdAt,
        ),
      );
    }
  }

  /// Recomputes [_unreadConversations] from the cached conversations.
  void _recomputeUnreadBadge() {
    _unreadConversations =
        _conversations.where((c) => c.unreadCount > 0).length;
  }

  /// Clears the local conversation cache (called on logout).
  void _clearConversations() {
    _conversations.clear();
    _unreadConversations = 0;
  }

  @override
  void dispose() {
    _disposed = true;
    _chatIncoming.close();
    _friendsChanged.close();
    super.dispose();
  }
}

/// Immutable snapshot of a viewed profile: the viewed user, their posts
/// and the friendship state between the session user and [user]. Stored in
/// [AppState] keyed by lowercase nickname so the session user
/// (currentUser) and every viewed profile (viewedUser) stay isolated —
/// navigating A → B → C → A never corrupts A.
class ProfileData {
  const ProfileData({
    required this.user,
    required this.posts,
    this.friendship,
  });

  final MatrixUser user;
  final List<Post> posts;
  final Friendship? friendship;

  ProfileData copyWith({
    MatrixUser? user,
    List<Post>? posts,
    Friendship? friendship,
  }) =>
      ProfileData(
        user: user ?? this.user,
        posts: posts ?? this.posts,
        friendship: friendship ?? this.friendship,
      );
}
