import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../models/comment.dart';
import '../../models/conversation.dart';
import '../../models/cosmetic_item.dart';
import '../../models/friend_request.dart';
import '../../models/matrix_notification.dart';
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
    required String nickname,
    required String password,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/api/auth/register',
      data: {
        'nickname': nickname,
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
    required String nickname,
    required String password,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/api/auth/login',
      data: {'nickname': nickname, 'password': password},
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

  /// Hard-delete of the authenticated account (server cascade) followed by
  /// a full local token cleanup. Identity is never sent — the server takes
  /// it from the bearer token.
  Future<void> deleteAccount() async {
    try {
      await _api.delete('/api/auth/account');
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

/// Comments repository — list, create, reply, delete and like.
class CommentRepository {
  CommentRepository(this._api);

  final ApiClient _api;

  Future<List<Comment>> list(String postId) async {
    final json = await _api.get<Map<String, dynamic>>('/api/posts/$postId/comments');
    final list = (json['comments'] as List).cast<Map<String, dynamic>>();
    return list.map(CommentDto.fromJson).map((d) => d.toModel()).toList();
  }

  /// Replies of a top-level comment (oldest first).
  Future<List<Comment>> listReplies(String parentCommentId) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/api/comments/$parentCommentId/replies',
    );
    final list = (json['replies'] as List).cast<Map<String, dynamic>>();
    return list.map(CommentDto.fromJson).map((d) => d.toModel()).toList();
  }

  Future<Comment> create({required String postId, required String text}) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/api/posts/$postId/comments',
      data: {'text': text},
    );
    return CommentDto.fromJson(json).toModel();
  }

  /// Creates a reply under [parentCommentId]. The server associates it with
  /// that comment so it renders grouped under it.
  Future<Comment> reply({
    required String parentCommentId,
    required String text,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/api/comments/$parentCommentId/replies',
      data: {'text': text},
    );
    return CommentDto.fromJson(json).toModel();
  }

  Future<void> delete(String commentId) async {
    await _api.delete('/api/comments/$commentId');
  }

  /// Toggles the session user's like on a comment/reply. Returns the
  /// updated {liked, likeCount} from the server (single source of truth).
  Future<({bool liked, int likeCount})> toggleLike(String commentId,
      {required bool liked}) async {
    final json = liked
        ? await _api.post<Map<String, dynamic>>('/api/comments/$commentId/like')
        : await _api.delete<Map<String, dynamic>>('/api/comments/$commentId/like');
    return (
      liked: json['liked'] as bool,
      likeCount: (json['likeCount'] as num).toInt(),
    );
  }
}

/// Users repository — public profile, update own profile, search.
class UserRepository {
  UserRepository(this._api);

  final ApiClient _api;

  /// Fetches a public profile by nickname: user, posts and (for an
  /// authenticated viewer) the friendship state Seguir/Solicitado/Amigos.
  Future<({MatrixUser user, List<Post> posts, Friendship? friendship})> profile(
    String nickname,
  ) async {
    // Nicknames are full Unicode (emojis, spaces, symbols) — the path
    // segment must be percent-encoded or the URL breaks.
    final json = await _api
        .get<Map<String, dynamic>>('/api/users/${Uri.encodeComponent(nickname)}');
    final user = PublicUserDto.fromJson(json['user'] as Map<String, dynamic>).toModel();
    final list = (json['posts'] as List).cast<Map<String, dynamic>>();
    final posts = list.map(FeedPostDto.fromJson).map((d) => d.toModel()).toList();
    final raw = json['friendship'];
    final friendship = raw is String ? Friendship.fromApi(raw) : null;
    return (user: user, posts: posts, friendship: friendship);
  }

