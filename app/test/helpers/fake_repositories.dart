import 'dart:io';

import 'package:matrix_app/data/api_config.dart';
import 'package:matrix_app/data/dtos/dtos.dart';
import 'package:matrix_app/data/repositories/repositories.dart';
import 'package:matrix_app/data/repositories/sticker_repository.dart';
import 'package:matrix_app/data/repositories/story_repository.dart';
import 'package:matrix_app/models/comment.dart';
import 'package:matrix_app/models/conversation.dart';
import 'package:matrix_app/models/cosmetic_item.dart';
import 'package:matrix_app/models/friend_request.dart';
import 'package:matrix_app/models/matrix_notification.dart';
import 'package:matrix_app/models/matrix_user.dart';
import 'package:matrix_app/models/post.dart';
import 'package:matrix_app/models/sticker.dart';
import 'package:matrix_app/models/story.dart';

/// In-memory fake repositories for widget/unit tests.
///
/// Each fake `implements` the real repository interface, so [AppState]
/// exercises its real optimistic-update / caching logic against data that
/// lives in memory — no network, no platform storage. Data is seeded
/// deterministically so tests are reproducible.
class FakeRepositories extends Repositories {
  FakeRepositories._({
    required FakeStore store,
    required super.auth,
    required super.posts,
    required super.likes,
    required super.comments,
    required super.users,
    required super.friends,
    required super.notifications,
    required super.uploads,
    required super.customization,
    required super.chat,
    required super.stickers,
    required super.stories,
  }) : _store = store;

  factory FakeRepositories({
    bool failLikes = false,
    Map<String, List<Comment>> seedComments = const {},
    Map<String, List<Comment>> seedReplies = const {},
    Set<String> seedLikedCommentIds = const {},
    List<MatrixNotification> seedNotifications = const [],
    Map<String, CosmeticItem> seedEquippedCosmetics = const {},
    List<CosmeticItem> seedCatalog = const [],
    List<StickerPackage> seedStickerPackages = const [],
    List<Sticker> seedStickerFavorites = const [],
    List<Sticker> seedStickerRecents = const [],
    List<StoryGroup> seedStoryGroups = const [],
  }) {
    final store = FakeStore();
    seedComments.forEach((postId, comments) {
      store.commentsByPost[postId] = List.of(comments);
    });
    seedReplies.forEach((parentId, replies) {
      store.repliesByParent[parentId] = List.of(replies);
    });
    store.likedCommentIds.addAll(seedLikedCommentIds);
    store.notifications.addAll(seedNotifications);
    store.equippedCosmetics.addAll(seedEquippedCosmetics);
    store.catalog.addAll(seedCatalog);
    store.stickerPackages.addAll(seedStickerPackages);
    store.stickerFavorites.addAll(seedStickerFavorites);
    store.stickerRecents.addAll(seedStickerRecents);
    store.storyGroups.addAll(seedStoryGroups);
    return FakeRepositories._(
      store: store,
      auth: _FakeAuthRepository(store),
      posts: _FakePostRepository(store),
      likes: _FakeLikeRepository(store, fail: failLikes),
      comments: _FakeCommentRepository(store),
      users: _FakeUserRepository(store),
      friends: _FakeFriendRepository(store),
      notifications: _FakeNotificationRepository(store),
      uploads: const _FakeUploadRepository(),
      customization: _FakeCustomizationRepository(store),
      chat: _FakeChatRepository(store),
      stickers: _FakeStickerRepository(store),
      stories: _FakeStoryRepository(store),
    );
  }

  /// Direct access to the in-memory store for richer test seeding.
  FakeStore get store => _store;
  final FakeStore _store;
}

class FakeStore {
  /// Server-owned cosmetic catalog (palette of colors, frames, ...).
  final List<CosmeticItem> catalog = [];

  /// Conversations hidden FOR the current user (`pair|userId`) — mirrors the
  /// server's ConversationHidden rows ("Excluir conversa para mim").
  final List<String> conversationHides = [];

  /// Messages hidden FOR the current user (`pair|messageId|userId`) — mirrors
  /// the server's MessageHide rows ("Excluir mensagem para mim").
  final List<String> messageHides = [];

  /// Messages deleted for everyone (`pair|messageId`) — mirrors the server's
  /// soft-deleted messages (deletedAt set).
  final List<String> deletedEverywhere = [];

  /// Groups (fake): id -> group header/list state.
  final Map<String, GroupConversation> groups = {};

  /// Sticker catalog (fake): the full server package list.
  final List<StickerPackage> stickerPackages = [];

  /// Sticker favorites (fake).
  final List<Sticker> stickerFavorites = [];

  /// Sticker recents (fake, newest first).
  final List<Sticker> stickerRecents = [];

  /// Hashes SHA-256 de figuritas ya importadas (dedupe simulada del server).
  final Set<String> importedStickerHashes = {};

  /// Sticker.ly pack codes already imported (fake dedupe of the source).
  final Set<String> stickerlyImported = {};

  /// Active stories grouped by author (fake server state).
  final List<StoryGroup> storyGroups = [];

  /// Story ids the session user liked (fake server state).
  final Set<String> storyLikes = {};

  /// Cópias autônomas de favoritas preservadas quando o pacote é excluído
  /// (espelha o pacote-arquivo oculto do servidor).
  final List<Sticker> favoriteArchive = [];

  /// Group messages by group id (fake persistence).
  late final Map<String, List<ChatMessage>> groupMessagesById = {};

  /// Groups hidden FOR the current user (`groupId|userId`) — mirrors the
  /// server's GroupHidden rows.
  final List<String> groupHides = [];

  /// Group member ids by group id (fake persistence: mirrors GroupMember rows).
  final Map<String, Set<String>> groupMemberIds = {};

  /// Currently-banned member ids by group id (fake persistence: mirrors
  /// `bannedAt` on the GroupMember rows — banned users are NOT members).
  final Map<String, Set<String>> groupBannedIds = {};

