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
  });

  final String id;
  final String content;
  final String senderId;
  final DateTime createdAt;
}

/// A single private message.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    required this.mine,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final DateTime createdAt;
  final bool mine;
}