  Future<MatrixUser> updateProfile({
    String? nickname,
    String? bio,
    String? avatarUrl,
  }) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/api/users/me',
      data: {
        if (nickname != null) 'nickname': nickname,
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

/// Friends repository — friend request lifecycle (send / list / accept /
/// reject). All authorization is enforced by the server.
class FriendRepository {
  FriendRepository(this._api);

  final ApiClient _api;

  Future<FriendRequest> send(String userId) async {
    final json = await _api.post<Map<String, dynamic>>('/api/friend-requests/$userId');
    return FriendRequestDto.fromJson(json).toModel();
  }

  Future<List<FriendRequest>> pending() async {
    final json = await _api.get<Map<String, dynamic>>('/api/friend-requests');
    final list = (json['requests'] as List).cast<Map<String, dynamic>>();
    return list.map(FriendRequestDto.fromJson).map((d) => d.toModel()).toList();
  }

  Future<void> accept(String requestId) async {
    await _api.post('/api/friend-requests/$requestId/accept');
  }

  Future<void> reject(String requestId) async {
    await _api.post('/api/friend-requests/$requestId/reject');
  }

  /// Cancels the PENDING request the CURRENT user sent to [userId]. The
  /// server removes the request + its notification; the relationship
  /// returns to NONE (SOLICITAR).
  Future<void> cancel(String userId) async {
    await _api.delete('/api/friend-requests/$userId');
  }

  /// Removes the ACCEPTED friendship between the CURRENT user and [userId].
  /// The server validates the requester (only one side of the friendship
  /// may remove it) and deletes the row; the relationship returns to NONE.
  Future<void> removeFriend(String userId) async {
    await _api.delete('/api/users/$userId/friends');
  }

  /// Current friendship state with another user, per the server.
  Future<Friendship> state(String userId) async {
    final json = await _api.get<Map<String, dynamic>>('/api/users/$userId/friendship');
    return Friendship.fromApi(json['state'] as String?);
  }

  /// Paginated friends list of a user (accepted friendships only). Used by
  /// the profile "Amigos" bottom sheet; [total] matches the profile
  /// counter because both come from the same server query.
  Future<({List<MatrixUser> friends, int total, int page, int pageSize})> list(
    String userId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/api/users/$userId/friends',
      queryParameters: {'page': page, 'pageSize': pageSize},
    );
    final list = (json['friends'] as List).cast<Map<String, dynamic>>();
    return (
      friends: list.map(PublicUserDto.fromJson).map((d) => d.toModel()).toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? page,
      pageSize: (json['pageSize'] as num?)?.toInt() ?? pageSize,
    );
  }
}

/// Notifications repository — persistent server-side notifications.
class NotificationRepository {
  NotificationRepository(this._api);

  final ApiClient _api;

