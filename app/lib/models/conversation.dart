import 'cosmetic_item.dart';

/// A lightweight user reference embedded in chat payloads (the OTHER side of
/// a conversation). Carries the owner's nickname cosmetics so chat renders
/// each user's own color/frame, same as every other surface.
class ChatUser {
  const ChatUser({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    this.nameColor,
    this.frameId,
    this.frameAsset,
  });

  final String id;
  final String nickname;
  final String? avatarUrl;
  final String? nameColor;
  final String? frameId;
  final String? frameAsset;

  /// The equipped AVATAR_FRAME as a cosmetic (mirrors MatrixUser.frame).
  CosmeticItem? get frame {
    final id = frameId;
    if (id == null) return null;
    return CosmeticItem(
      id: id,
      slot: CosmeticItem.avatarFrame,
      name: id,
      assetUrl: frameAsset ?? '',
    );
  }
}

/// One private conversation as returned by the server. `otherUser` is always
/// the OTHER participant (never the session user); `lastMessage` is non-null
/// only after the first message was exchanged.
class Conversation {
  const Conversation({
    required this.id,
    required this.otherUser,
    this.lastMessage,
    required this.lastMine,
    required this.unreadCount,
    required this.updatedAt,
  });

  final String id;
  final ChatUser otherUser;
  final ConversationLastMessage? lastMessage;
  final bool lastMine;
  final int unreadCount;
  final DateTime updatedAt;

  Conversation copyWith({
    String? id,
    ChatUser? otherUser,
    ConversationLastMessage? lastMessage,
    bool? lastMine,
    int? unreadCount,
    DateTime? updatedAt,
  }) =>
      Conversation(
        id: id ?? this.id,
        otherUser: otherUser ?? this.otherUser,
        lastMessage: lastMessage ?? this.lastMessage,
        lastMine: lastMine ?? this.lastMine,
        unreadCount: unreadCount ?? this.unreadCount,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class ConversationLastMessage {
  const ConversationLastMessage({
    required this.id,
    required this.content,
    required this.senderId,
    required this.createdAt,
    this.senderNickname,
  });

  final String id;
  final String content;
  final String senderId;
  final DateTime createdAt;

  /// The sender's nickname preview (group lists only; null for private DMs,
  /// where the list card already shows the peer's photo + name).
  final String? senderNickname;
}

/// A single message — private chat (has [conversationId]) or group chat
/// (has [groupId]). Group messages embed the real sender's compact identity
/// ([sender], ChatUser) so every bubble can be labeled without a per-message
/// lookup; private messages leave it null (the peer is already known).
class ChatMessage {
  const ChatMessage({
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
  });

  final String id;
  final String? conversationId;
  final String? groupId;

  /// The real sender's compact identity (group messages only; null for DMs).
  final ChatUser? sender;

  final String senderId;
  final String content;
  final DateTime createdAt;
  final bool mine;

  /// When the RECIPIENT of this message read it (drives "enviado" → "visto
  /// agora" inside the sender's last bubble). Null while still unread.
  final DateTime? readAt;

  /// The original message this one answers (server-resolved preview). Null
  /// when not a reply. [ReplyInfo.exists] is false when the original was
  /// deleted (renders a graceful placeholder instead of breaking).
  final ReplyInfo? replyTo;

  /// "text" (default) | "voice". Voice messages render the inline player
  /// via [audioUrl]/[durationMs] instead of plain content.
  final String type;

  /// Absolute URL of the persisted voice-message audio file (voice only).
  final String? audioUrl;

  /// Recorded length in milliseconds (voice only).
  final int? durationMs;

  bool get isVoice => type == 'voice';

  ChatMessage copyWith({
    DateTime? readAt,
    ReplyInfo? replyTo,
    String? type,
    String? audioUrl,
    int? durationMs,
    ChatUser? sender,
  }) =>
      ChatMessage(
        id: id,
        conversationId: conversationId,
        groupId: groupId,
        sender: sender ?? this.sender,
        senderId: senderId,
        content: content,
        createdAt: createdAt,
        mine: mine,
        readAt: readAt ?? this.readAt,
        replyTo: replyTo ?? this.replyTo,
        type: type ?? this.type,
        audioUrl: audioUrl ?? this.audioUrl,
        durationMs: durationMs ?? this.durationMs,
      );
}

/// A group as returned by the server's group-list endpoint. Carries the full
/// identity (name, photo, description, creator, member count) plus the
/// last-message preview and unread state, mirroring [Conversation] so the
/// Chat tab can render DMs and groups in the same list.
class GroupConversation {
  const GroupConversation({
    required this.id,
    required this.group,
    this.lastMessage,
    required this.lastMine,
    required this.unreadCount,
    required this.updatedAt,
  });

  final String id;
  final GroupHeader group;
  final ConversationLastMessage? lastMessage;
  final bool lastMine;
  final int unreadCount;
  final DateTime updatedAt;

  GroupConversation copyWith({
    String? id,
    GroupHeader? group,
    ConversationLastMessage? lastMessage,
    bool? lastMine,
    int? unreadCount,
    DateTime? updatedAt,
  }) =>
      GroupConversation(
        id: id ?? this.id,
        group: group ?? this.group,
        lastMessage: lastMessage ?? this.lastMessage,
        lastMine: lastMine ?? this.lastMine,
        unreadCount: unreadCount ?? this.unreadCount,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// The identity block of a group (list/detail common subset).
class GroupHeader {
  const GroupHeader({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.description,
    required this.createdById,
    required this.memberCount,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final String description;
  final String createdById;
  final int memberCount;

  GroupHeader copyWith({
    String? name,
    String? avatarUrl,
    String? description,
    String? createdById,
    int? memberCount,
  }) =>
      GroupHeader(
        id: id,
        name: name ?? this.name,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        description: description ?? this.description,
        createdById: createdById ?? this.createdById,
        memberCount: memberCount ?? this.memberCount,
      );
}

/// Server-resolved preview of the original message a reply points at. Only
/// the preview is transmitted — never a duplicate of the original row.
class ReplyInfo {
  const ReplyInfo({
    required this.id,
    required this.senderId,
    required this.senderNickname,
    required this.content,
    required this.exists,
  });

  final String id;
  final String senderId;
  final String senderNickname;
  final String content;

  /// False when the original message was deleted (still renders a
  /// "mensagem apagada" placeholder rather than breaking the view).
  final bool exists;
}

/// A single group participant (profile menu). Avatar/nickname plus a
/// server-computed owner flag — identity never inferred client-side..
class GroupMemberInfoModel {
  const GroupMemberInfoModel({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    required this.isOwner,
  });

  final String id;
  final String nickname;
  final String? avatarUrl;
  final bool isOwner;
}