  FakeStore() {
    users = {
      'u0': MatrixUser(
        id: 'u0',
        nickname: 'leonardo',
        bio: 'Construindo o futuro. ⚡',
        avatarSeed: 'leonardo',
      ),
      // A second full user — needed for search/profile/friendship tests.
      'u2': MatrixUser(
        id: 'u2',
        nickname: 'joao',
        bio: '',
        avatarSeed: 'joao',
      ),
      // A third full user — needed for multi-mention / independence tests.
      'u3': MatrixUser(
        id: 'u3',
        nickname: 'carla',
        bio: '',
        avatarSeed: 'carla',
      ),
    };
    currentUserId = 'u0';
    posts = [
      Post(
        id: 'p1',
        authorId: 'u0',
        authorNickname: 'leonardo',
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
        authorNickname: 'joao',
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
    repliesByParent = <String, List<Comment>>{};
    likedCommentIds = <String>{};
    commentLikeCount = <String, int>{};
    notifications = <MatrixNotification>[];
    friendRequests = <String, FriendRequest>{};
    friendships = <String>{};
    chatMessagesByPair = <String, List<ChatMessage>>{};
  }

  late final Map<String, MatrixUser> users;
  late String? currentUserId;
  late List<Post> posts;
  late Set<String> likedPostIds;
  late Map<String, int> likeCountByPost;
  late Map<String, List<Comment>> commentsByPost;
  late Map<String, List<Comment>> repliesByParent;
  late Set<String> likedCommentIds;
  late Map<String, int> commentLikeCount;

  /// Server-side persistent notifications (recipient = current user).
  late final List<MatrixNotification> notifications;

  /// Friend requests by id; status is a plain string (PENDING/ACCEPTED).
  late final Map<String, FriendRequest> friendRequests;

  /// Friendship pairs stored as `a|b` with ids sorted — one row per
  /// friendship, no duplicates, just like the SQLite schema.
  late final Set<String> friendships;

  /// Private chat messages by conversation (pair key `a|b`), in order.
  late final Map<String, List<ChatMessage>> chatMessagesByPair;

  /// Cosmetics equipped by the session user, keyed by slot.
  final Map<String, CosmeticItem> equippedCosmetics = {};

  MatrixUser get currentUser => users[currentUserId]!;

  String _pairKey(String a, String b) => a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';

  Friendship friendshipState(String otherUserId) {
    final me = currentUserId;
    if (me == otherUserId) return Friendship.none;
    if (friendships.contains(_pairKey(me!, otherUserId))) {
      return Friendship.friends;
    }
    final pending = friendRequests.values.where((r) =>
        r.status == 'PENDING' &&
        ((r.sender.id == me && r.receiverId == otherUserId) ||
            (r.sender.id == otherUserId && r.receiverId == me)));
    for (final r in pending) {
      return r.sender.id == me
          ? Friendship.outgoingPending
          : Friendship.incomingPending;
    }
    return Friendship.none;
  }
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._store);

  final FakeStore _store;

  @override
  Future<AuthDto> register({
    required String nickname,
    required String password,
  }) async {
    final user = MatrixUser(
      id: 'u${_store.users.length}',
      nickname: nickname,
      bio: '',
    );
    _store.users[user.id] = user;
    _store.currentUserId = user.id;
    return AuthDto(
      accessToken: 'fake-access',
      refreshToken: 'fake-refresh',
      user: AuthUserDto(
        id: user.id,
        nickname: user.nickname,
        avatarUrl: user.avatarUrl,
        bio: user.bio,
      ),
      recoveryCode: '829147206153',
    );
  }

  @override
  Future<AuthDto> login({
    required String nickname,
    required String password,
  }) async {
    final u = _store.currentUser;
    return AuthDto(
      accessToken: 'fake-access',
      refreshToken: 'fake-refresh',
      user: AuthUserDto(
        id: u.id,
        nickname: u.nickname,
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
      nickname: u.nickname,
      avatarUrl: u.avatarUrl,
      bio: u.bio,
    );
  }

  @override
  Future<void> logout() async {}

  @override
  Future<void> deleteAccount() async {
    final id = _store.currentUserId;
    _store.users.remove(id);
    _store.currentUserId = null;
  }
}

class _FakePostRepository implements PostRepository {
  _FakePostRepository(this._store);

  final FakeStore _store;

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
  Future<Post> create({
    required String text,
    String? imageUrl,
    String? videoUrl,
    String? thumbnailUrl,
  }) async {
    final u = _store.currentUser;
    final post = Post(
      id: 'p${DateTime.now().millisecondsSinceEpoch}',
      authorId: u.id,
      authorNickname: u.nickname,
      text: text,
      createdAt: DateTime.now(),
      avatarSeed: u.avatarSeed,
      authorAvatarUrl: u.avatarUrl,
      imageUrl: imageUrl,
      videoUrl: videoUrl,
      thumbnailUrl: thumbnailUrl,
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

  final FakeStore _store;

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

  final FakeStore _store;

  @override
  Future<List<Comment>> list(String postId) async {
    // Mirror the server: top-level comments carry their (server-computed)
    // reply count so "ver respostas" appears only when replies exist.
    return List<Comment>.of(
      (List.of(_store.commentsByPost[postId] ?? const [])).map((c) {
        final replies = _store.repliesByParent[c.id];
        if (replies == null || replies.isEmpty) return c;
        return c.copyWith(replyCount: replies.length);
      }),
    );
  }

  @override
  Future<List<Comment>> listReplies(String parentCommentId) async {
    return List.of(_store.repliesByParent[parentCommentId] ?? const []);
  }

  @override
  Future<Comment> create({required String postId, required String text}) async {
    final comment = Comment(
      id: 'c${DateTime.now().microsecondsSinceEpoch}',
      authorId: _store.currentUser.id,
      authorNickname: _store.currentUser.nickname,
      authorAvatarUrl: _store.currentUser.avatarUrl,
      text: text,
      createdAt: DateTime.now(),
    );
    _store.commentsByPost.putIfAbsent(postId, () => []).add(comment);
    return comment;
  }

  @override
  Future<Comment> reply({
    required String parentCommentId,
    required String text,
  }) async {
    final reply = Comment(
      id: 'r${DateTime.now().microsecondsSinceEpoch}',
      authorId: _store.currentUser.id,
      authorNickname: _store.currentUser.nickname,
      authorAvatarUrl: _store.currentUser.avatarUrl,
      text: text,
      createdAt: DateTime.now(),
      parentCommentId: parentCommentId,
    );
    _store.repliesByParent.putIfAbsent(parentCommentId, () => []).add(reply);
    return reply;
  }

  @override
  Future<void> delete(String commentId) async {
    for (final list in _store.commentsByPost.values) {
      list.removeWhere((c) => c.id == commentId);
    }
    for (final list in _store.repliesByParent.values) {
      list.removeWhere((c) => c.id == commentId);
    }
  }

  @override
  Future<({bool liked, int likeCount})> toggleLike(String commentId,
      {required bool liked}) async {
    final nowLiked = liked;
    if (nowLiked) {
      _store.likedCommentIds.add(commentId);
    } else {
      _store.likedCommentIds.remove(commentId);
    }
    final base = _store.commentLikeCount[commentId] ?? 0;
    final count = (base + (nowLiked ? 1 : -1)).clamp(0, 1 << 31);
    _store.commentLikeCount[commentId] = count;
    return (liked: nowLiked, likeCount: count);
  }
}

class _FakeUserRepository implements UserRepository {
  _FakeUserRepository(this._store);

  final FakeStore _store;

  @override
  Future<({MatrixUser user, List<Post> posts, Friendship? friendship})> profile(
    String nickname,
  ) async {
    final user = _store.users.values.firstWhere(
      (u) => u.nickname == nickname,
      orElse: () => _store.currentUser,
    );
    final userPosts =
        _store.posts.where((p) => p.authorNickname == nickname).toList();
    final isCurrent = user.id == _store.currentUserId;
    // Real counters, like the server computes them: posts of THIS user and
    // accepted friendships only.
    final friendsCount = _store.friendships
        .where((pair) => pair.split('|').contains(user.id))
        .length;
    return (
      user: user.copyWith(
        postsCount: userPosts.length,
        friendsCount: friendsCount,
      ),
      posts: userPosts,
      friendship: isCurrent ? null : _store.friendshipState(user.id),
    );
  }

  @override
  Future<MatrixUser> updateProfile({
    String? nickname,
    String? bio,
    String? avatarUrl,
  }) async {
    final old = _store.currentUser;
    final updated = MatrixUser(
      id: old.id,
      nickname: nickname ?? old.nickname,
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
    return users.where((u) => u.nickname.toLowerCase().contains(q)).toList();
  }
}

class _FakeUploadRepository implements UploadRepository {
  const _FakeUploadRepository();

  @override
  Future<String> upload(File file, {String? contentType, String? filename}) async =>
      'https://fake.matrix.app/u/test.png';

  @override
  Future<String> uploadVideo(File file, {int? durationMs}) async =>
      'https://fake.matrix.app/u/test.mp4';
}

/// In-memory cosmetics: the session user "owns" everything they equip —
/// ownership validation is a server concern tested in ServidorMtx.
class _FakeCustomizationRepository implements CustomizationRepository {
  _FakeCustomizationRepository(this._store);

  final FakeStore _store;

  @override
  Future<List<CosmeticItem>> catalog({String? type}) async =>
      _store.catalog.where((i) => type == null || i.slot == type).toList();

  @override
  Future<List<CosmeticItem>> inventory() async =>
      _store.equippedCosmetics.values.toList();

  @override
  Future<Map<String, CosmeticItem>> equipped() async =>
      Map.of(_store.equippedCosmetics);

  @override
  Future<CosmeticItem> equip(String itemId) async {
    // Mirror the server: the slot comes from the CATALOG item's own type;
    // unknown ids are rejected. NAME_COLOR entries equip freely.
    final item = _store.catalog.where((i) => i.id == itemId).firstOrNull;
    if (item == null) {
      throw const ApiException(
          statusCode: 404, message: 'Item não encontrado.');
    }
    _store.equippedCosmetics[item.slot] = item;
    return item;
  }

  @override
  Future<void> unequip(String slot) async {
    _store.equippedCosmetics.remove(slot);
  }

  /// Mirrors the server: each id is validated against the catalog (null
  /// removes the slot, absent leaves it untouched) and persisted; the app
  /// then reloads `equipped()`.
  @override
  Future<void> saveCosmetics({String? nameColorId, String? frameId}) async {
    _applySlot(nameColorId, CosmeticItem.nameColor);
    _applySlot(frameId, CosmeticItem.avatarFrame);
  }

  void _applySlot(String? id, String slot) {
    if (id == null) {
      _store.equippedCosmetics.remove(slot);
      return;
    }
    final item =
        _store.catalog.where((i) => i.id == id && i.slot == slot).firstOrNull;
    if (item == null) {
      throw const ApiException(statusCode: 400, message: 'Item inválido.');
    }
    _store.equippedCosmetics[slot] = item;
  }
}

class _FakeFriendRepository implements FriendRepository {
  _FakeFriendRepository(this._store);

  final FakeStore _store;

  @override
  Future<FriendRequest> send(String userId) async {
    final sender = _store.currentUser;
    final key = 'fr_${sender.id}_$userId';
    final existing = _store.friendRequests[key];
    if (existing != null) {
      throw const ApiException(
        statusCode: 409,
        message: 'Solicitação já enviada.',
      );
    }
    final request = FriendRequest(
      id: key,
      status: 'PENDING',
      createdAt: DateTime.now(),
      sender: sender,
      receiverId: userId,
    );
    _store.friendRequests[key] = request;
    return request;
  }

  @override
  Future<List<FriendRequest>> pending() async {
    final me = _store.currentUserId;
    return _store.friendRequests.values
        .where((r) => r.status == 'PENDING' && r.receiverId == me)
        .toList();
  }

  @override
  Future<void> accept(String requestId) async {
    final request = _store.friendRequests[requestId];
    if (request == null) return;
    _store.friendRequests[requestId] = FriendRequest(
      id: request.id,
      status: 'ACCEPTED',
      createdAt: request.createdAt,
      sender: request.sender,
      receiverId: request.receiverId,
    );
    final ids = [request.sender.id, request.receiverId]..sort();
    _store.friendships.add('${ids[0]}|${ids[1]}');
  }

  @override
  Future<void> reject(String requestId) async {
    _store.friendRequests.remove(requestId);
  }

  @override
  Future<void> cancel(String userId) async {
    _store.friendRequests.removeWhere((key, r) =>
        r.status == 'PENDING' &&
        r.sender.id == _store.currentUserId &&
        r.receiverId == userId);
  }

  @override
  Future<void> removeFriend(String userId) async {
    final me = _store.currentUserId;
    final pair = _store._pairKey(me!, userId);
    _store.friendships.remove(pair);
  }

  @override
  Future<Friendship> state(String userId) async =>
      _store.friendshipState(userId);

  @override
  Future<({List<MatrixUser> friends, int total, int page, int pageSize})> list(
    String userId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final ids = <String>[];
    for (final pair in _store.friendships) {
      final parts = pair.split('|');
      if (parts.contains(userId)) {
        ids.add(parts.firstWhere((id) => id != userId));
      }
    }
    final all =
        ids.map((id) => _store.users[id]).whereType<MatrixUser>().toList();
    final start = (page - 1) * pageSize;
    final slice = start >= all.length
        ? <MatrixUser>[]
        : all.sublist(start, (start + pageSize).clamp(0, all.length));
    return (friends: slice, total: all.length, page: page, pageSize: pageSize);
  }
}

class _FakeNotificationRepository implements NotificationRepository {
  _FakeNotificationRepository(this._store);

  final FakeStore _store;

  @override
  Future<({List<MatrixNotification> notifications, int unreadCount})>
      list() async {
    final items = List.of(_store.notifications);
    return (
      notifications: items,
      unreadCount: items.where((n) => !n.read).length,
    );
  }

  @override
  Future<void> markRead(String id) async {
    for (var i = 0; i < _store.notifications.length; i++) {
      if (_store.notifications[i].id == id && !_store.notifications[i].read) {
        _store.notifications[i] = _store.notifications[i].copyWith(read: true);
      }
    }
  }

  @override
  Future<void> markAllRead() async {
    for (var i = 0; i < _store.notifications.length; i++) {
      if (!_store.notifications[i].read) {
        _store.notifications[i] = _store.notifications[i].copyWith(read: true);
      }
    }
  }
}

/// In-memory chat: conversations (friend-only, one per pair) and messages
/// persisted per conversation, mirroring the SQLite schema. Enforces
/// friendship the same way the real server does.
class _FakeChatRepository implements ChatRepository {
  _FakeChatRepository(this._store);

  final FakeStore _store;

  String _pairKey(String a, String b) => a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';

  List<ChatMessage> _messagesOf(String pair) =>
      List.of(_store.chatMessagesByPair[pair] ?? const []);

  /// Messages that [me] may actually see: not hidden for them ("Excluir para
  /// mim") and not deleted for everyone. Mirrors the server's read paths.
  List<ChatMessage> _visibleMessages(String pair, String me) {
    return _messagesOf(pair).where((m) {
      if (_store.deletedEverywhere.contains('$pair|${m.id}')) return false;
      if (_store.messageHides.contains('$pair|${m.id}|$me')) return false;
      return true;
    }).toList();
  }

  @override
  Future<List<Conversation>> conversations() async {
    final me = _store.currentUserId;
    if (me == null) return const [];
    final result = <Conversation>[];
    for (final pair in _store.friendships) {
      final parts = pair.split('|');
      if (!parts.contains(me)) continue;
      // "Excluir conversa (para mim)" hides it from THIS user's list only.
      if (_store.conversationHides.contains('$pair|$me')) continue;
      final otherId = parts.firstWhere((id) => id != me);
      final other = _store.users[otherId];
      if (other == null) continue;
      final messages = _visibleMessages(pair, me);
      final last = messages.isNotEmpty ? messages.last : null;
      result.add(Conversation(
        id: pair,
        otherUser: other.toChatUser(),
        lastMessage: last == null
            ? null
            : ConversationLastMessage(
                id: last.id,
                content: last.content,
                senderId: last.senderId,
                createdAt: last.createdAt,
              ),
        lastMine: last?.senderId == me,
        unreadCount: 0,
        updatedAt: last?.createdAt ?? DateTime(2024),
      ));
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  @override
  Future<int> unreadCount() async => 0;

  @override
  Future<void> deleteMessageForMe(
      String conversationId, String messageId) async {
    final pair = _pairFromConversationId(conversationId);
    if (pair == null) return;
    _store.messageHides.add('$pair|$messageId|${_store.currentUserId}');
  }

  @override
  Future<void> deleteMessageForEveryone(
      String conversationId, String messageId) async {
    final pair = _pairFromConversationId(conversationId);
    if (pair == null) return;
    _store.deletedEverywhere.add('$pair|$messageId');
  }

  @override
  Future<void> hideConversation(String conversationId) async {
    final pair = _pairFromConversationId(conversationId);
    if (pair == null) return;
    _store.conversationHides.add('$pair|${_store.currentUserId}');
  }

  // Deterministic reverse of the pair -> conversationId mapping.
  String? _pairFromConversationId(String conversationId) {
    for (final pair in _store.friendships) {
      if (pair == conversationId) return pair;
    }
    return null;
  }

  @override
  Future<Conversation> getOrCreate(String otherUserId) async {
    final me = _store.currentUserId;
    if (me == null || me == otherUserId) {
      throw const ApiException(statusCode: 403, message: 'Conversa inválida.');
    }
    if (!_store.friendships.contains(_pairKey(me, otherUserId))) {
      throw const ApiException(
        statusCode: 403,
        message: 'Vocês precisam ser amigos para iniciar uma conversa.',
      );
    }
    final other = _store.users[otherUserId];
    if (other == null) {
      throw const ApiException(
          statusCode: 404, message: 'Usuário não encontrado.');
    }
    final pair = _pairKey(me, otherUserId);
    final messages = _visibleMessages(pair, me);
    final last = messages.isNotEmpty ? messages.last : null;
    return Conversation(
      id: pair,
      otherUser: other.toChatUser(),
      lastMessage: last == null
          ? null
          : ConversationLastMessage(
              id: last.id,
              content: last.content,
              senderId: last.senderId,
              createdAt: last.createdAt,
            ),
      lastMine: last?.senderId == me,
      unreadCount: 0,
      updatedAt: last?.createdAt ?? DateTime(2024),
    );
  }

  @override
  Future<({List<ChatMessage> messages, bool hasMore})> messages(
    String conversationId, {
    String? before,
    int limit = 30,
  }) async {
    final me = _store.currentUserId ?? '';
    // Only VISIBLE messages are returned (mirrors the server): hidden-for-me
    // and deleted-for-everyone messages never reach the client.
    final all = _visibleMessages(conversationId, me);
    // `before` references a message id → return the messages OLDER than it.
    if (before != null) {
      final index = all.indexWhere((m) => m.id == before);
      final from = index == -1 ? all.length : index;
      final older = all.sublist(0, from);
      final start = older.length > limit ? older.length - limit : 0;
      return (messages: older.sublist(start), hasMore: start > 0);
    }
    // Latest page: the newest `limit` messages.
    final start = all.length > limit ? all.length - limit : 0;
    return (messages: all.sublist(start), hasMore: start > 0);
  }

  @override
  Future<ChatMessage> send(
    String conversationId,
    String content, {
    String? replyToMessageId,
  }) async {
    final me = _store.currentUserId;
    // The fake mirrors the server's reply resolution: resolve the ORIGINAL
    // message's preview (nickname + content) unless it was deleted.
    ReplyInfo? replyTo;
    if (replyToMessageId != null) {
      final all = _messagesOf(conversationId);
      ChatMessage? target;
      for (final m in all) {
        // A message deleted for everyone can no longer be a reply preview.
        if (m.id == replyToMessageId &&
            !_store.deletedEverywhere.contains('$conversationId|${m.id}')) {
          target = m;
          break;
        }
      }
      replyTo = target == null
          ? ReplyInfo(
              id: replyToMessageId,
              senderId: '',
              senderNickname: '',
              content: '',
              exists: false,
            )
          : ReplyInfo(
              id: target.id,
              senderId: target.senderId,
              senderNickname: target.senderId == me
                  ? _store.users[me]?.nickname ?? 'Você'
                  : _store.users[target.senderId]?.nickname ?? '',
              content: target.content,
              exists: true,
            );
    }
    final message = ChatMessage(
      id: 'm${DateTime.now().microsecondsSinceEpoch}',
      conversationId: conversationId,
      senderId: me!,
      content: content,
      createdAt: DateTime.now(),
      mine: true,
      replyTo: replyTo,
    );
    _store.chatMessagesByPair
        .putIfAbsent(conversationId, () => [])
        .add(message);
    return message;
  }

  @override
  Future<ChatMessage> sendMedia(
    String conversationId, {
    required String kind,
    required String url,
    String? replyToMessageId,
  }) async {
    final me = _store.currentUserId;
    final label = kind == 'video' ? '🎥 Vídeo' : '📷 Foto';
    final message = ChatMessage(
      id: 'md${DateTime.now().microsecondsSinceEpoch}',
      conversationId: conversationId,
      senderId: me!,
      content: label,
      createdAt: DateTime.now(),
      mine: true,
      type: kind,
      imageUrl: kind == 'image' ? url : null,
      videoUrl: kind == 'video' ? url : null,
      replyTo: replyToMessageId == null
          ? null
          : ReplyInfo(
              id: replyToMessageId,
              senderId: _store.currentUserId ?? "",
              senderNickname: _store.currentUser.nickname,
              content: "original",
              exists: true,
            ),
    );
    _store.chatMessagesByPair
        .putIfAbsent(conversationId, () => [])
        .add(message);
    return message;
  }

  @override
  Future<ChatMessage> sendVoice(
    String conversationId,
    File audioFile, {
    required int durationMs,
    String? replyToMessageId,
  }) async {
    final me = _store.currentUserId;
    final message = ChatMessage(
      id: 'v${DateTime.now().microsecondsSinceEpoch}',
      conversationId: conversationId,
      senderId: me!,
      content: '🎤 Áudio',
      createdAt: DateTime.now(),
      mine: true,
      type: 'voice',
      audioUrl: 'memory://voice-${DateTime.now().microsecondsSinceEpoch}.m4a',
      durationMs: durationMs,
      replyTo: replyToMessageId == null
          ? null
          : ReplyInfo(
              id: replyToMessageId,
              senderId: _store.currentUserId ?? "",
              senderNickname: _store.currentUser.nickname,
              content: "original",
              exists: true,
            ),
    );
    _store.chatMessagesByPair
        .putIfAbsent(conversationId, () => [])
        .add(message);
    return message;
  }

  @override
  Future<void> markRead(String conversationId) async {}

  @override
  void setTyping(String conversationId, bool typing) {}
  @override
  void setRecording(String conversationId, bool recording) {}

// ── Groups (fake) ──────────────────────────────────────────

  @override
  Future<List<GroupConversation>> groups() async {
    final me = _store.currentUserId;
    if (me == null) return const [];
    final result = <GroupConversation>[];
    _store.groups.forEach((groupId, g) {
      if (_store.groupHides.contains('$groupId|$me')) return;
      final messages = _store.groupMessagesById[groupId] ?? const [];
      final visible = messages
          .where((m) => !_store.deletedEverywhere.contains('g$groupId|${m.id}'))
          .toList();
      final last = visible.isNotEmpty ? visible.last : null;
      result.add(g.copyWith(
        lastMessage: last == null
            ? null
            : ConversationLastMessage(
                id: last.id,
                content: last.content,
                senderId: last.senderId,
                createdAt: last.createdAt,
              ),
        lastMine: last?.senderId == me,
        unreadCount: 0,
        updatedAt: last?.createdAt ?? g.updatedAt,
      ));
    });
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  @override
  Future<int> groupUnreadCount() async => 0;

  @override
  Future<GroupConversation> createGroup({
    required String name,
    String description = '',
    String? avatarUrl,
    List<String> participantIds = const [],
  }) async {
    final me = _store.currentUserId;
    if (me == null) {
      throw const ApiException(statusCode: 401, message: 'Não autenticado.');
    }
    if (name.trim().isEmpty) {
      throw const ApiException(
          statusCode: 422, message: 'Nome do grupo é obrigatório.');
    }
    final id = 'g${_store.groups.length + 1}';
    final g = GroupConversation(
      id: id,
      group: GroupHeader(
        id: id,
        name: name.trim(),
        avatarUrl: avatarUrl,
        description: description,
        createdById: me,
        memberCount: participantIds.length + 1,
      ),
      lastMessage: null,
      lastMine: false,
      unreadCount: 0,
      updatedAt: DateTime.now(),
    );
    _store.groups[id] = g;
    _store.groupMessagesById[id] = [];
    _store.groupMemberIds[id] = {me, ...participantIds};
    return g;
  }

  @override
  Future<({List<ChatMessage> messages, bool hasMore})> groupMessages(
    String groupId, {
    String? before,
    int limit = 30,
  }) async {
    final me = _store.currentUserId;
    if (me == null) {
      throw const ApiException(statusCode: 401, message: 'Não autenticado.');
    }
    if (!_store.groups.containsKey(groupId)) {
      throw const ApiException(
          statusCode: 404, message: 'Grupo não encontrado.');
    }
    final all =
        List<ChatMessage>.of(_store.groupMessagesById[groupId] ?? const []);
    // Mirror the server: a banned sender's messages stay in history but their
    // embedded `sender.banned` reflects the CURRENT group ban state.
    final bannedIds = _store.groupBannedIds[groupId] ?? const <String>{};
    final visible = all.map((m) {
      final sender = m.sender;
      if (sender == null || bannedIds.contains(sender.id) == sender.banned) {
        return m;
      }
      return m.copyWith(
          sender: sender.copyWith(banned: bannedIds.contains(sender.id)));
    }).toList();
    if (before != null) {
      final index = visible.indexWhere((m) => m.id == before);
      final from = index == -1 ? visible.length : index;
      final older = visible.sublist(0, from);
      final start = older.length > limit ? older.length - limit : 0;
      return (messages: older.sublist(start), hasMore: start > 0);
    }
    final start = visible.length > limit ? visible.length - limit : 0;
    return (messages: visible.sublist(start), hasMore: start > 0);
  }

  @override
  Future<ChatMessage> sendGroupMessage(
    String groupId,
    String content, {
    String? replyToMessageId,
    List<ChatMention> mentions = const [],
    List<String> mentionUserIds = const [],
    bool mentionAll = false,
  }) async {
    final me = _store.currentUserId;
    if (me == null || !_store.groups.containsKey(groupId)) {
      throw const ApiException(statusCode: 403, message: 'Acesso negado.');
    }
    // @todos is owner-only (mirrors the server rule).
    final hasAll = mentionAll || mentions.any((m) => m.all);
    if (hasAll && _store.groups[groupId]!.group.createdById != me) {
      throw const ApiException(
          statusCode: 403,
          message: 'Somente o dono do grupo pode usar "@todos".');
    }
    // RANGE-ANCHORED mention rows win; legacy ids are a fallback. `@todos`
    // mirrors the server serialization: exposed via `mentionAll`, never inside
    // mentions[] (which only holds individual user references).
    var finalMentions = [
      for (final m in mentions)
        if (!m.all) m,
    ];
    if (finalMentions.isEmpty && mentionUserIds.isNotEmpty) {
      finalMentions = [
        for (final id in mentionUserIds)
          ChatMention(
              userId: id,
              nickname: _store.users[id]?.nickname ?? 'desconhecido'),
      ];
    }
    final message = ChatMessage(
      id: 'gm${DateTime.now().microsecondsSinceEpoch}',
      groupId: groupId,
      conversationId: groupId,
      senderId: me,
      content: content,
      createdAt: DateTime.now(),
      mine: true,
      replyTo: replyToMessageId == null
          ? null
          : ReplyInfo(
              id: replyToMessageId,
              senderId: _store.currentUserId ?? "",
              senderNickname: _store.currentUser.nickname,
              content: "original",
              exists: true,
            ),
      mentions: finalMentions,
      mentionAll: hasAll,
      mentioned: hasAll || finalMentions.any((m) => m.userId == me),
    );
    _store.groupMessagesById.putIfAbsent(groupId, () => []).add(message);
    return message;
  }

  @override
  Future<
      ({
        List<ChatUser> read,
        List<ChatUser> unread,
      })> groupMessageReaders(
    String groupId,
    String messageId,
  ) async {
    // Fake: everyone except the sender is "read" (enough for widget tests).
    final members = _store.groupMemberIds[groupId] ?? const <String>{};
    final read = <ChatUser>[
      for (final id in members)
        if (id != _store.currentUserId)
          ChatUser(
            id: id,
            nickname: _store.users[id]?.nickname ?? 'membro',
          ),
    ];
    return (read: read, unread: <ChatUser>[]);
  }

  @override
  Future<ChatMessage> sendGroupMedia(
    String groupId, {
    required String kind,
    required String url,
    String? replyToMessageId,
  }) async {
    final me = _store.currentUserId;
    if (me == null || !_store.groups.containsKey(groupId)) {
      throw const ApiException(statusCode: 403, message: 'Acesso negado.');
    }
    final label = kind == 'video' ? '🎥 Vídeo' : '📷 Foto';
    final message = ChatMessage(
      id: 'gmd${DateTime.now().microsecondsSinceEpoch}',
      groupId: groupId,
      conversationId: groupId,
      senderId: me,
      content: label,
      createdAt: DateTime.now(),
      mine: true,
      type: kind,
      imageUrl: kind == 'image' ? url : null,
      videoUrl: kind == 'video' ? url : null,
      replyTo: replyToMessageId == null
          ? null
          : ReplyInfo(
              id: replyToMessageId,
              senderId: _store.currentUserId ?? "",
              senderNickname: _store.currentUser.nickname,
              content: "original",
              exists: true,
            ),
    );
    _store.groupMessagesById.putIfAbsent(groupId, () => []).add(message);
    return message;
  }

  @override
  Future<ChatMessage> sendGroupVoiceMessage(
    String groupId,
    File audioFile, {
    required int durationMs,
    String? replyToMessageId,
  }) async {
    final me = _store.currentUserId;
    final message = ChatMessage(
      id: 'gv${DateTime.now().microsecondsSinceEpoch}',
      groupId: groupId,
      conversationId: groupId,
      senderId: me!,
      content: '🎤 Áudio',
      createdAt: DateTime.now(),
      mine: true,
      type: 'voice',
      audioUrl: 'memory://voice-${DateTime.now().microsecondsSinceEpoch}.m4a',
      durationMs: durationMs,
      replyTo: replyToMessageId == null
          ? null
          : ReplyInfo(
              id: replyToMessageId,
              senderId: _store.currentUserId ?? "",
              senderNickname: _store.currentUser.nickname,
              content: "original",
              exists: true,
            ),
    );
    _store.groupMessagesById.putIfAbsent(groupId, () => []).add(message);
    return message;
  }

  @override
  Future<ChatMessage> sendSticker(
    String conversationId,
    String stickerId, {
    String? replyToMessageId,
  }) async {
    final me = _store.currentUserId;
    final sticker = _store.stickerPackages
        .expand((p) => p.stickers)
        .where((s) => s.id == stickerId)
        .firstOrNull;
    final message = ChatMessage(
      id: 'st${DateTime.now().microsecondsSinceEpoch}',
      conversationId: conversationId,
      senderId: me!,
      content: '🧩 Figurinha',
      createdAt: DateTime.now(),
      mine: true,
      type: 'sticker',
      stickerUrl: sticker?.fileUrl ?? 'sticker://$stickerId.png',
      stickerId: stickerId,
      stickerPackageId: sticker?.packageId ?? '',
      replyTo: replyToMessageId == null
          ? null
          : ReplyInfo(
              id: replyToMessageId,
              senderId: me,
              senderNickname: _store.currentUser.nickname,
              content: 'original',
              exists: true,
            ),
    );
    _store.chatMessagesByPair
        .putIfAbsent(conversationId, () => [])
        .add(message);
    return message;
  }

  @override
  Future<ChatMessage> sendGroupSticker(
    String groupId,
    String stickerId, {
    String? replyToMessageId,
  }) async {
    final me = _store.currentUserId;
    final sticker = _store.stickerPackages
        .expand((p) => p.stickers)
        .where((s) => s.id == stickerId)
        .firstOrNull;
    final message = ChatMessage(
      id: 'gst${DateTime.now().microsecondsSinceEpoch}',
      groupId: groupId,
      conversationId: groupId,
      senderId: me!,
      content: '🧩 Figurinha',
      createdAt: DateTime.now(),
      mine: true,
      type: 'sticker',
      stickerUrl: sticker?.fileUrl ?? 'sticker://$stickerId.png',
      stickerId: stickerId,
      stickerPackageId: sticker?.packageId ?? '',
    );
    _store.groupMessagesById.putIfAbsent(groupId, () => []).add(message);
    return message;
  }

  @override
  Future<void> markGroupRead(String groupId) async {}
  @override
  void setGroupTyping(String groupId, bool typing) {}
  @override
  void setGroupRecording(String groupId, bool recording) {}
  @override
  Future<void> deleteGroupMessageForMe(String groupId, String messageId) async {
    _store.messageHides.add('g$groupId|$messageId|${_store.currentUserId}');
  }

  @override
  Future<void> deleteGroupMessageForEveryone(
      String groupId, String messageId) async {
    _store.deletedEverywhere.add('g$groupId|$messageId');
  }

  @override
  Future<void> hideGroup(String groupId) async {
    _store.groupHides.add('$groupId|${_store.currentUserId}');
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    if (_store.groups.containsKey(groupId)) {
      _store.groups.remove(groupId);
      _store.groupMessagesById.remove(groupId);
      _store.groupMemberIds.remove(groupId);
      _store.groupBannedIds.remove(groupId);
    }
  }

  @override
  Future<void> leaveGroup(String groupId) async {
    final me = _store.currentUserId;
    if (me == null) return;
    // Mirrors the server: an active member removes their OWN membership row.
    // The OWNER cannot leave (rejected — a group must never be orphaned).
    final ownerId = _store.groups[groupId]?.group.createdById;
    if (me == ownerId) {
      throw const ApiException(
        statusCode: 403,
        message:
            'O dono do grupo não pode sair. Para encerrar o grupo, use "Excluir grupo".',
      );
    }
    _store.groupMemberIds[groupId]?.remove(me);
  }

  @override
  Future<
      ({
        GroupHeader group,
        List<GroupMemberInfoModel> members,
        List<GroupMemberInfoModel> bannedMembers,
      })> groupInfo(
    String groupId,
  ) async {
    final g = _store.groups[groupId];
    if (g == null) {
      throw const ApiException(
          statusCode: 404, message: 'Grupo n\u00e3o encontrado.');
    }
    final me = _store.currentUserId;

    final ownerId = g.group.createdById;

    final allUsers = _store.users.values.toList();
    final memberIds = _store.groupMemberIds[groupId];
    final candidates = memberIds != null && memberIds.isNotEmpty
        ? (allUsers.where((u) => memberIds.contains(u.id)).toList())
        : [
            ...allUsers.where((u) => u.id == ownerId),
            ...allUsers.where((u) => u.id == me || u.id == ownerId),
          ];

    final seen = <String>{};
    final members = <GroupMemberInfoModel>[];
    for (final u in candidates) {
      if (!seen.add(u.id)) continue;
      members.add(GroupMemberInfoModel(
        id: u.id,
        nickname: u.nickname,
        avatarUrl: u.avatarUrl,
        isOwner: u.id == ownerId,
      ));
    }
    final bannedIds = _store.groupBannedIds[groupId] ?? const <String>{};
    final bannedMembers = <GroupMemberInfoModel>[];
    for (final u in allUsers) {
      if (u.id == ownerId || !bannedIds.contains(u.id)) continue;
      if (members.any((m) => m.id == u.id)) continue;
      bannedMembers.add(GroupMemberInfoModel(
        id: u.id,
        nickname: u.nickname,
        avatarUrl: u.avatarUrl,
        isOwner: false,
      ));
    }
    return (group: g.group, members: members, bannedMembers: bannedMembers);
  }

  @override
  Future<GroupHeader> updateGroup(
    String groupId, {
    String? name,
    String? description,
  }) async {
    final g = _store.groups[groupId];
    if (g == null) {
      throw const ApiException(
          statusCode: 404, message: 'Grupo n\u00e3o encontrado.');
    }
    final updated = g.copyWith(
        group: g.group.copyWith(
      name: name,
      description: description,
    ));
    _store.groups[groupId] = updated;
    return updated.group;
  }

  @override
  Future<GroupHeader> updateGroupAvatar(
    String groupId,
    String avatarUrl,
  ) async {
    final g = _store.groups[groupId];
    if (g == null) {
      throw const ApiException(
          statusCode: 404, message: 'Grupo n\u00e3o encontrado.');
    }
    final updated = g.copyWith(group: g.group.copyWith(avatarUrl: avatarUrl));
    _store.groups[groupId] = updated;
    return updated.group;
  }

  @override
  Future<GroupConversation> addGroupMember(
    String groupId,
    String newUserId,
  ) async {
    final g = _store.groups[groupId];
    if (g == null) {
      throw const ApiException(
          statusCode: 404, message: 'Grupo n\u00e3o encontrado.');
    }
    final updated = g.copyWith(
        group: g.group.copyWith(memberCount: g.group.memberCount + 1));
    _store.groups[groupId] = updated;
    return updated;
  }

  @override
  Future<GroupConversation> banGroupMember(
    String groupId,
    String targetUserId,
  ) async {
    final g = _store.groups[groupId];
    if (g == null) {
      throw const ApiException(
          statusCode: 404, message: 'Grupo não encontrado.');
    }
    // Banned users are no longer active members (row is kept in the fake DB
    // with bannedAt set — mirrors the server's GroupMember.bannedAt).
    _store.groupMemberIds[groupId]?.remove(targetUserId);
    (_store.groupBannedIds[groupId] ??= {}).add(targetUserId);
    final updated = g.copyWith(
        group: g.group.copyWith(memberCount: g.group.memberCount - 1));
    _store.groups[groupId] = updated;
    return updated;
  }

  @override
  Future<GroupConversation> unbanGroupMember(
    String groupId,
    String targetUserId,
  ) async {
    final g = _store.groups[groupId];
    if (g == null) {
      throw const ApiException(
          statusCode: 404, message: 'Grupo não encontrado.');
    }
    _store.groupBannedIds[groupId]?.remove(targetUserId);
    final memberIds = _store.groupMemberIds[groupId] ??= {};
    if (targetUserId != g.group.createdById) memberIds.add(targetUserId);
    final updated =
        g.copyWith(group: g.group.copyWith(memberCount: memberIds.length));
    _store.groups[groupId] = updated;
    return updated;
  }
}

class _FakeStickerRepository implements StickerRepository {
  _FakeStickerRepository(this._store);

  final FakeStore _store;

  @override
  Future<List<StickerPackage>> catalog() async => List.of(_store.stickerPackages);

  @override
  Future<StickerPackage> package(String packageId) async {
    return _store.stickerPackages.firstWhere(
      (p) => p.id == packageId,
      orElse: () => throw const ApiException(
          statusCode: 404, message: 'Pacote de figurinhas não encontrado.'),
    );
  }

  @override
  Future<void> install(String packageId) async {
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> uninstall(String packageId) async {
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<int> deletePackage(String packageId) async {
    // Preserva as favoritas do pacote (mesma regra do servidor): move cada
    // favorita para uma cópia autônoma, depois remove o pacote do catálogo.
    final pkg = _store.stickerPackages.where((p) => p.id == packageId).firstOrNull;
    var preserved = 0;
    if (pkg != null) {
      final ids = pkg.stickers.map((s) => s.id).toSet();
      final favs = _store.stickerFavorites.where((f) => ids.contains(f.id));
      preserved = favs.length;
      for (final fav in favs) {
        _store.favoriteArchive.add(fav.copyWith(favorited: true));
      }
      _store.stickerFavorites.removeWhere((f) => ids.contains(f.id));
      _store.stickerFavorites.addAll(
        _store.favoriteArchive.where((f) => ids.contains(f.id)),
      );
      _store.stickerPackages.removeWhere((p) => p.id == packageId);
    }
    return preserved;
  }

  @override
  Future<List<Sticker>> favorites() async => List.of(_store.stickerFavorites);

  @override
  Future<void> favorite(String stickerId) async {
    if (_store.stickerFavorites.every((s) => s.id != stickerId)) {
      final source = _store.stickerPackages
          .expand((p) => p.stickers)
          .where((s) => s.id == stickerId)
          .firstOrNull;
      if (source != null) {
        _store.stickerFavorites.insert(0, source.copyWith(favorited: true));
      }
    }
  }

  @override
  Future<void> unfavorite(String stickerId) async {
    _store.stickerFavorites.removeWhere((s) => s.id == stickerId);
  }

  @override
  Future<List<Sticker>> recents() async => List.of(_store.stickerRecents);

  @override
  Future<StickerlyPackPreview> stickerlyPreview(String code) async {
    if (code.length < 4) {
      throw const ApiException(
          statusCode: 400, message: 'Código inválido.');
    }
    if (code.toUpperCase() == 'MISSING') {
      throw const ApiException(
          statusCode: 404,
          message: 'Não foi possível encontrar esse pacote.');
    }
    return StickerlyPackPreview(
      code: code.toUpperCase(),
      name: 'Pacote Sticker.ly',
      author: 'Autor Ly',
      iconUrl: 'https://fake.matrix.app/ly/tray.png',
      stickerCount: 2,
      animated: false,
      previewUrls: const ['https://fake.matrix.app/ly/1.webp'],
      alreadyInstalled: _store.stickerlyImported.contains(code.toUpperCase()),
    );
  }

  @override
  Future<({StickerPackage? package, int created, int skipped, bool already})>
      stickerlyImport(String code) async {
    final upper = code.toUpperCase();
    if (_store.stickerlyImported.contains(upper)) {
      return (package: null, created: 0, skipped: 0, already: true);
    }
    _store.stickerlyImported.add(upper);
    final pkg = StickerPackage(
      id: 'ly_$upper',
      name: 'Pacote Sticker.ly',
      slug: 'stickerly-${upper.toLowerCase()}',
      description: 'Importado do Sticker.ly.',
      author: 'Autor Ly',
      iconUrl: 'https://fake.matrix.app/ly/tray.png',
      installed: true,
      stickerCount: 1,
      stickers: [
        Sticker(
          id: 'ly_${upper}_0',
          packageId: 'ly_$upper',
          order: 0,
          fileUrl: 'https://fake.matrix.app/ly/1.webp',
        ),
      ],
    );
    _store.stickerPackages.insert(0, pkg);
    return (package: pkg, created: 1, skipped: 0, already: false);
  }

  @override
  Future<void> markRecent(String stickerId) async {
    final source = _store.stickerPackages
        .expand((p) => p.stickers)
        .where((s) => s.id == stickerId)
        .firstOrNull;
    if (source == null) return;
    _store.stickerRecents
      ..removeWhere((s) => s.id == stickerId)
      ..insert(0, source);
  }

  @override
  Future<void> removeRecent(String stickerId) async {
    // Somente a entrada de RECENTES sai — pacote/favorito/mensagem intactos.
    _store.stickerRecents.removeWhere((s) => s.id == stickerId);
  }

  @override
  Future<({int created, int skipped})> importPackage(
    String name,
    List<Map<String, dynamic>> stickers,
  ) async {
    if (stickers.isEmpty) return (created: 0, skipped: 0);
    var created = 0;
    var skipped = 0;
    final newStickers = <Sticker>[];
    for (final item in stickers) {
      final hash = item['hash'] as String? ?? '';
      if (hash.isNotEmpty && _importedHashes.contains(hash)) {
        skipped++;
        continue;
      }
      if (hash.isNotEmpty) _importedHashes.add(hash);
      newStickers.add(Sticker(
        id: 'shared_$created',
        packageId: '',
        order: created,
        fileUrl: item['url'] as String,
        width: (item['width'] as num?)?.toInt(),
        height: (item['height'] as num?)?.toInt(),
      ));
      created++;
    }
    if (newStickers.isNotEmpty) {
      final pkg = StickerPackage(
        id: 'shared_pkg',
        name: name.isNotEmpty ? name : 'Meus stickers',
        slug: 'compartilhados-fake',
        description: 'Importado do compartilhamento.',
        author: 'MATRIX',
        iconUrl: newStickers.first.fileUrl,
        installed: true,
        stickerCount: newStickers.length,
        stickers: newStickers,
      );
      _store.stickerPackages.insert(0, pkg);
      _store.stickerFavorites.clear();
    }
    return (created: created, skipped: skipped);
  }
}

/// Hashes já importados (simula a dedupe do servidor para testes).
extension _FakeStickerRepoHashes on _FakeStickerRepository {
  Set<String> get _importedHashes => _store.importedStickerHashes;
}


/// In-memory stories: mirrors the server's grouping/ordering contract
/// (unviewed authors first, newest first inside each group).
class _FakeStoryRepository implements StoryRepository {
  _FakeStoryRepository(this._store);

  final FakeStore _store;

  @override
  Future<List<StoryGroup>> active() async {
    final groups = _store.storyGroups.map((g) {
      final stories = g.stories
          .where((s) => s.expiresAt.isAfter(DateTime.now()))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return StoryGroup(
        authorId: g.authorId,
        authorNickname: g.authorNickname,
        authorAvatarUrl: g.authorAvatarUrl,
        authorNicknameColor: g.authorNicknameColor,
        authorFrameId: g.authorFrameId,
        authorFrameAsset: g.authorFrameAsset,
        stories: stories,
        allViewed: stories.isNotEmpty && stories.every((s) => s.viewed),
      );
    }).where((g) => g.stories.isNotEmpty).toList();
    groups.sort((a, b) {
      if (a.allViewed != b.allViewed) return a.allViewed ? 1 : -1;
      final aT = a.stories.first.createdAt;
      final bT = b.stories.first.createdAt;
      return bT.compareTo(aT);
    });
    return groups;
  }

  @override
  Future<Story> create({
    String type = 'image',
    String? mediaUrl,
    String mediaType = 'image',
    String text = '',
    String? thumbnailUrl,
    String caption = '',
    int? durationMs,
  }) async {
    final now = DateTime.now();
    final story = Story(
      id: 'story_${now.microsecondsSinceEpoch}',
      authorId: _store.currentUserId ?? "",
      authorNickname: 'matrixuser0',
      authorAvatarUrl: null,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      type: type,
      text: text,
      thumbnailUrl: thumbnailUrl,
      caption: caption,
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 24)),
      mine: true,
    );
    // Append to the session user's group (created on demand).
    final idx = _store.storyGroups.indexWhere(
      (g) => g.authorId == (_store.currentUserId ?? ""),
    );
    if (idx >= 0) {
      final g = _store.storyGroups[idx];
      _store.storyGroups[idx] = StoryGroup(
        authorId: g.authorId,
        authorNickname: g.authorNickname,
        authorAvatarUrl: g.authorAvatarUrl,
        stories: [story, ...g.stories],
        allViewed: false,
      );
    } else {
      _store.storyGroups.add(StoryGroup(
        authorId: _store.currentUserId ?? "",
        authorNickname: 'matrixuser0',
        authorAvatarUrl: null,
        stories: [story],
        allViewed: false,
      ));
    }
    return story;
  }

  @override
  Future<({bool liked, int likeCount})> toggleLike(String storyId) async {
    // Espelha o servidor: uma curtida por usuário+story (toggle).
    if (_store.storyLikes.contains(storyId)) {
      _store.storyLikes.remove(storyId);
      return (liked: false, likeCount: 0);
    }
    _store.storyLikes.add(storyId);
    return (liked: true, likeCount: 1);
  }

  @override
  Future<({ChatMessage message, String conversationId})> reply(
    String storyId,
    String text,
  ) async {
    // O servidor cria uma mensagem REAL na conversa com o autor do Story.
    final now = DateTime.now();
    final msg = ChatMessage(
      id: 'story_reply_${now.microsecondsSinceEpoch}',
      conversationId: 'story_conv',
      senderId: _store.currentUserId ?? '',
      content: text,
      createdAt: now,
      mine: true,
      type: 'story_reply',
      story: StoryReference(
        storyId: storyId,
        type: 'text',
        preview: text,
      ),
    );
    return (message: msg, conversationId: 'story_conv');
  }

  @override
  Future<void> markViewed(String storyId) async {
    for (var i = 0; i < _store.storyGroups.length; i++) {
      final g = _store.storyGroups[i];
      if (g.stories.every((s) => s.id != storyId)) continue;
      _store.storyGroups[i] = StoryGroup(
        authorId: g.authorId,
        authorNickname: g.authorNickname,
        authorAvatarUrl: g.authorAvatarUrl,
        stories: g.stories
            .map((s) => s.id == storyId
                ? Story(
                    id: s.id,
                    authorId: s.authorId,
                    authorNickname: s.authorNickname,
                    authorAvatarUrl: s.authorAvatarUrl,
                    mediaUrl: s.mediaUrl,
                    mediaType: s.mediaType,
                    thumbnailUrl: s.thumbnailUrl,
                    caption: s.caption,
                    createdAt: s.createdAt,
                    expiresAt: s.expiresAt,
                    viewed: true,
                    mine: s.mine,
                  )
                : s)
            .toList(),
        allViewed: true,
      );
    }
  }

  @override
  Future<void> delete(String storyId) async {
    for (var i = _store.storyGroups.length - 1; i >= 0; i--) {
      final g = _store.storyGroups[i];
      final remaining = g.stories.where((s) => s.id != storyId).toList();
      if (remaining.isEmpty) {
        _store.storyGroups.removeAt(i);
      } else {
        _store.storyGroups[i] = StoryGroup(
          authorId: g.authorId,
          authorNickname: g.authorNickname,
          authorAvatarUrl: g.authorAvatarUrl,
          stories: remaining,
          allViewed: remaining.every((s) => s.viewed),
        );
      }
    }
  }
}
