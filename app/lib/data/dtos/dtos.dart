import '../../models/comment.dart';
import '../../models/conversation.dart';
import '../../models/cosmetic_item.dart';
import '../../models/friend_request.dart';
import '../../models/matrix_notification.dart';
import '../../models/matrix_user.dart';
import '../../models/post.dart';
import '../../models/sticker.dart';

/// Mappers that convert backend JSON responses into the app's domain models.
///
/// Keeping these in one place means the UI never touches raw maps and the
/// API response shape can evolve without rippling through every screen.

class AuthDto {
  final String accessToken;
  final String refreshToken;
  final AuthUserDto user;
  final String? recoveryCode;

  const AuthDto({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    this.recoveryCode,
  });

  factory AuthDto.fromJson(Map<String, dynamic> json) => AuthDto(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        user: AuthUserDto.fromJson(json['user'] as Map<String, dynamic>),
        recoveryCode: json['recoveryCode'] as String?,
      );
}

class AuthUserDto {
  final String id;
  final String nickname;
  final String? avatarUrl;
  final String bio;

  const AuthUserDto({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    required this.bio,
  });

  MatrixUser toModel() => MatrixUser(
        id: id,
        nickname: nickname,
        bio: bio,
        avatarUrl: avatarUrl,
      );

  factory AuthUserDto.fromJson(Map<String, dynamic> json) => AuthUserDto(
        id: json['id'] as String,
        nickname: json['nickname'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        bio: (json['bio'] as String?) ?? '',
      );
}

class FeedPostDto {
  final String id;
  final String text;
  final String? imageUrl;
  final String? videoUrl;
  final String? thumbnailUrl;
  final DateTime createdAt;
  final String authorId;
  final String authorNickname;
  final String? authorAvatarUrl;
  final String? authorNicknameColor;
  final String? authorFrameId;
  final String? authorFrameAsset;
  final int likeCount;
  final bool liked;
  final int commentCount;

  const FeedPostDto({
    required this.id,
    required this.text,
    this.imageUrl,
    this.videoUrl,
    this.thumbnailUrl,
    required this.createdAt,
    required this.authorId,
    required this.authorNickname,
    this.authorAvatarUrl,
    this.authorNicknameColor,
    this.authorFrameId,
    this.authorFrameAsset,
    required this.likeCount,
    required this.liked,
    required this.commentCount,
  });

  Post toModel() => Post(
        id: id,
        authorId: authorId,
        authorNickname: authorNickname,
        text: text,
        createdAt: createdAt,
        avatarSeed: authorNickname,
        authorAvatarUrl: authorAvatarUrl,
        authorNicknameColor: authorNicknameColor,
        authorFrameId: authorFrameId,
        authorFrameAsset: authorFrameAsset,
        imageUrl: imageUrl,
        videoUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
        likes: likeCount,
        liked: liked,
        commentCount: commentCount,
      );