  /// Fetches the notification list plus the unread counter.
  Future<({List<MatrixNotification> notifications, int unreadCount})> list() async {
    final json = await _api.get<Map<String, dynamic>>('/api/notifications');
    final list = (json['notifications'] as List).cast<Map<String, dynamic>>();
    final notifications =
        list.map(NotificationDto.fromJson).map((d) => d.toModel()).toList();
    return (
      notifications: notifications,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> markRead(String id) async {
    await _api.patch('/api/notifications/$id/read');
  }

  Future<void> markAllRead() async {
    await _api.patch('/api/notifications/read-all');
  }
}

/// Private chat repository — conversations, messages and unread badge.
/// All authorization is enforced by the server (friend-only messaging,
/// membership on every load); the client never sends a senderId.
class ChatRepository {
  ChatRepository(this._api);

  final ApiClient _api;

  /// The authenticated user's conversations, newest activity first, each
  /// with the OTHER participant embedded.
  Future<List<Conversation>> conversations() async {
    final json = await _api.get<Map<String, dynamic>>('/api/conversations');
    return (json['conversations'] as List)
        .cast<Map<String, dynamic>>()
        .map(ConversationDto.fromJson)
        .map((d) => d.toModel())
        .toList();
  }

  /// Unread conversations counter for the Chat tab badge.
  Future<int> unreadCount() async {
    final json =
        await _api.get<Map<String, dynamic>>('/api/conversations/unread-count');
    return (json['unreadCount'] as num?)?.toInt() ?? 0;
  }

  /// Returns the ONE conversation with [otherUserId], creating it when none
  /// exists yet (friends only — the server enforces this).
  Future<Conversation> getOrCreate(String otherUserId) async {
    final json = await _api
        .post<Map<String, dynamic>>('/api/conversations/$otherUserId');
    return ConversationDto.fromJson(json['conversation'] as Map<String, dynamic>)
        .toModel();
  }

  /// Latest messages of a conversation. Pass [before] (the id of the oldest
  /// currently-loaded message) to fetch the OLDER page.
  Future<({List<ChatMessage> messages, bool hasMore})> messages(
    String conversationId, {
    String? before,
    int limit = 30,
  }) async {
    final query = <String, dynamic>{'limit': limit};
    if (before != null) query['before'] = before;
    final json = await _api.get<Map<String, dynamic>>(
      '/api/conversations/$conversationId/messages',
      queryParameters: query,
    );
    final page = MessagePageDto.fromJson(json);
    return (messages: page.messages, hasMore: page.hasMore);
  }

  /// Sends a chat message. Returns the persisted message (auth-derived
  /// sender). [replyToMessageId] is optional: when set, the message is a
  /// reply to that existing message of the same conversation (only the
  /// reference is stored server-side). Throws [ApiException] on rejection.
  Future<ChatMessage> send(
    String conversationId,
    String content, {
    String? replyToMessageId,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/api/conversations/$conversationId/messages',
      data: {
        'content': content,
        if (replyToMessageId != null && replyToMessageId.isNotEmpty)
          'replyToMessageId': replyToMessageId,
      },
    );
    return ChatMessageDto.fromJson(json['message'] as Map<String, dynamic>)
        .toModel();
  }

  /// Sends a VOICE message (AAC/m4a recorded locally) for [conversationId].
  /// [durationMs] is the recorded length (3–60s, validated server-side). The
  /// audio file rides as multipart; the duration is a query param. Returns
  /// the persisted voice message (type === 'voice').
  Future<ChatMessage> sendVoice(
    String conversationId,
    File audioFile, {
    required int durationMs,
  }) async {
    final multipart = await MultipartFile.fromFile(audioFile.path);
    final json = await _api.upload<Map<String, dynamic>>(
      '/api/conversations/$conversationId/voice?durationMs=$durationMs',
      file: multipart,
    );
    final raw = json['message'] as Map<String, dynamic>;
    if (kDebugMode) {
      debugPrint('[voice] upload OK — id=${raw['id']} '
          'type=${raw['type']} url=${raw['audioUrl']} '
          'duration=${raw['durationMs']}ms');
    }
    return ChatMessageDto.fromJson(raw).toModel();
  }

  /// Marks all messages FROM THE OTHER SIDE as read (clears the unread badge).
  Future<void> markRead(String conversationId) async {
    await _api.post('/api/conversations/$conversationId/read');
  }

  /// "Excluir mensagem para mim" — the message disappears for the CURRENT
  /// user only (the peer keeps seeing it). Server-persisted (MessageHide
  /// row), so it survives app restarts and re-logins. Idempotent.
  Future<void> deleteMessageForMe(String conversationId, String messageId) async {
    await _api.delete('/api/conversations/$conversationId/messages/$messageId');
  }

  /// "Excluir mensagem para todos" — server-authoritative soft-delete that
  /// removes the message for BOTH participants (the server validates the
  /// caller is a member of the conversation). The peer gets a realtime
  /// `chat_message_deleted` frame so an open conversation updates live.
  /// Idempotent; errors (403/404) surface as [ApiException].
  Future<void> deleteMessageForEveryone(String conversationId, String messageId) async {
    await _api.delete(
      '/api/conversations/$conversationId/messages/$messageId/everyone',
    );
  }

  /// "Excluir conversa para mim" — removes the conversation from the CURRENT
  /// user's Chat list only. The conversation + its messages stay fully intact
  /// for the peer. A new incoming message un-hides it (server-side). Idempotent.
  Future<void> hideConversation(String conversationId) async {
    await _api.delete('/api/conversations/$conversationId');
  }

  /// Signals the session user's typing state to the peer (ephemeral realtime
  /// frame — nothing persists server-side). Best-effort: failures are silent.

  void setTyping(String conversationId, bool typing) {
    // Fire-and-forget: typing state is transient and non-critical.

    _api
        .post<void>('/api/conversations/$conversationId/typing',
            data: {'typing': typing})
        .catchError((_) {});
  }

  /// Signals the peer that the session user is (or stopped) recording a voice
  /// message in [conversationId]. Ephemeral realtime frame — nothing persists,
  /// so there is no stale state to clean up server-side (the peer also
  /// auto-clears it). Mirrors [setTyping]: same auth + membership rules,
  /// best-effort (a failed signal must never break the recording flow).
  void setRecording(String conversationId, bool recording) {

    _api
        .post<void>('/api/conversations/$conversationId/recording',
            data: {'recording': recording})
        .catchError((_) {});
  }

}

/// Profile customization (cosmetics): catalog, inventory and equipped
/// items. All state is server-owned — the server validates ownership on
/// equip, so a crafted client request can never unlock an item.
class CustomizationRepository {
  CustomizationRepository(this._api);

  final ApiClient _api;

  /// The active server-owned catalog, optionally filtered by slot/type.
  Future<List<CosmeticItem>> catalog({String? type}) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/api/customization/catalog',
      queryParameters: type != null ? {'type': type} : null,
    );
    return (json['items'] as List)
        .cast<Map<String, dynamic>>()
        .map(CosmeticItemDto.fromJson)
        .map((d) => d.toModel())
        .toList();
  }

