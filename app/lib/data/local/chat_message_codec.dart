import 'dart:convert';

import '../../models/conversation.dart';

/// JSON serialization for [ChatMessage] ↔ the local message store.
///
/// WHY THIS EXISTS
/// The phone is the source of truth for chat history, so every message has to
/// survive a round-trip through SQLite with NO field loss. Hand-writing that
/// mapping column-by-column is exactly the kind of code that silently drops a
/// field (the same class of bug that once turned a text Story into an empty
/// image), so the whole message is stored as ONE JSON document plus the few
/// columns needed for querying (ids, timestamps, flags).
class ChatMessageCodec {
  ChatMessageCodec._();

  static String encode(ChatMessage m) => jsonEncode({
        'id': m.id,
        'conversationId': m.conversationId,
        'groupId': m.groupId,
        'senderId': m.senderId,
        'content': m.content,
        'createdAt': m.createdAt.toIso8601String(),
        'mine': m.mine,
        if (m.readAt != null) 'readAt': m.readAt!.toIso8601String(),
        'type': m.type,
        if (m.audioUrl != null) 'audioUrl': m.audioUrl,
        if (m.durationMs != null) 'durationMs': m.durationMs,
        if (m.imageUrl != null) 'imageUrl': m.imageUrl,
        if (m.videoUrl != null) 'videoUrl': m.videoUrl,
        if (m.stickerUrl != null) 'stickerUrl': m.stickerUrl,
        if (m.stickerId != null) 'stickerId': m.stickerId,
        if (m.stickerPackageId != null) 'stickerPackageId': m.stickerPackageId,
        if (m.sender != null) 'sender': _encodeSender(m.sender!),
        if (m.replyTo != null) 'replyTo': _encodeReply(m.replyTo!),
        if (m.story != null) 'story': _encodeStory(m.story!),
        if (m.mentions.isNotEmpty)
          'mentions': m.mentions
              .map((x) => {
                    'userId': x.userId,
                    'nickname': x.nickname,
                    if (x.all) 'all': true,
                    if (x.start != null) 'start': x.start,
                    if (x.end != null) 'end': x.end,
                  })
              .toList(),
        if (m.mentionAll) 'mentionAll': true,
        if (m.mentioned) 'mentioned': true,
      });

  static ChatMessage decode(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return ChatMessage(
      id: j['id'] as String,
      conversationId: j['conversationId'] as String?,
      groupId: j['groupId'] as String?,
      senderId: (j['senderId'] as String?) ?? '',
      content: (j['content'] as String?) ?? '',
      createdAt: DateTime.tryParse((j['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      mine: (j['mine'] as bool?) ?? false,
      readAt:
          j['readAt'] != null ? DateTime.tryParse(j['readAt'] as String) : null,
      type: (j['type'] as String?) ?? 'text',
      audioUrl: j['audioUrl'] as String?,
      durationMs: (j['durationMs'] as num?)?.toInt(),
      imageUrl: j['imageUrl'] as String?,
      videoUrl: j['videoUrl'] as String?,
      stickerUrl: j['stickerUrl'] as String?,
      stickerId: j['stickerId'] as String?,
      stickerPackageId: j['stickerPackageId'] as String?,
      sender: j['sender'] != null
          ? _decodeSender(j['sender'] as Map<String, dynamic>)
          : null,
      replyTo: j['replyTo'] != null
          ? _decodeReply(j['replyTo'] as Map<String, dynamic>)
          : null,
      story: j['story'] != null
          ? _decodeStory(j['story'] as Map<String, dynamic>)
          : null,
      mentions: ((j['mentions'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_decodeMention)
          .toList(),
      mentionAll: (j['mentionAll'] as bool?) ?? false,
      mentioned: (j['mentioned'] as bool?) ?? false,
    );
  }

  static Map<String, dynamic> _encodeSender(ChatUser u) => {
        'id': u.id,
        'nickname': u.nickname,
        if (u.avatarUrl != null) 'avatarUrl': u.avatarUrl,
      };

  static ChatUser _decodeSender(Map<String, dynamic> j) => ChatUser(
        id: (j['id'] as String?) ?? '',
        nickname: (j['nickname'] as String?) ?? '',
        avatarUrl: j['avatarUrl'] as String?,

      );

  static Map<String, dynamic> _encodeReply(ReplyInfo r) => {
        'id': r.id,
        'senderId': r.senderId,
        'senderNickname': r.senderNickname,
        'content': r.content,
        'exists': r.exists,
      };

  static ReplyInfo _decodeReply(Map<String, dynamic> j) => ReplyInfo(
        id: (j['id'] as String?) ?? '',
        senderId: (j['senderId'] as String?) ?? '',
        senderNickname: (j['senderNickname'] as String?) ?? '',
        content: (j['content'] as String?) ?? '',
        exists: (j['exists'] as bool?) ?? true,
      );

  static Map<String, dynamic> _encodeStory(StoryReference s) => {
        'storyId': s.storyId,
        'type': s.type,
        if (s.thumbnailUrl != null) 'thumbnailUrl': s.thumbnailUrl,
        'preview': s.preview,
      };

  static StoryReference _decodeStory(Map<String, dynamic> j) => StoryReference(
        storyId: (j['storyId'] as String?) ?? '',
        type: (j['type'] as String?) ?? 'image',
        thumbnailUrl: j['thumbnailUrl'] as String?,
        preview: (j['preview'] as String?) ?? '',
      );

  static ChatMention _decodeMention(Map<String, dynamic> j) => ChatMention(
        userId: (j['userId'] as String?) ?? '',
        nickname: (j['nickname'] as String?) ?? '',
        all: (j['all'] as bool?) ?? false,
        start: (j['start'] as num?)?.toInt(),
        end: (j['end'] as num?)?.toInt(),
      );
}