  factory FeedPostDto.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>;
    return FeedPostDto(
      id: json['id'] as String,
      text: (json['text'] as String?) ?? '',
      imageUrl: json['imageUrl'] as String?,
      videoUrl: json['videoUrl'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      authorId: (author['id'] as String?) ?? '',
      authorNickname: author['nickname'] as String,
      authorAvatarUrl: author['avatarUrl'] as String?,
      authorNicknameColor: author['nameColor'] as String?,
      authorFrameId: author['frameId'] as String?,
      authorFrameAsset: author['frameAsset'] as String?,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      liked: (json['liked'] as bool?) ?? false,
      commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class CommentDto {
  final String id;
  final String text;
  final DateTime createdAt;
  final String authorId;
  final String authorNickname;
  final String? authorAvatarUrl;
  final String? authorNicknameColor;
  final String? authorFrameId;
  final String? authorFrameAsset;
  final String? parentCommentId;
  final int likeCount;
  final bool liked;
  final int replyCount;

  const CommentDto({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.authorId,
    required this.authorNickname,
    this.authorAvatarUrl,
    this.authorNicknameColor,
    this.authorFrameId,
    this.authorFrameAsset,
    this.parentCommentId,
    this.likeCount = 0,
    this.liked = false,
    this.replyCount = 0,
  });

  Comment toModel() => Comment(
        id: id,
        authorId: authorId,
        authorNickname: authorNickname,
        authorAvatarUrl: authorAvatarUrl,
        authorNicknameColor: authorNicknameColor,
        authorFrameId: authorFrameId,
        authorFrameAsset: authorFrameAsset,
        text: text,
        createdAt: createdAt,
        parentCommentId: parentCommentId,
        likeCount: likeCount,
        liked: liked,
        replyCount: replyCount,
      );

  factory CommentDto.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>;
    return CommentDto(
      id: json['id'] as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      authorId: author['id'] as String,
      authorNickname: author['nickname'] as String,
      authorAvatarUrl: author['avatarUrl'] as String?,
      authorNicknameColor: author['nameColor'] as String?,
      authorFrameId: author['frameId'] as String?,
      authorFrameAsset: author['frameAsset'] as String?,
      parentCommentId: json['parentCommentId'] as String?,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      liked: (json['liked'] as bool?) ?? false,
      replyCount: (json['replyCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class PublicUserDto {
  final String id;
  final String nickname;
  final String? avatarUrl;
  final String bio;
  final int friendsCount;
  final int postsCount;
  final CosmeticMap customization;
  final String? nameColor;
  final String? frameId;
  final String? frameAsset;

  const PublicUserDto({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    required this.bio,
    this.friendsCount = 0,
    this.postsCount = 0,
    this.customization = const {},
    this.nameColor,
    this.frameId,
    this.frameAsset,
  });

  MatrixUser toModel() => MatrixUser(
        id: id,
        nickname: nickname,
        bio: bio,
        avatarUrl: avatarUrl,
        friendsCount: friendsCount,
        postsCount: postsCount,
        customization: customization,
        nameColor: nameColor,
        frameId: frameId,
        frameAsset: frameAsset,
      );

  factory PublicUserDto.fromJson(Map<String, dynamic> json) => PublicUserDto(
        id: json['id'] as String,
        nickname: json['nickname'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        bio: (json['bio'] as String?) ?? '',
        friendsCount: (json['friendsCount'] as num?)?.toInt() ?? 0,
        postsCount: (json['postsCount'] as num?)?.toInt() ?? 0,
        customization: parseCustomization(json['customization']),
        nameColor: json['nameColor'] as String?,
        frameId: json['frameId'] as String?,
        frameAsset: json['frameAsset'] as String?,
      );
}

/// Parses the profile `customization` object: slot → equipped cosmetic.
/// Absent/invalid payloads degrade to "nothing equipped" (all defaults).
CosmeticMap parseCustomization(Object? raw) {
  if (raw is! Map) return const {};
  final map = <String, CosmeticItem>{};
  raw.forEach((slot, value) {
    if (slot is String && value is Map<String, dynamic>) {
      final itemId = value['itemId'] as String?;
      final name = value['name'] as String?;
      if (itemId != null && name != null) {
        map[slot] = CosmeticItem(
          id: itemId,
          slot: slot,
          name: name,
          assetUrl: (value['assetUrl'] as String?) ?? '',
          rarity: (value['rarity'] as String?) ?? 'COMMON',
          config:
              (value['config'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
      }
    }
  });
  return map;
}

/// A cosmetic entry as returned by the customization endpoints
/// (catalog / inventory / equipped).
class CosmeticItemDto {
  final String id;
  final String slot;
  final String name;
  final String assetUrl;
  final String rarity;
  final String? category;
  final int sortOrder;
  final Map<String, dynamic> config;

  const CosmeticItemDto({
    required this.id,
    required this.slot,
    required this.name,
    this.assetUrl = '',
    this.rarity = 'COMMON',
    this.category,
    this.sortOrder = 0,
    this.config = const {},
  });

  CosmeticItem toModel() => CosmeticItem(
        id: id,
        slot: slot,
        name: name,
        assetUrl: assetUrl,
        rarity: rarity,
        category: category,
        sortOrder: sortOrder,
        config: config,
      );

  /// Catalog/inventory entries carry `id` + `type`; equipped entries carry
  /// `itemId` + `slot`. Both shapes map onto the same model.
  factory CosmeticItemDto.fromJson(Map<String, dynamic> json) =>
      CosmeticItemDto(
        id: (json['id'] as String?) ?? (json['itemId'] as String),
        slot: (json['type'] as String?) ?? (json['slot'] as String),
        name: json['name'] as String,
        assetUrl: (json['assetUrl'] as String?) ?? '',
        rarity: (json['rarity'] as String?) ?? 'COMMON',
        category: json['category'] as String?,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        config: (json['config'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

/// A pending friend request (sender embedded).
class FriendRequestDto {
  final String id;
  final String status;
  final DateTime createdAt;
  final PublicUserDto sender;

  const FriendRequestDto({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.sender,
  });

  FriendRequest toModel() => FriendRequest(
        id: id,
        status: status,
        createdAt: createdAt,
        sender: sender.toModel(),
      );

  factory FriendRequestDto.fromJson(Map<String, dynamic> json) {
    final senderJson = json['sender'] as Map<String, dynamic>;
    return FriendRequestDto(
      id: json['id'] as String,
      status: (json['status'] as String?) ?? 'PENDING',
      createdAt: DateTime.parse(json['createdAt'] as String),
      sender: PublicUserDto.fromJson(senderJson),
    );
  }
}

/// A notification (actor embedded; references post/comment/request).
class NotificationDto {
  final String id;
  final String type;
  final bool read;
  final DateTime createdAt;
  final PublicUserDto actor;
  final String? postId;
  final String? commentId;
  final String? friendRequestId;
  final String? friendRequestStatus;

  const NotificationDto({
    required this.id,
    required this.type,
    required this.read,
    required this.createdAt,
    required this.actor,
    this.postId,
    this.commentId,
    this.friendRequestId,
    this.friendRequestStatus,
  });

  // The actor's own nickname cosmetics ride inside `actor` (PublicUserDto).

  MatrixNotification toModel() => MatrixNotification(
        id: id,
        type: type,
        read: read,
        createdAt: createdAt,
        actorId: actor.id,
        actorNickname: actor.nickname,
        actorAvatarUrl: actor.avatarUrl,
        actorNicknameColor: actor.nameColor,
        actorFrameId: actor.frameId,
        actorFrameAsset: actor.frameAsset,
        postId: postId,
        commentId: commentId,
        friendRequestId: friendRequestId,
        friendRequestStatus: friendRequestStatus,
      );

  factory NotificationDto.fromJson(Map<String, dynamic> json) {
    final actorJson = json['actor'] as Map<String, dynamic>;
    return NotificationDto(
      id: json['id'] as String,
      type: json['type'] as String,
      read: (json['read'] as bool?) ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      actor: PublicUserDto.fromJson(actorJson),
      postId: json['postId'] as String?,
      commentId: json['commentId'] as String?,
      friendRequestId: json['friendRequestId'] as String?,
      friendRequestStatus: json['friendRequestStatus'] as String?,
    );
  }
}

/// The chat counterpart of a user shown inside conversation payloads. Rides
/// the same author fragment (id, nickname, avatar + the OWNER's name
/// color/frame) so chat renders every nickname with the user's real look.
class ChatUserDto {
  final String id;
  final String nickname;
  final String? avatarUrl;
  final String? nameColor;
  final String? frameId;
  final String? frameAsset;
  final bool banned;

  const ChatUserDto({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    this.nameColor,
    this.frameId,
    this.frameAsset,
    this.banned = false,
  });

  ChatUser toModel() => ChatUser(
        id: id,
        nickname: nickname,
        avatarUrl: avatarUrl,
        nameColor: nameColor,
        frameId: frameId,
        frameAsset: frameAsset,
        banned: banned,
      );

  factory ChatUserDto.fromJson(Map<String, dynamic> json) => ChatUserDto(
        id: json['id'] as String,
        nickname: json['nickname'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        nameColor: json['nameColor'] as String?,
        frameId: json['frameId'] as String?,
        frameAsset: json['frameAsset'] as String?,
        banned: (json['banned'] as bool?) ?? false,
      );
}

/// A private conversation (list item / get-or-create response).
class ConversationDto {
  final String id;
  final ChatUserDto otherUser;
  final ConversationLastMessageDto? lastMessage;
  final bool lastMine;
  final int unreadCount;
  final DateTime updatedAt;

  const ConversationDto({
    required this.id,
    required this.otherUser,
    this.lastMessage,
    required this.lastMine,
    required this.unreadCount,
    required this.updatedAt,
  });

  Conversation toModel() => Conversation(
        id: id,
        otherUser: otherUser.toModel(),
        lastMessage: lastMessage?.toModel(),
        lastMine: lastMine,
        unreadCount: unreadCount,
        updatedAt: updatedAt,
      );

  factory ConversationDto.fromJson(Map<String, dynamic> json) {
    final last = json['lastMessage'];
    return ConversationDto(
      id: json['id'] as String,
      otherUser:
          ChatUserDto.fromJson(json['otherUser'] as Map<String, dynamic>),
      lastMessage: last is Map<String, dynamic>
          ? ConversationLastMessageDto.fromJson(last)
          : null,
      lastMine: (json['lastMine'] as bool?) ?? false,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

class ConversationLastMessageDto {
  final String id;
  final String content;
  final String senderId;
  final DateTime createdAt;
  final String? senderNickname;

  const ConversationLastMessageDto({
    required this.id,
    required this.content,
    required this.senderId,
    required this.createdAt,
    this.senderNickname,
  });

  ConversationLastMessage toModel() => ConversationLastMessage(
        id: id,
        content: content,
        senderId: senderId,
        createdAt: createdAt,
        senderNickname: senderNickname,
      );

  factory ConversationLastMessageDto.fromJson(Map<String, dynamic> json) =>
      ConversationLastMessageDto(
        id: json['id'] as String,
        content: json['content'] as String,
        senderId: json['senderId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        senderNickname: json['senderNickname'] as String?,
      );
}

/// A single private chat message. Now carries the read state (drives the
/// "enviado" → "visto agora" hint) and the reply reference (preview of the
/// original message, resolved by the server).
class ChatMessageDto {
  final String id;
  final String? conversationId;
  final String? groupId;
  final ChatUserDto? sender;
  final String senderId;
  final String content;
  final DateTime createdAt;
  final bool mine;
  final DateTime? readAt;
  final ReplyInfoDto? replyTo;
  final String type;
  final String? audioUrl;
  final int? durationMs;
  final String? imageUrl;
  final String? videoUrl;
  final String? stickerUrl;
  final String? stickerId;
  final String? stickerPackageId;
  final List<ChatMention> mentions;
  final bool mentionAll;
  final bool mentioned;

  const ChatMessageDto({
    required this.id,
    this.conversationId,
    this.groupId,
    this.sender,
    required this.senderId,
    required this.content,
    required this.createdAt,
    required this.mine,
    this.readAt,
    this.replyTo,
    this.type = 'text',
    this.audioUrl,
    this.durationMs,
    this.imageUrl,
    this.videoUrl,
    this.stickerUrl,
    this.stickerId,
    this.stickerPackageId,
    this.mentions = const [],
    this.mentionAll = false,
    this.mentioned = false,
  });

  ChatMessage toModel() => ChatMessage(
        id: id,
        conversationId: conversationId,
        groupId: groupId,
        sender: sender?.toModel(),
        senderId: senderId,
        content: content,
        createdAt: createdAt,
        mine: mine,
        readAt: readAt,
        replyTo: replyTo?.toModel(),
        type: switch (type) {
          'voice' => 'voice',
          'image' => 'image',
          'video' => 'video',
          'sticker' => 'sticker',
          _ => 'text',
        },
        audioUrl: audioUrl,
        durationMs: durationMs,
        imageUrl: imageUrl,
        videoUrl: videoUrl,
        stickerUrl: stickerUrl,
        stickerId: stickerId,
        stickerPackageId: stickerPackageId,
        mentions: mentions,
        mentionAll: mentionAll,
        mentioned: mentioned,
      );

  factory ChatMessageDto.fromJson(Map<String, dynamic> json) {
    final raw = json['readAt'];
    final replyRaw = json['replyTo'];
    final senderRaw = json['sender'];
    final mentionsRaw = json['mentions'];
    return ChatMessageDto(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String?,
      groupId: json['groupId'] as String?,
      sender: senderRaw is Map<String, dynamic>
          ? ChatUserDto.fromJson(senderRaw)
          : null,
      senderId: json['senderId'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      mine: (json['mine'] as bool?) ?? false,
      readAt: raw is String ? DateTime.tryParse(raw) : null,
      replyTo: replyRaw is Map<String, dynamic>
          ? ReplyInfoDto.fromJson(replyRaw)
          : null,
      type: (json['type'] as String?) ?? 'text',
      audioUrl: json['audioUrl'] as String?,
      durationMs: (json['durationMs'] as num?)?.toInt(),
      imageUrl: json['imageUrl'] as String?,
      videoUrl: json['videoUrl'] as String?,
      stickerUrl: json['stickerUrl'] as String?,
      stickerId: json['stickerId'] as String?,
      stickerPackageId: json['stickerPackageId'] as String?,
      mentions: mentionsRaw is List
          ? mentionsRaw
              .whereType<Map<String, dynamic>>()
              .map((m) => ChatMentionDto.fromJson(m).toModel())
              .toList()
          : const <ChatMention>[],
      mentionAll: (json['mentionAll'] as bool?) ?? false,
      mentioned: (json['mentioned'] as bool?) ?? false,
    );
  }
}

/// Structured mention payload (server resolves nickname live from the id).
class ChatMentionDto {
  final String userId;
  final String nickname;
  final bool all;
  final int? start;
  final int? end;

  const ChatMentionDto({
    required this.userId,
    required this.nickname,
    this.all = false,
    this.start,
    this.end,
  });

  ChatMention toModel() => ChatMention(
        userId: userId,
        nickname: nickname,
        all: all,
        start: start,
        end: end,
      );

  factory ChatMentionDto.fromJson(Map<String, dynamic> json) => ChatMentionDto(
        userId: json['userId'] as String? ?? '',
        nickname: json['nickname'] as String? ?? '',
        all: (json['all'] as bool?) ?? false,
        start: (json['start'] as num?)?.toInt(),
        end: (json['end'] as num?)?.toInt(),
      );
}

/// Server-resolved preview of the original message a reply answers. Only the
/// preview rides the wire — never a duplicate of the full original.
class ReplyInfoDto {
  final String id;
  final String senderId;
  final String senderNickname;
  final String content;
  final bool exists;

  const ReplyInfoDto({
    required this.id,
    required this.senderId,
    required this.senderNickname,
    required this.content,
    required this.exists,
  });

  ReplyInfo toModel() => ReplyInfo(
        id: id,
        senderId: senderId,
        senderNickname: senderNickname,
        content: content,
        exists: exists,
      );

  factory ReplyInfoDto.fromJson(Map<String, dynamic> json) => ReplyInfoDto(
        id: json['id'] as String? ?? '',
        senderId: json['senderId'] as String? ?? '',
        senderNickname: json['senderNickname'] as String? ?? '',
        content: json['content'] as String? ?? '',
        exists: (json['exists'] as bool?) ?? false,
      );
}

/// Real-time `chat_group_updated` frame: the server pushed a fresh group
/// identity block after an owner edit (name/avatar/description/membership).
/// Also carries the CURRENT list of banned user ids ([bannedUserIds]) so open
/// conversation screens can tag/un-tag "banido(a)" on the affected messages
/// live, without a full history reload.
class GroupUpdatedEvent {
  const GroupUpdatedEvent({
    required this.groupId,
    required this.group,
    this.bannedUserIds = const {},
  });

  final String groupId;
  final GroupHeader group;

  /// Full set of user ids currently banned from this group (server-authoritative).
  final Set<String> bannedUserIds;

  factory GroupUpdatedEvent.fromMap(Map<String, dynamic> data) {
    final raw = data['group'];
    final rawBanned = data['bannedUserIds'];
    return GroupUpdatedEvent(
      groupId: (data['groupId'] as String?) ?? '',
      bannedUserIds: rawBanned is List
          ? rawBanned.whereType<String>().toSet()
          : const <String>{},
      group: raw is Map<String, dynamic>
          ? GroupHeaderDto.fromJson(raw).toModel()
          : GroupHeader(
              id: (data['groupId'] as String?) ?? '',
              name: (data['name'] as String?) ?? '',
              avatarUrl: data['avatarUrl'] as String?,
              description: (data['description'] as String?) ?? '',
              createdById: (data['createdById'] as String?) ?? '',
              memberCount: (data['memberCount'] as num?)?.toInt() ?? 0,
            ),
    );
  }
}

/// The group identity block embedded in group-list items. Mirrors the
/// server's `GroupHeader` shape.
class GroupHeaderDto {
  final String id;
  final String name;
  final String? avatarUrl;
  final String description;
  final String createdById;
  final int memberCount;

  const GroupHeaderDto({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.description,
    required this.createdById,
    required this.memberCount,
  });

  GroupHeader toModel() => GroupHeader(
        id: id,
        name: name,
        avatarUrl: avatarUrl,
        description: description,
        createdById: createdById,
        memberCount: memberCount,
      );

  factory GroupHeaderDto.fromJson(Map<String, dynamic> json) => GroupHeaderDto(
        id: json['id'] as String,
        name: json['name'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        description: (json['description'] as String?) ?? '',
        createdById: json['createdById'] as String,
        memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
      );
}

/// A group member as returned by the group-info endpoint. Extended chat
/// user (id/nickname/avatar) plus a server-computed `isOwner` flag so
/// the profile screen can tag the owner without trusting the client..
class GroupMemberDto {
  final String id;
  final String nickname;
  final String? avatarUrl;
  final bool isOwner;

  const GroupMemberDto({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    required this.isOwner,
  });

  GroupMemberInfoModel toModel() => GroupMemberInfoModel(
        id: id,
        nickname: nickname,
        avatarUrl: avatarUrl,
        isOwner: isOwner,
      );

  factory GroupMemberDto.fromJson(Map<String, dynamic> json) => GroupMemberDto(
        id: json['id'] as String,
        nickname: json['nickname'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        isOwner: (json['isOwner'] as bool?) ?? false,
      );
}

/// Full group info (profile menu). `group` is the identity block used
/// everywhere;`members` is the participant list with owner tagging and
/// `bannedMembers` lists the currently-banned participants (kept separate so
/// they are never confused with active members).
class GroupInfoDto {
  final GroupHeaderDto group;
  final List<GroupMemberDto> members;
  final List<GroupMemberDto> bannedMembers;

  const GroupInfoDto({
    required this.group,
    required this.members,
    this.bannedMembers = const [],
  });

  ({
    GroupHeader group,
    List<GroupMemberInfoModel> members,
    List<GroupMemberInfoModel> bannedMembers
  }) toModel() => (
        group: group.toModel(),
        members: members.map((m) => m.toModel()).toList(),
        bannedMembers: bannedMembers.map((m) => m.toModel()).toList(),
      );

  factory GroupInfoDto.fromJson(Map<String, dynamic> json) => GroupInfoDto(
        group: GroupHeaderDto.fromJson(json['group'] as Map<String, dynamic>),
        members: ((json['members'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(GroupMemberDto.fromJson)
            .toList(),
        bannedMembers: ((json['bannedMembers'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(GroupMemberDto.fromJson)
            .toList(),
      );
}

/// A group conversation (list item). Mirrors the server's
/// `GroupConversationItem` shape so the Chat tab can render groups and DMs
/// in the same merged, sorted list.
class GroupConversationDto {
  final String id;
  final GroupHeaderDto group;
  final ConversationLastMessageDto? lastMessage;
  final bool lastMine;
  final int unreadCount;
  final DateTime updatedAt;
  final bool mentioned;

  const GroupConversationDto({
    required this.id,
    required this.group,
    this.lastMessage,
    required this.lastMine,
    required this.unreadCount,
    required this.updatedAt,
    this.mentioned = false,
  });

  GroupConversation toModel() => GroupConversation(
        id: id,
        group: group.toModel(),
        lastMessage: lastMessage?.toModel(),
        lastMine: lastMine,
        unreadCount: unreadCount,
        updatedAt: updatedAt,
        mentioned: mentioned,
      );

  factory GroupConversationDto.fromJson(Map<String, dynamic> json) {
    final last = json['lastMessage'];
    return GroupConversationDto(
      id: json['id'] as String,
      group: GroupHeaderDto.fromJson(json['group'] as Map<String, dynamic>),
      lastMessage: last is Map<String, dynamic>
          ? ConversationLastMessageDto.fromJson(last)
          : null,
      lastMine: (json['lastMine'] as bool?) ?? false,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      mentioned: (json['mentioned'] as bool?) ?? false,
    );
  }
}

/// A paginated messages page: the chronological batch plus whether older
/// messages exist to paginate into (`before`).
class MessagePageDto {
  final List<ChatMessage> messages;
  final bool hasMore;

  const MessagePageDto({required this.messages, required this.hasMore});

  factory MessagePageDto.fromJson(Map<String, dynamic> json) => MessagePageDto(
        messages: (json['messages'] as List)
            .cast<Map<String, dynamic>>()
            .map(ChatMessageDto.fromJson)
            .map((d) => d.toModel())
            .toList(),
        hasMore: (json['hasMore'] as bool?) ?? false,
      );
}

/// A single sticker from the server catalog.
class StickerDto {
  final String id;
  final String packageId;
  final int order;
  final String fileUrl;
  final String? thumbUrl;
  final int? width;
  final int? height;
  final bool favorited;

  const StickerDto({
    required this.id,
    required this.packageId,
    required this.order,
    required this.fileUrl,
    this.thumbUrl,
    this.width,
    this.height,
    this.favorited = false,
  });

  Sticker toModel() => Sticker(
        id: id,
        packageId: packageId,
        order: order,
        fileUrl: fileUrl,
        thumbUrl: thumbUrl,
        width: width,
        height: height,
        favorited: favorited,
      );

  factory StickerDto.fromJson(Map<String, dynamic> json) => StickerDto(
        id: json['id'] as String,
        packageId: json['packageId'] as String,
        order: (json['order'] as num?)?.toInt() ?? 0,
        fileUrl: json['fileUrl'] as String,
        thumbUrl: json['thumbUrl'] as String?,
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
        favorited: (json['favorited'] as bool?) ?? false,
      );
}

/// A sticker package (catalog entry) with its stickers + user install state.
class StickerPackageDto {
  final String id;
  final String name;
  final String slug;
  final String description;
  final String author;
  final String iconUrl;
  final bool installed;
  final int stickerCount;
  final List<Sticker> stickers;

  const StickerPackageDto({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.author,
    required this.iconUrl,
    required this.installed,
    required this.stickerCount,
    required this.stickers,
  });

  StickerPackage toModel() => StickerPackage(
        id: id,
        name: name,
        slug: slug,
        description: description,
        author: author,
        iconUrl: iconUrl,
        installed: installed,
        stickerCount: stickerCount,
        stickers: stickers,
      );

  factory StickerPackageDto.fromJson(Map<String, dynamic> json) =>
      StickerPackageDto(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        description: json['description'] as String? ?? '',
        author: json['author'] as String? ?? '',
        iconUrl: json['iconUrl'] as String? ?? '',
        installed: (json['installed'] as bool?) ?? false,
        stickerCount: (json['stickerCount'] as num?)?.toInt() ?? 0,
        stickers: (json['stickers'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(StickerDto.fromJson)
            .map((d) => d.toModel())
            .toList(),
      );
}