  /// Items the session user owns (expired ones are filtered server-side).
  Future<List<CosmeticItem>> inventory() async {
    final json =
        await _api.get<Map<String, dynamic>>('/api/customization/inventory');
    return (json['items'] as List)
        .cast<Map<String, dynamic>>()
        .map(CosmeticItemDto.fromJson)
        .map((d) => d.toModel())
        .toList();
  }

  /// Currently equipped cosmetics of the session user, keyed by slot.
  Future<CosmeticMap> equipped() async {
    final json =
        await _api.get<Map<String, dynamic>>('/api/customization/equipped');
    final list = (json['equipped'] as List).cast<Map<String, dynamic>>();
    final map = <String, CosmeticItem>{};
    for (final entry in list) {
      final item = CosmeticItemDto.fromJson(entry).toModel();
      map[item.slot] = item;
    }
    return map;
  }

  /// Equips an OWNED item. Throws [ApiException] when the user does not
  /// own it or it expired — the server is the source of truth.
  Future<CosmeticItem> equip(String itemId) async {
    final json = await _api
        .post<Map<String, dynamic>>('/api/customization/equip/$itemId');
    return CosmeticItemDto.fromJson(json['equipped'] as Map<String, dynamic>)
        .toModel();
  }

  Future<void> unequip(String slot) async {
    await _api.delete('/api/customization/equip/$slot');
  }

  /// Consolidated save: sends the WHOLE pending customization in ONE
  /// operation — `{nameColorId, frameId}`. A string value equips the catalog
  /// entry, null removes the slot, absent leaves it untouched. The server
  /// validates each id against the active catalog and persists it. Callers
  /// refresh the equipped map afterwards (`equipped()`) so the server stays
  /// the source of truth.
  Future<void> saveCosmetics({
    String? nameColorId,
    String? frameId,
  }) async {
    await _api.put<Map<String, dynamic>>(
      '/api/customization/cosmetics',
      data: {'nameColorId': nameColorId, 'frameId': frameId},
    );
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
    required this.friends,
    required this.notifications,
    required this.uploads,
    required this.customization,
    required this.chat,
  });

  final AuthRepository auth;
  final PostRepository posts;
  final LikeRepository likes;
  final CommentRepository comments;
  final UserRepository users;
  final FriendRepository friends;
  final NotificationRepository notifications;
  final UploadRepository uploads;
  final CustomizationRepository customization;
  final ChatRepository chat;
}
