import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/api_config.dart';
import '../../data/dtos/dtos.dart';
import '../../data/repositories/repositories.dart';
import '../../data/repositories/sticker_repository.dart';
import '../../data/search_history_store.dart';
import '../../data/services.dart';
import '../../models/akame_message.dart';
import '../../models/search_history_entry.dart';
import '../../models/comment.dart';
import '../../models/conversation.dart';
import '../../models/cosmetic_item.dart';
import '../../models/friend_request.dart';
import '../../models/matrix_notification.dart';
import '../../models/matrix_user.dart';
import '../../models/post.dart';
import '../../models/sticker.dart';
import '../utils/mock_data_service.dart';
import '../utils/sticker_import_validator.dart';

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
  AppState({Repositories? repositories, SearchHistoryStore? searchHistoryStore})
      : _repos = repositories,
        _searchHistoryStore = searchHistoryStore,
        _akameMessages = MockDataService.initialAkameMessages();

  final Repositories? _repos;

  /// Injected (tests) or lazily-created (production) per-user history store.
  SearchHistoryStore? _searchHistoryStore;

  List<AkameMessage> _akameMessages = [];

  /// Per-user visited-profile history ("Pesquisas recentes"), newest first.

  /// Persisted locally per session user via [SearchHistoryStore]; cleared on
  /// logout/account deletion so one account never sees another's history.v
  final List<SearchHistoryEntry> _searchHistory = [];
  bool _searchHistoryLoaded = false;

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

  // ── Stickers (figurinhas) ─────────────────────────────────
  /// The full server sticker catalog: packages + stickers + user state.
  List<StickerPackage> _stickerPackages = const [];
  bool _loadingStickerPackages = false;
  bool _stickerCatalogLoaded = false;

  /// The session user's favorites (deduped refs resolved from the server).
  List<Sticker> _stickerFavorites = const [];
  bool _loadingStickerFavorites = false;
  bool _stickerFavoritesLoaded = false;

  /// The session user's recents, newest first, deduped (server-bounded).
  List<Sticker> _stickerRecents = const [];
  bool _loadingStickerRecents = false;
  bool _stickerRecentsLoaded = false;

  /// Posts fetched individually (detail screen) that may not be present in
  /// the feed/profile caches. Lets likes/comments work uniformly by id.
  final Map<String, Post> _postCache = {};

  /// Private chat: the authenticated user's conversations (Chat tab).
  final List<Conversation> _conversations = [];

  /// Group chats:the authenticated user's groups (Chat tab, merged with DMs).
  final List<GroupConversation> _groups = [];
  bool _loadingConversations = false;

  /// Total unread conversations, shown as a badge on the 💬 Chat tab.
  int _unreadConversations = 0;

  /// Real-time incoming chat messages (from the shared WebSocket). The
  /// conversation screen listens so an open DM updates live; the Chat tab
  /// listens (while open) to refresh the list/unread badge.
  final _chatIncoming = StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get onChatIncoming => _chatIncoming.stream;

  /// Real-time peer typing signal (started/stopped) for an open conversation.
  final _chatTyping = StreamController<ChatTypingEvent>.broadcast();
  Stream<ChatTypingEvent> get onChatTyping => _chatTyping.stream;

  /// Emits when the PEER read one of my messages (lets my last bubble flip
  /// "enviado" → "visto agora" live, no reload).
  final _chatRead = StreamController<ChatReadEvent>.broadcast();
  Stream<ChatReadEvent> get onChatRead => _chatRead.stream;

  /// Real-time peer voice-recording signal (started/stopped) for an open
  /// conversation, so the "gravando áudio" hint appears/disappears live below
  /// the peer's nickname. Ephemeral, like typing — never persists.

  final _chatRecording = StreamController<ChatRecordingEvent>.broadcast();
  Stream<ChatRecordingEvent> get onChatRecording => _chatRecording.stream;

  /// Real-time group identity updates (name/avatar/description/membership)
  /// pushed by the server after an owner edit. Open conversation / profile
  /// screens refresh their header live..
  final _groupUpdated = StreamController<GroupUpdatedEvent>.broadcast();
  Stream<GroupUpdatedEvent> get onGroupUpdated => _groupUpdated.stream;

  /// Real-time signal that the session user was BANNED from a group. The
  /// server kicks them out; the app drops the group from the cache and
  /// open group screens close themselves so nothing stays stale.
  final _groupBanned = StreamController<GroupBannedEvent>.broadcast();
  Stream<GroupBannedEvent> get onGroupBanned => _groupBanned.stream;

  /// Real-time signal that the session user LOST ACCESS to a group — either
  /// the owner permanently deleted it or the user left it. Identical payload
  /// to [_groupBanned]; handled the same way (drop cache + close open
  /// screens).
  final _groupDeleted = StreamController<GroupDeletedEvent>.broadcast();
  Stream<GroupDeletedEvent> get onGroupDeleted => _groupDeleted.stream;

  /// Emits when a message in a conversation is deleted FOR EVERYONE by the
  /// peer (realtime). Open conversation screens remove the bubble live.
  final _chatMessageDeleted =
      StreamController<ChatMessageDeletedEvent>.broadcast();
  Stream<ChatMessageDeletedEvent> get onChatMessageDeleted =>
      _chatMessageDeleted.stream;

  /// Emits when a comment on a post is deleted (realtime by the post author
  /// or the comment owner). Open comments sheets / posts remove the entry live.
  final _commentDeleted = StreamController<CommentDeletedEvent>.broadcast();
  Stream<CommentDeletedEvent> get onCommentDeleted => _commentDeleted.stream;

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

  List<MatrixNotification> get notifications =>
      List.unmodifiable(_notifications);
  int get unreadNotifications => _notifications.where((n) => !n.read).length;
  bool get isLoadingNotifications => _loadingNotifications;

  /// Private chat getters.
  List<Conversation> get conversations => List.unmodifiable(_conversations);
  List<GroupConversation> get groups => List.unmodifiable(_groups);
  bool get isLoadingConversations => _loadingConversations;

  /// Per-user visited-profile history (newest first). Empty until the first
  /// [loadSearchHistory] completes — the getter is stable for the UI (no
  /// partial list while the store is being read).
  List<SearchHistoryEntry> get searchHistory =>
      _searchHistoryLoaded ? List.unmodifiable(_searchHistory) : const [];

  /// The per-user history store. Used only when the app is running with the
  /// real Services singleton (never in tests,w which inject repositories and
  /// don't initialize Services). When available it is localand kept in an
  /// instance field so repeated calls don't rebuild it.

  SearchHistoryStore? _historyStore() {
    final injected = _searchHistoryStore;
    if (injected != null) return injected;
    if (_repos != null && !Services.isInitialized) return null;
    return _searchHistoryStore ??= SearchHistoryStore();
  }

  /// Loads the session user's persisted search history (newest first.v
  void loadSearchHistory() {
    final userId = _currentUser?.id;
    if (userId == null || userId.isEmpty) return;
    unawaited(() async {
      final store = _historyStore();
      if (store == null) return;
      final entries = await store.read(userId);
      if (!_disposed) {
        _searchHistory
          ..clear()
          ..addAll(entries);
        _searchHistoryLoaded = true;
        notifyListeners();
      }
    }());
  }

  /// Registers a visited profile in the history (newest first, deduped by id.v
  /// Does nothing for the session user's own profile or for unloaded guest
  /// users (id missing.v Returns immediately — persistence is best-effort.v
  void recordProfileVisit(MatrixUser user) {
    final userId = user.id;
    if (userId.isEmpty || _currentUser == null || userId == _currentUser!.id) {
      return;
    }
    _searchHistory.removeWhere((e) => e.userId == userId);
    _searchHistory.insert(0, SearchHistoryEntry.fromUser(user));
    _searchHistoryLoaded = true;
    _persistSearchHistory();
    notifyListeners();
  }

  /// Removes one entry from the history (UI + persistence immediately,no
  /// refresh required.v
  void removeSearchHistory(String userId) {
    _searchHistory.removeWhere((e) => e.userId == userId);
    if (_searchHistoryLoaded) {
      unawaited(_persistNow());
    }
    notifyListeners();
  }

  void _persistSearchHistory() {
    if (!_searchHistoryLoaded) return;
    unawaited(_persistNow());
  }

  Future<void> _persistNow() async {
    final userId = _currentUser?.id;
    if (userId == null || userId.isEmpty) return;
    final store = _historyStore();
    if (store == null) return;
    await store.write(userId, List.of(_searchHistory));
  }

  int get unreadConversations => _unreadConversations;

  /// Cosmetics equipped by the session user (slot → item). Empty means
  /// "all defaults" — the spec's "Nenhuma" state.
  CosmeticMap get myCosmetics => Map.unmodifiable(_myCosmetics);
  bool get isLoadingCosmetics => _loadingCosmetics;

  /// The official nickname color palette (server catalog), empty until
  /// [loadNameColorCatalog] completes.
  List<CosmeticItem> get nameColorCatalog =>
      List.unmodifiable(_nameColorCatalog);

  /// The official profile frame catalog (server), empty until
  /// [loadFrameCatalog] completes.
  List<CosmeticItem> get frameCatalog => List.unmodifiable(_frameCatalog);
  bool get isLoadingFrameCatalog => _loadingFrameCatalog;

  /// The full sticker catalog (every active package with its stickers and the
  /// session user's install/favorite state). Empty until [loadStickers]
  /// completes.
  List<StickerPackage> get stickerPackages => List.unmodifiable(_stickerPackages);
  bool get isLoadingStickerPackages => _loadingStickerPackages;
  bool get isStickerCatalogLoaded => _stickerCatalogLoaded;

  /// Sticker packages the user has INSTALLED (the "Meus pacotes" set).
  List<StickerPackage> get installedStickerPackages =>
      List.unmodifiable(_stickerPackages.where((p) => p.installed));

  /// The session user's sticker favorites.
  List<Sticker> get stickerFavorites => List.unmodifiable(_stickerFavorites);
  bool get isLoadingStickerFavorites => _loadingStickerFavorites;

  /// The session user's sticker recents (newest first).
  List<Sticker> get stickerRecents =>
      _stickerRecentsLoaded ? List.unmodifiable(_stickerRecents) : const [];
  bool get isLoadingStickerRecents => _loadingStickerRecents;

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
  StickerRepository get _stickersRepo =>
      _repos?.stickers ?? Services.instance.stickers;

  /// Restores the session from a stored refresh token. Called at startup.
  /// Returns true when the user is authenticated afterwards.
  Future<bool> restoreSession() async {
    try {
      _currentUser = (await _auth.me()).toModel();
      notifyListeners();
      _syncPush();
      loadSearchHistory();
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
  Future<void> login(
      {required String nickname, required String password}) async {
    final dto = await _auth.login(nickname: nickname, password: password);
    _currentUser = dto.user.toModel();
    notifyListeners();
    _syncPush();
    loadSearchHistory();
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
    loadSearchHistory();
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
    _clearSearchHistory();
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
    _clearStickerState();
  }

  /// Clears the (per-user) sticker caches on logout/account deletion so one
  /// account never borrows another's installs/favorites/recents.
  void _clearStickerState() {
    _stickerPackages = const [];
    _stickerCatalogLoaded = false;
    _stickerFavorites = const [];
    _stickerFavoritesLoaded = false;
    _stickerRecents = const [];
    _stickerRecentsLoaded = false;
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
  /// profile grid when the viewed profile is the author's own). [imageUrl]
  /// and [videoUrl] are mutually exclusive (server validates); [thumbnailUrl]
  /// is the video cover (only for video posts).
  Future<String> createPost({
    required String text,
    String? imageUrl,
    String? videoUrl,
    String? thumbnailUrl,
  }) async {
    final post = await _postsRepo.create(
      text: text.trim(),
      imageUrl: imageUrl,
      videoUrl: videoUrl,
      thumbnailUrl: thumbnailUrl,
    );
    _posts.insert(0, post);
    // Reflect on the author's viewed profile, if loaded: posts list grows
    // and the server-side counter bumps by one (matches Part 2.3).
    final key = post.authorNickname.toLowerCase();
    final profile = _profiles[key];
    if (profile != null) {
      _profiles[key] = profile.copyWith(
        user: profile.user.copyWith(postsCount: profile.user.postsCount + 1),
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
          friendsCount:
              (profile.user.friendsCount - 1).clamp(0, 1 << 31).toInt(),
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
        user:
            profile.user.copyWith(friendsCount: profile.user.friendsCount + 1),
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
      final groupList = await _chat.groups();
      _groups
        ..clear()
        ..addAll(groupList);
    } finally {
      _loadingConversations = false;
      notifyListeners();
    }
  }

  /// Refreshes just the unread conversations badge (light — used after a
  /// real-time message arrives or the tab reopens).
  Future<void> refreshUnreadConversations() async {
    try {
      final dm = await _chat.unreadCount();
      final grp = await _chat.groupUnreadCount();
      _unreadConversations = dm + grp;
    } catch (_) {
      // Best-effort: keep the last known badge on failure.
    }
    notifyListeners();
  }

  // ── Stickers (figurinhas) ──────────────────────────────────

  /// Loads the full sticker catalog (packages + stickers + user state) into
  /// state. Idempotent-guarded per session: a second call refreshes unless
  /// a load is already in flight.
  Future<void> loadStickers() async {
    if (_loadingStickerPackages) return;
    _loadingStickerPackages = true;
    notifyListeners();
    try {
      final packages = await _stickersRepo.catalog();
      _stickerPackages = packages;
      _stickerCatalogLoaded = true;
    } catch (_) {
      // The picker shows a friendly empty/error state; a retry re-calls this.
    } finally {
      _loadingStickerPackages = false;
      notifyListeners();
    }
  }

  /// Loads the session user's sticker favorites.
  Future<void> loadStickerFavorites() async {
    if (_loadingStickerFavorites) return;
    _loadingStickerFavorites = true;
    notifyListeners();
    try {
      _stickerFavorites = await _stickersRepo.favorites();
      _stickerFavoritesLoaded = true;
    } catch (_) {
      // Keep last known favorites on failure.
    } finally {
      _loadingStickerFavorites = false;
      notifyListeners();
    }
  }

  /// Loads the session user's sticker recents.
  Future<void> loadStickerRecents() async {
    if (_loadingStickerRecents) return;
    _loadingStickerRecents = true;
    notifyListeners();
    try {
      _stickerRecents = await _stickersRepo.recents();
      _stickerRecentsLoaded = true;
    } catch (_) {
      // Keep last known recents on failure.
    } finally {
      _loadingStickerRecents = false;
      notifyListeners();
    }
  }

  /// Favorites a sticker locally + on the server, then refreshes every
  /// surface that renders its state (catalog + favorites list).
  Future<void> favoriteSticker(String stickerId) async {
    try {
      await _stickersRepo.favorite(stickerId);
    } catch (_) {
      // Best-effort: the next full reload reconciles with the server.
    }
    _applyStickerFavorite(stickerId, true);
  }

  /// Removes a favorite locally + on the server.
  Future<void> unfavoriteSticker(String stickerId) async {
    try {
      await _stickersRepo.unfavorite(stickerId);
    } catch (_) {
      // Best-effort.
    }
    _applyStickerFavorite(stickerId, false);
  }

  /// Updates every sticker cache (package grids + favorites list) to reflect
  /// the new favorite state of [stickerId] — single point of truth.
  void _applyStickerFavorite(String stickerId, bool favorited) {
    _stickerPackages = _stickerPackages.map((p) {
      if (p.stickers.every((s) => s.id != stickerId)) return p;
      return p.copyWith(
        installed: p.installed,
      ).replaceSticker(
        stickerId,
        (s) => s.copyWith(favorited: favorited),
      );
    }).toList();
    _stickerRecents = _stickerRecents
        .map((s) => s.id == stickerId ? s.copyWith(favorited: favorited) : s)
        .toList();
    if (favorited) {
      final existing = _stickerFavorites;
      if (existing.every((s) => s.id != stickerId)) {
        // Find the sticker in the catalog to preserve full metadata.
        final source = _stickerInCatalog(stickerId);
        _stickerFavorites = source == null
            ? existing
            : [source.copyWith(favorited: true), ...existing];
      }
    } else {
      _stickerFavorites =
          _stickerFavorites.where((s) => s.id != stickerId).toList();
    }
    if (!_stickerFavoritesLoaded) _stickerFavoritesLoaded = true;
    notifyListeners();
  }

  Sticker? _stickerInCatalog(String stickerId) {
    for (final p in _stickerPackages) {
      for (final s in p.stickers) {
        if (s.id == stickerId) return s;
      }
    }
    for (final s in _stickerFavorites) {
      if (s.id == stickerId) return s;
    }
    return null;
  }

  /// Whether [stickerId] is currently in the session user's favorites.
  /// Single source of truth for the UI (picker + chat message menu) — reads
  /// the loaded favorites list, never a duplicated local flag.
  bool isStickerFavorited(String? stickerId) {
    if (stickerId == null || stickerId.isEmpty) return false;
    return _stickerFavorites.any((s) => s.id == stickerId);
  }

  /// Installs a sticker package locally + on the server and refreshes the
  /// catalog state so the picker navigates into it immediately.
  Future<void> installStickerPackage(String packageId) async {
    try {
      await _stickersRepo.install(packageId);
    } catch (_) {
      // Best-effort: server remains the source of truth on next reload.
    }
    _stickerPackages = _stickerPackages
        .map((p) => p.id == packageId ? p.copyWith(installed: true) : p)
        .toList();
    notifyListeners();
  }

  /// Removes a sticker package locally + on the server. Favorites/history
  /// keep rendering — only the picker package tab disappears.
  Future<void> uninstallStickerPackage(String packageId) async {
    try {
      await _stickersRepo.uninstall(packageId);
    } catch (_) {
      // Best-effort.
    }
    _stickerPackages = _stickerPackages
        .map((p) => p.id == packageId ? p.copyWith(installed: false) : p)
        .toList();
    notifyListeners();
  }

  /// DELETES a package the session user owns (imported from share/Sticker.ly)
  /// and drops it from the local catalog immediately, so the picker updates
  /// without a reload. The server preserves the user's favorited stickers as
  /// standalone copies — the favorites/recents lists are refreshed after.
  ///
  /// Throws [ApiException] on failure (e.g. 403 for a non-owned package) so
  /// the UI can show a clear message and keep the package.
  Future<int> deleteStickerPackage(String packageId) async {
    final preserved = await _stickersRepo.deletePackage(packageId);
    _stickerPackages =
        _stickerPackages.where((p) => p.id != packageId).toList();
    notifyListeners();
    if (preserved > 0) {
      await loadStickerFavorites();
      await loadStickerRecents();
    }
    return preserved;
  }

  /// Moves a sticker to the FRONT of the session user's recents (deduped).
  /// Persistence is server-side (registered automatically on send); this
  /// just keeps the local picker in sync without waiting for a reload.
  void _bumpStickerRecent(String stickerId) {
    final source = _stickerInCatalog(stickerId);
    if (source == null) return;
    _stickerRecents = [
      source.copyWith(favorited: source.favorited),
      ..._stickerRecents.where((s) => s.id != stickerId),
    ];
    _stickerRecentsLoaded = true;
    // best-effort server sync (idempotent):
    _stickersRepo.markRecent(stickerId).catchError((_) {});
  }

  /// Importa figuritas recibidas por el compartir nativo de Android.
  ///
  /// Cada archivo validado se sube por el sistema de uploads EXISTENTE y se
  /// crea un paquete del usuario vía la API de stickers (misma persistencia).
  /// Devuelve cuántas se crearon y cuántas se omitieron (dedupe por hash).
  Future<({int created, int skipped})> importSharedStickers({
    required String name,
    required List<ValidatedStickerFile> stickers,
  }) async {
    final uploads = _repos?.uploads ?? Services.instance.uploads;
    final items = <Map<String, dynamic>>[];
    for (final s in stickers) {
      // Declara el MIME/extension REALES validados por magic bytes
      // (png/webp/jpeg): el servidor rechaza uploads cuyo Content-Type o
      // extensión no esté permitido (un temp sin extensión llegaría como
      // application/octet-stream).
      final (contentType, ext) = switch (s.kind) {
        StickerImageKind.png => ('image/png', 'png'),
        StickerImageKind.webp => ('image/webp', 'webp'),
        StickerImageKind.jpeg => ('image/jpeg', 'jpg'),
      };
      final url = await uploads.upload(
        s.file,
        contentType: contentType,
        filename: 'sticker.$ext',
      );
      items.add({
        'url': url,
        'hash': s.sha256,
        'width': s.width,
        'height': s.height,
      });
    }
    final result = await _stickersRepo.importPackage(name, items);
    // Refresca catálogo/instalados para que el paquete nuevo aparezca.
    await loadStickers();
    return result;
  }

  /// Prévia de um pacote do Sticker.ly (código ou link). Não altera nada —
  /// apenas consulta o SERVIDOR, que é quem fala com a fonte externa (o APK
  /// nunca carrega credenciais nem chama o Sticker.ly direto).
  Future<StickerlyPackPreview> previewStickerlyPack(String code) {
    return _stickersRepo.stickerlyPreview(code);
  }

  /// Importa um pacote do Sticker.ly para a coleção do usuário. Reimportar o
  /// mesmo código não duplica (dedupe no servidor por origem/hash).
  Future<({StickerPackage? package, int created, int skipped, bool already})>
      importStickerlyPack(String code) async {
    final result = await _stickersRepo.stickerlyImport(code);
    // Refresca catálogo/instalados para o pacote aparecer no painel.
    await loadStickers();
    return result;
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

  /// Latest messages of a group (same paginated, chronological shape as
  /// private chat — with the real sender embedded in each bubble).
  Future<({List<ChatMessage> messages, bool hasMore})> loadGroupMessages(
    String groupId, {
    String? before,
    int limit = 30,
  }) {
    return _chat.groupMessages(groupId, before: before, limit: limit);
  }

  /// Creates a group on the server (name required; description/foto optional;
  /// participants selected by the user — friends only, enforced server-side).
  /// The creator is added as OWNER automatically by the server. The returned
  /// group is inserted into the cached list immediately so it shows up in the
  /// Chat tab without a refetch.

  /// Full group info (profile menu.: identity + member list with owner flag).
  /// The group header is ALSO upserted into the local groups cache so an
  /// open conversation header reflects the persisted identity immediately..
  Future<
      ({
        GroupHeader group,
        List<GroupMemberInfoModel> members,
        List<GroupMemberInfoModel> bannedMembers,
      })> fetchGroupInfo(
    String groupId,
  ) async {
    final info = await _chat.groupInfo(groupId);
    final idx = _groups.indexWhere((g) => g.id == groupId);
    if (idx != -1) {
      _groups[idx] = _groups[idx].copyWith(group: info.group);
    }
    notifyListeners();
    return info;
  }

  Future<GroupConversation> createGroup({
    required String name,
    String description = '',
    String? avatarUrl,
    List<String> participantIds = const [],
  }) async {
    final group = await _chat.createGroup(
      name: name,
      description: description,
      avatarUrl: avatarUrl,
      participantIds: participantIds,
    );
    _groups
      ..removeWhere((g) => g.id == group.id)
      ..insert(0, group);
    _recomputeUnreadBadge();
    notifyListeners();
    return group;
  }

  /// Owner-only identity edit (name/description). Server returns the fresh
  /// header;we upsert it into the cached group list so the Chat tab preview
  /// and any open conversation AppBar update immediately.

  Future<GroupHeader> updateGroup(
    String groupId, {
    String? name,
    String? description,
  }) async {
    final header = await _chat.updateGroup(
      groupId,
      name: name,
      description: description,
    );
    _upsertGroupHeader(header);
    notifyListeners();
    return header;
  }

  /// Owner-only group avatar replacement (image already uploaded). Same
  /// cached-header refresh as [updateGroup]..
  Future<GroupHeader> updateGroupAvatar(
    String groupId,
    String avatarUrl,
  ) async {
    final header = await _chat.updateGroupAvatar(groupId, avatarUrl);
    _upsertGroupHeader(header);
    notifyListeners();
    return header;
  }

  /// Owner-only member addition. Refreshes the caller's cached group item
  /// (the server response embeds the fresh member count).
  Future<void> addGroupMember(
    String groupId,
    String newUserId,
  ) async {
    final group = await _chat.addGroupMember(groupId, newUserId);
    final idx = _groups.indexWhere((g) => g.id == group.id);
    if (idx != -1) _groups[idx] = group;
    notifyListeners();
  }

  /// Owner-only member removal (ban feature). Refreshes the caller's cached group
  /// item (the server response embeds the fresh member count). Returns true on
  /// success (the server re-validates owner permission and rejects banning the
  /// OWNER — forge-proof).
  Future<bool> banGroupMember(String groupId, String userId) async {
    try {
      final group = await _chat.banGroupMember(groupId, userId);
      final idx = _groups.indexWhere((g) => g.id == group.id);
      if (idx != -1) _groups[idx] = group;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Owner-only member unban. Refreshes the caller's cached group item (the
  /// server response embeds the fresh member count). Returns true on success
  /// (the server re-validates owner permission and the banned state).
  Future<bool> unbanGroupMember(String groupId, String userId) async {
    try {
      final group = await _chat.unbanGroupMember(groupId, userId);
      final idx = _groups.indexWhere((g) => g.id == group.id);
      if (idx != -1) _groups[idx] = group;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Replaces the cached group header fora single group (used by admin edits).
  void _upsertGroupHeader(GroupHeader header) {
    final idx = _groups.indexWhere((g) => g.id == header.id);
    if (idx == -1) return;
    _groups[idx] = _groups[idx].copyWith(group: header);
  }

  /// Sends a chat message and, on success, optimistically records it in the
  /// cached conversation's last-message slot (the server response is
  /// authoritative and returned for the screen to append). [replyToMessageId]
  /// (optional) makes it a reply to an existing message of the conversation.
  Future<ChatMessage> sendChatMessage(
    String conversationId,
    String content, {
    ChatUser? otherUser,
    String? replyToMessageId,
  }) async {
    final message = await _chat.send(conversationId, content,
        replyToMessageId: replyToMessageId);
    _applyChatMessage(message, otherUser: otherUser ?? _peerOf(conversationId));
    // Wake the Chat tab synchronously so its preview shows the sent message
    // immediately — no need to wait for a tab switch or a full refetch.
    notifyListeners();
    return message;
  }

  /// Sends a MEDIA message (image/video) to a private conversation and
  /// updates the cached last-message preview (same flow as chat text/voice).
  Future<ChatMessage> sendMediaMessage(
    String conversationId, {
    required String kind,
    required String url,
    String? replyToMessageId,
    ChatUser? otherUser,
  }) async {
    final message = await _chat.sendMedia(
      conversationId,
      kind: kind,
      url: url,
      replyToMessageId: replyToMessageId,
    );
    _applyChatMessage(message, otherUser: otherUser ?? _peerOf(conversationId));
    notifyListeners();
    return message;
  }

  /// Sends a GROUP media message (image/video) and updates the cached group
  /// preview (same flow as group text/voice).
  Future<ChatMessage> sendGroupMediaMessage(
    String groupId, {
    required String kind,
    required String url,
    String? replyToMessageId,
  }) async {
    final message = await _chat.sendGroupMedia(
      groupId,
      kind: kind,
      url: url,
      replyToMessageId: replyToMessageId,
    );
    _applyChatMessage(message);
    notifyListeners();
    return message;
  }

  /// Sends a recorded VOICE message and (like [sendChatMessage]) updates the
  /// cached conversation's last-message slot with the server's authoritative
  /// response so the list preview ("🎤 Áudio") updates immediately.
  Future<ChatMessage> sendVoiceMessage(
    String conversationId,
    File audioFile, {
    required int durationMs,
    ChatUser? otherUser,
    String? replyToMessageId,
  }) async {
    final message = await _chat.sendVoice(
      conversationId,
      audioFile,
      durationMs: durationMs,
      replyToMessageId: replyToMessageId,
    );
    _applyChatMessage(message, otherUser: otherUser ?? _peerOf(conversationId));
    // Same synchronous wake-up as [sendChatMessage]: the audio preview
    // must appear on the list without waiting for a refetch.
    notifyListeners();
    return message;
  }

  /// Sends a STICKER message to a private conversation and updates the cached
  /// preview + the sender's recent sticker list (same flow as text/voice).
  Future<ChatMessage> sendStickerMessage(
    String conversationId, {
    required String stickerId,
    ChatUser? otherUser,
    String? replyToMessageId,
  }) async {
    final message = await _chat.sendSticker(
      conversationId,
      stickerId,
      replyToMessageId: replyToMessageId,
    );
    _applyChatMessage(message, otherUser: otherUser ?? _peerOf(conversationId));
    _bumpStickerRecent(stickerId);
    notifyListeners();
    return message;
  }

  /// Sends a STICKER message to a GROUP (same flow as [sendStickerMessage]).
  Future<ChatMessage> sendGroupStickerMessage(
    String groupId, {
    required String stickerId,
    String? replyToMessageId,
  }) async {
    final message = await _chat.sendGroupSticker(
      groupId,
      stickerId,
      replyToMessageId: replyToMessageId,
    );
    _applyChatMessage(message);
    _bumpStickerRecent(stickerId);
    notifyListeners();
    return message;
  }

  /// Signals the peer that the session user is (or stopped) typing. Ephemeral
  void sendTyping(String conversationId, bool typing) {
    _chat.setTyping(conversationId, typing);
  }

  /// and best-effort — the UI calls it from the composer's onChange.

  /// Sends a GROUP message and, on success, optimistically records it in the
  /// cached group's last-message slot (the server's response is authoritative).
  /// [mentions] are RANGE-ANCHORED mention references (the only mentions the
  /// server accepts — never derived from raw text). Legacy [mentionUserIds] /
  /// [mentionAll] remain as a fallback pipe.
  Future<ChatMessage> sendGroupChatMessage(
    String groupId,
    String content, {
    String? replyToMessageId,
    List<ChatMention> mentions = const [],
    List<String> mentionUserIds = const [],
    bool mentionAll = false,
  }) async {
    final message = await _chat.sendGroupMessage(groupId, content,
        replyToMessageId: replyToMessageId,
        mentions: mentions,
        mentionUserIds: mentionUserIds,
        mentionAll: mentionAll);
    _applyChatMessage(message);
    notifyListeners();
    return message;
  }

  /// Visto/Enviado — who already read a group message and who hasn't (the
  /// full breakdown is only returned to the sender; others get their own
  /// state). Used by the long-press "Visto/Enviado" panel.
  Future<({List<ChatUser> read, List<ChatUser> unread})> groupMessageReaders(
    String groupId,
    String messageId,
  ) {
    return _chat.groupMessageReaders(groupId, messageId);
  }

  /// Sends a recorded VOICE message to a GROUP (same rules as DMs).
  Future<ChatMessage> sendGroupVoiceMessage(
    String groupId,
    File audioFile, {
    required int durationMs,
    String? replyToMessageId,
  }) async {
    final message = await _chat.sendGroupVoiceMessage(
      groupId,
      audioFile,
      durationMs: durationMs,
      replyToMessageId: replyToMessageId,
    );
    _applyChatMessage(message);
    notifyListeners();
    return message;
  }

  /// Signals the other members that the session user is (or stopped) typing in
  /// a group. Ephemeral + best-effort.

  void sendGroupTyping(String groupId, bool typing) {
    _chat.setGroupTyping(groupId, typing);
  }

  /// A real-time `chat_typing` frame arrived → forward to open conversations.

  void handleIncomingChatTyping(ChatTypingEvent event) {
    if (_disposed) return;
    if (!_chatTyping.isClosed) _chatTyping.add(event);
  }

  /// Signals the peer that the session user is (or stopped) recording a voice

  /// message. Ephemeral + best-effort, like [sendTyping].

  void sendRecording(String conversationId, bool recording) {
    _chat.setRecording(conversationId, recording);
  }

  /// Signals the other members that the session user is (or stopped) recording a
  /// voice message in a group. Ephemeral + best-effort.

  void sendGroupRecording(String groupId, bool recording) {
    _chat.setGroupRecording(groupId, recording);
  }

  /// A real-time `chat_read` frame arrived → the peer read my messages. Flip
  /// readAt on MY last sent message in that conversation (local cache +
  /// open screens) so "enviado" → "visto agora" updates live.
  void handleIncomingChatRead(ChatReadEvent event) {
    if (_disposed) return;
    if (!_chatRead.isClosed) _chatRead.add(event);
  }

  /// A real-time `chat_recording` frame arrived → forward to open conversations
  /// so the "gravando áudio" hint under the peer's nickname updates live.
  void handleIncomingChatRecording(ChatRecordingEvent event) {
    if (_disposed) return;
    if (!_chatRecording.isClosed) _chatRecording.add(event);
    notifyListeners();
  }

  /// A real-time `chat_message_deleted` frame arrived → the peer removed a
  /// message for everyone. The conversation screen removes the bubble; the
  /// Chat tab refreshes its preview. Cached conversation last-preview is
  /// recomputed lazily on the next list load.
  void handleIncomingChatMessageDeleted(ChatMessageDeletedEvent event) {
    if (_disposed) return;
    if (!_chatMessageDeleted.isClosed) _chatMessageDeleted.add(event);
    notifyListeners();
  }

  /// A real-time `chat_group_updated` frame arrived → a group's identity
  /// (name/avatar/description/members) was edited by the owner. Refresh
  /// the cached list header and forward the event so an open conversation
  /// AppBar / group profile menu updates live.

  void handleIncomingGroupUpdated(GroupUpdatedEvent event) {
    if (_disposed) return;
    if (event.groupId.isEmpty) return;
    final idx = _groups.indexWhere((g) => g.id == event.groupId);
    if (idx != -1) _groups[idx] = _groups[idx].copyWith(group: event.group);
    if (!_groupUpdated.isClosed) _groupUpdated.add(event);
    notifyListeners();
  }

  /// A real-time `chat_group_banned` frame arrived → the session user was
  /// removed from a group. Drop the group from the local cache, recompute
  /// the unread badge, and notify open group screens so they close.
  void handleIncomingGroupBanned(GroupBannedEvent event) {
    if (_disposed) return;
    if (event.groupId.isEmpty) return;
    _groups.removeWhere((g) => g.id == event.groupId);
    _recomputeUnreadBadge();
    if (!_groupBanned.isClosed) _groupBanned.add(event);
    notifyListeners();
  }

  /// A real-time `chat_group_deleted` frame arrived → the session user lost
  /// access to a group (owner deleted it permanently or the user left).
  /// Drop the group from the local cache, recompute the unread badge and
  /// notify open group screens so they close — same semantics as a ban.
  void handleIncomingGroupDeleted(GroupDeletedEvent event) {
    if (_disposed) return;
    if (event.groupId.isEmpty) return;
    _groups.removeWhere((g) => g.id == event.groupId);
    _recomputeUnreadBadge();
    if (!_groupDeleted.isClosed) _groupDeleted.add(event);
    notifyListeners();
  }

  /// A real-time `comment_deleted` frame arrived → a comment was removed
  /// (by its owner or the post author). Open comment surfaces subscribe to
  /// [onCommentDeleted] to remove it live.
  void handleIncomingCommentDeleted(CommentDeletedEvent event) {
    if (_disposed) return;
    if (!_commentDeleted.isClosed) _commentDeleted.add(event);
    // Decrement the cached post comment count if we have it.
    final post = _findPost(event.postId);
    if (post != null && post.commentCount > 0) {
      post.commentCount -= 1;
      notifyListeners();
    }
  }

  /// Excluir comentário — server-enforced: allowed only for the comment's
  /// author or the post author. Returns true on success.
  Future<bool> deleteComment(String commentId, {required String postId}) async {
    try {
      await _comments.delete(commentId);
      final post = _findPost(postId);
      if (post != null && post.commentCount > 0) {
        post.commentCount -= 1;
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// "Excluir mensagem para mim" — server-persisted (survives restarts).
  /// The open conversation screen removes the bubble locally after success.
  Future<bool> deleteChatMessageForMe(
      String conversationId, String messageId) async {
    try {
      await _chat.deleteMessageForMe(conversationId, messageId);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// "Excluir mensagem para todos" — server-authoritative; on success the
  /// open conversation screen removes the bubble and we refresh the cached
  /// conversation preview (the last visible message may have changed).
  Future<bool> deleteChatMessageForEveryone(
    String conversationId,
    String messageId,
  ) async {
    try {
      await _chat.deleteMessageForEveryone(conversationId, messageId);
      // Re-fetch the conversation preview lazily (best-effort) so the Chat
      // tab's last-message reflects the deletion.
      unawaited(_refreshConversationPreview(conversationId));
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// "Excluir mensagem para mim" (group — same hide semantics as DMs).
  Future<bool> deleteGroupMessageForMe(String groupId, String messageId) async {
    try {
      await _chat.deleteGroupMessageForMe(groupId, messageId);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// "Excluir mensagem para todos" (group — server-authoritative; the other
  /// members get a realtime `chat_message_deleted` frame wired to this app).
  Future<bool> deleteGroupMessageForEveryone(
    String groupId,
    String messageId,
  ) async {
    try {
      await _chat.deleteGroupMessageForEveryone(groupId, messageId);
      unawaited(_refreshGroupPreview(groupId));
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Best-effort refresh of a cached group's last-visible-message preview
  /// after a "delete for everyone" so the Chat tab stays in sync.

  Future<void> _refreshGroupPreview(String groupId) async {
    try {
      final idx = _groups.indexWhere((g) => g.id == groupId);
      if (idx == -1) return;
      final page = await _chat.groupMessages(groupId, limit: 1);
      final last = page.messages.isNotEmpty ? page.messages.last : null;
      final g = _groups[idx];
      _groups[idx] = g.copyWith(
        lastMessage: last == null
            ? null
            : ConversationLastMessage(
                id: last.id,
                content: last.content,
                senderId: last.senderId,
                senderNickname: last.sender?.nickname,
                createdAt: last.createdAt,
              ),
        lastMine: last?.senderId == _currentUser?.id,
      );
      notifyListeners();
    } catch (_) {
      // Best-effort:the next list load refreshes it anyway.
    }
  }

  /// "Excluir conversa para mim" — removes the conversation from the local
  /// list immediately (server persists the hide). Returns true on success.
  Future<bool> hideConversation(String conversationId) async {
    try {
      await _chat.hideConversation(conversationId);
      _conversations.removeWhere((c) => c.id == conversationId);
      _recomputeUnreadBadge();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Best-effort refresh of a cached conversation's last-visible-message
  /// preview after a "delete for everyone" so the Chat tab stays in sync.
  Future<void> _refreshConversationPreview(String conversationId) async {
    try {
      final idx = _conversations.indexWhere((c) => c.id == conversationId);
      if (idx == -1) return;
      final page = await _chat.messages(conversationId, limit: 1);
      final last = page.messages.isNotEmpty ? page.messages.last : null;
      final c = _conversations[idx];
      _conversations[idx] = c.copyWith(
        lastMessage: last == null
            ? null
            : ConversationLastMessage(
                id: last.id,
                content: last.content,
                senderId: last.senderId,
                createdAt: last.createdAt,
              ),
        lastMine: last?.senderId == _currentUser?.id,
      );
      notifyListeners();
    } catch (_) {
      // Best-effort: the next list load refreshes it anyway.
    }
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

  /// Marks a GROUP as read by the session user and clears its unread badge from
  /// the local cache. Server clears the per-member unread counter too.)
  Future<void> markGroupRead(String groupId) async {
    try {
      await _chat.markGroupRead(groupId);
    } catch (_) {
      // Best-effort: reading is not fatal.
    }
    var modified = false;
    for (var i = 0; i < _groups.length; i++) {
      if (_groups[i].id == groupId && _groups[i].unreadCount > 0) {
        final g = _groups[i];
        _groups[i] = g.copyWith(unreadCount: 0);
        modified = true;
      }
    }
    if (modified) _recomputeUnreadBadge();
    notifyListeners();
  }

  /// "Sair do grupo" — removes the group from the local list immediately and
  /// tells server this member wants chat hidden(non-destructive leave;the
  /// server keeps the membership so re-invites/re-adds just resurface it).
  Future<bool> hideGroup(String groupId) async {
    try {
      await _chat.hideGroup(groupId);
      _groups.removeWhere((g) => g.id == groupId);
      _recomputeUnreadBadge();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// PERMANENTLY deletes a group (owner-only; the server re-validates).
  /// The server removes the group + all related rows in one transaction and
  /// broadcasts `chat_group_deleted` to every participant; on success the
  /// local cache drops the group immediately (the realtime frame covers the
  /// other devices).
  Future<bool> deleteGroup(String groupId) async {
    try {
      await _chat.deleteGroup(groupId);
      _groups.removeWhere((g) => g.id == groupId);
      _recomputeUnreadBadge();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// SAIR DO GRUPO — removes the SESSION user from the group (member-only;
  /// the server rejects the owner so the group never ends up ownerless).
  /// The group keeps existing for the other members. On success the local
  /// cache drops the group and open group screens close themselves.
  Future<bool> leaveGroup(String groupId) async {
    try {
      await _chat.leaveGroup(groupId);
      _groups.removeWhere((g) => g.id == groupId);
      _recomputeUnreadBadge();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A real-time chat message arrived on the WebSocket. If it belongs to a
  /// conversation we have cached, update that conversation (last message +
  /// unread badge); the peer (needed for the preview) is the message sender
  /// when we don't already know it.
  ///
  /// Routes the message into the cached conversation preview so the
  /// conversations list updates immediately. When the conversation isn't
  /// cached yet, [peer] (the sender's ChatUser from the realtime payload)
  /// lets us synthesize a coherent entry with the sender's real avatar —
  /// otherwise the list refreshes on focus anyway.
  /// Emits on [onChatIncoming] for open conversation screens.
  void handleIncomingChatMessage(ChatMessage message, {ChatUser? peer}) {
    if (_disposed) return;
    final groupId = message.groupId;
    if (groupId != null) {
      // Group message: route into the cached group list (if cached) as the
      // sender badge is derived from `lastMine` (the sender is never "me" for
      // an incoming realtime frame — sina self-made is implicit below).
      final gidx = _groups.indexWhere((g) => g.id == groupId);
      if (gidx != -1) {
        _applyGroupMessage(message);
      } else {
        // Group not cached (e.g. app booted into the chat tab without opening
        // the chat list): refresh the group list lazily so it appears, and let
        // the next focus refetch fix the badge.
        unawaited(loadConversations());
      }
      if (!_chatIncoming.isClosed) _chatIncoming.add(message);
      notifyListeners();
      return;
    }
    final cached =
        _conversations.indexWhere((c) => c.id == message.conversationId!);
    if (cached != -1) {
      final other = peer ?? _peerOf(message.conversationId!);
      _applyChatMessage(message, otherUser: other, selfMade: false);
    } else if (peer != null) {
      _applyChatMessage(message, otherUser: peer, selfMade: false);
    }
    if (!_chatIncoming.isClosed) _chatIncoming.add(message);
    notifyListeners();
  }

  /// Applies a GROUP message to the cached group's last-message slot and
  /// bumps its unread badge when the message isn't ours (realtime frames are
  /// never ours but self-sends arrive through [sendGroupChatMessage] already).
  void _applyGroupMessage(ChatMessage message) {
    for (var i = 0; i < _groups.length; i++) {
      if (_groups[i].id != message.groupId) continue;
      final g = _groups[i];
      final last = ConversationLastMessage(
        id: message.id,
        content: message.content,
        senderId: message.senderId,
        createdAt: message.createdAt,
        senderNickname: message.sender?.nickname,
      );
      _groups.removeAt(i);
      _groups.insert(
        0,
        g.copyWith(
          lastMessage: last,
          lastMine: message.mine,
          unreadCount: message.mine ? g.unreadCount : g.unreadCount + 1,
          updatedAt: message.createdAt,
        ),
      );
      _recomputeUnreadBadge();
      return;
    }
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
      _recomputeUnreadBadge();
      return;
    }
    // Conversation not cached yet: if we know the peer, synthesize a preview
    // entry so the list is immediately coherent (the screen refreshes on
    // focus anyway).
    if (otherUser != null) {
      _conversations.insert(
        0,
        Conversation(
          id: message.conversationId!,
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
      _recomputeUnreadBadge();
    }
  }

  /// Recomputes [_unreadConversations] from the cached conversations.
  void _recomputeUnreadBadge() {
    _unreadConversations =
        _conversations.where((c) => c.unreadCount > 0).length +
            _groups.where((g) => g.unreadCount > 0).length;
  }

  /// Clears the local conversation cache (called on logout).
  void _clearConversations() {
    _conversations.clear();
    _groups.clear();
    _unreadConversations = 0;
  }

  /// Clears the session user's search history (local only — the server has no
  /// concept of it.v Called from logout / account deletion so accounts never
  /// borrow each other's history.v
  void _clearSearchHistory() {
    _searchHistory.clear();
    _searchHistoryLoaded = false;
    final userId = _currentUser?.id;
    final store = _historyStore();
    _searchHistoryStore = null;
    if (userId != null && userId.isNotEmpty && store != null) {
      unawaited(store.clear(userId));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _chatIncoming.close();
    _chatTyping.close();
    _chatRecording.close();
    _chatRead.close();
    _chatMessageDeleted.close();
    _groupUpdated.close();
    _groupBanned.close();
    _commentDeleted.close();
    _friendsChanged.close();
    super.dispose();
  }
}

/// A realtime peer-recording signal for a conversation (voice capture active).
class ChatRecordingEvent {
  const ChatRecordingEvent({
    this.conversationId,
    this.groupId,
    this.userId,
    this.nickname,
    required this.recording,
  });
  final String? conversationId;
  final String? groupId;
  final String? userId;
  final String? nickname;
  final bool recording;

  String get chatId => groupId ?? conversationId ?? '';
}

/// A realtime peer-typing signal for a conversation (or a group).
class ChatTypingEvent {
  const ChatTypingEvent({
    this.conversationId,
    this.groupId,
    this.userId,
    this.nickname,
    required this.typing,
  });
  final String? conversationId;
  final String? groupId;
  final String? userId;
  final String? nickname;
  final bool typing;

  String get chatId => groupId ?? conversationId ?? '';
}

/// A realtime signal that the PEER read this conversation's messages (DMs:
/// a peer read my messages; groups: a member opened the group, clearing
/// their unread state). Either identifier may be present — DMs carry
/// [conversationId], groups carry [groupId].
class ChatReadEvent {
  const ChatReadEvent({
    this.conversationId,
    this.groupId,
    this.userId,
    this.messageIds = const [],
  });
  final String? conversationId;
  final String? groupId;

  /// Group read receipts: WHO read and WHICH messages (powers the live
  /// "Visto/Enviado" panel). Null for DMs.
  final String? userId;
  final List<String> messageIds;

  String get chatId => groupId ?? conversationId ?? '';
}

/// A realtime signal that a message was deleted FOR EVERYONE by the peer
/// (DM or group, identified by the nullable fields).
class ChatMessageDeletedEvent {
  const ChatMessageDeletedEvent({
    this.conversationId,
    this.groupId,
    required this.messageId,
  });
  final String? conversationId;
  final String? groupId;
  final String messageId;
}

/// A realtime signal that the session user was BANNED from a group. Carries
/// the group id + name so the UI can show a meaningful message and kick the
/// user out of every open surface for that group.
class GroupBannedEvent {
  const GroupBannedEvent({required this.groupId, required this.groupName});
  final String groupId;
  final String groupName;
}

/// A realtime signal that the session user LOST ACCESS to a group — either
/// the owner permanently deleted it or the user left it. The app drops the
/// group from the cache and open group screens close themselves.
class GroupDeletedEvent {
  const GroupDeletedEvent({required this.groupId, required this.groupName});
  final String groupId;
  final String groupName;
}

/// A realtime signal that a comment was deleted (by its owner or the post
/// author), so open comments sheets remove it.
class CommentDeletedEvent {
  const CommentDeletedEvent({required this.postId, required this.commentId});
  final String postId;
  final String commentId;
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
