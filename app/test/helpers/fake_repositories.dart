import 'dart:io';

import 'package:matrix_app/data/api_config.dart';
import 'package:matrix_app/data/dtos/dtos.dart';
import 'package:matrix_app/data/repositories/repositories.dart';
import 'package:matrix_app/models/comment.dart';
import 'package:matrix_app/models/conversation.dart';
import 'package:matrix_app/models/cosmetic_item.dart';
import 'package:matrix_app/models/friend_request.dart';
import 'package:matrix_app/models/matrix_notification.dart';
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
  }) : _store = store;

  factory FakeRepositories({
    bool failLikes = false,
    Map<String, List<Comment>> seedComments = const {},
    Map<String, List<Comment>> seedReplies = const {},
    Set<String> seedLikedCommentIds = const {},
    List<MatrixNotification> seedNotifications = const [],
    Map<String, CosmeticItem> seedEquippedCosmetics = const {},
    List<CosmeticItem> seedCatalog = const [],
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
    );
  }

  /// Direct access to the in-memory store for richer test seeding.
  FakeStore get store => _store;
  final FakeStore _store;
}

class FakeStore {
  /// Server-owned cosmetic catalog (palette of colors, frames, ...).
  final List<CosmeticItem> catalog = [];

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
  Future<Post> create({required String text, String? imageUrl}) async {
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
    return List.of(_store.commentsByPost[postId] ?? const []);
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
    return users
        .where((u) => u.nickname.toLowerCase().contains(q))
        .toList();
  }
}

class _FakeUploadRepository implements UploadRepository {
  const _FakeUploadRepository();

  @override
  Future<String> upload(File file) async => 'https://fake.matrix.app/u/test.png';
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
    final item = _store.catalog
        .where((i) => i.id == itemId)
        .firstOrNull;
    if (item == null) {
      throw const ApiException(statusCode: 404, message: 'Item não encontrado.');
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
    final item = _store.catalog
        .where((i) => i.id == id && i.slot == slot)
        .firstOrNull;
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
        r.status == 'PENDING' && r.sender.id == _store.currentUserId && r.receiverId == userId);
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
    final all = ids.map((id) => _store.users[id]).whereType<MatrixUser>().toList();
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
  Future<({List<MatrixNotification> notifications, int unreadCount})> list() async {
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

  String _pairKey(String a, String b) =>
      a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';

  List<ChatMessage> _messagesOf(String pair) =>
      List.of(_store.chatMessagesByPair[pair] ?? const []);

  @override
  Future<List<Conversation>> conversations() async {
    final me = _store.currentUserId;
    final result = <Conversation>[];
    for (final pair in _store.friendships) {
      final parts = pair.split('|');
      if (!parts.contains(me)) continue;
      final otherId = parts.firstWhere((id) => id != me);
      final other = _store.users[otherId];
      if (other == null) continue;
      final messages = _messagesOf(pair);
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
      throw const ApiException(statusCode: 404, message: 'Usuário não encontrado.');
    }
    final pair = _pairKey(me, otherUserId);
    final messages = _messagesOf(pair);
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
    final all = _messagesOf(conversationId);
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
        if (m.id == replyToMessageId) {
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
    _store.chatMessagesByPair.putIfAbsent(conversationId, () => []).add(message);
    return message;
  }

  @override
  Future<void> markRead(String conversationId) async {}

  @override
  void setTyping(String conversationId, bool typing) {}
}

