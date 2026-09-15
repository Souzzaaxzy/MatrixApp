import '../api_client.dart';
import '../dtos/dtos.dart';
import '../../models/conversation.dart';
import '../../models/story.dart';

/// Story (24h ephemeral media) repository — the data layer for the feed
/// header's Stories strip.
///
/// Talks ONLY to the existing MATRIX API (same auth/storage stack the feed
/// uses): stories reference media already uploaded through the standard
/// `/api/uploads` endpoints, so no second media pipeline exists.
class StoryRepository {
  StoryRepository(this._api);

  final ApiClient _api;

  /// Active stories (not expired), grouped by author, unviewed-first.
  Future<List<StoryGroup>> active() async {
    final json = await _api.get<Map<String, dynamic>>('/api/stories');
    return StoryGroupsDto.fromJson(json).groups;
  }

  /// Publishes a story. `mediaUrl`/`thumbnailUrl` come from the EXISTING
  /// uploads repository; expiry is decided server-side (24h).
  ///
  /// [type] is 'image' | 'video' | 'text'. A TEXT story sends `text` and no
  /// media — ONE endpoint/shape for every kind (no parallel stories API).
  Future<Story> create({
    String type = 'image',
    String? mediaUrl,
    String mediaType = 'image',
    String text = '',
    String? thumbnailUrl,
    String caption = '',
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/api/stories',
      data: {
        'type': type,
        'mediaType': mediaType,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (type == 'text' && text.trim().isNotEmpty) 'text': text.trim(),
        if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
        if (caption.trim().isNotEmpty) 'caption': caption.trim(),
      },
    );
    return StoryDto.fromJson(json).toModel();
  }

  /// Toggles the session user's like on a story. SAME semantics as the feed
  /// chain (server enforces one like per user+story).
  Future<({bool liked, int likeCount})> toggleLike(String storyId) async {
    final json = await _api.post<Map<String, dynamic>>('/api/stories/$storyId/like');
    return (
      liked: (json['liked'] as bool?) ?? false,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Replies to a story. The server turns it into a REAL direct message to
  /// the story's author and returns the created message + conversation, so
  /// the app can open/refresh that chat.
  Future<({ChatMessage message, String conversationId})> reply(
    String storyId,
    String text,
  ) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/api/stories/$storyId/reply',
      data: {'text': text.trim()},
    );
    return (
      message: ChatMessageDto.fromJson(json['message'] as Map<String, dynamic>)
          .toModel(),
      conversationId: (json['conversationId'] as String?) ?? '',
    );
  }

  /// Marks the story as seen by the session user (idempotent).
  Future<void> markViewed(String storyId) async {
    await _api.post('/api/stories/$storyId/view');
  }

  /// Deletes the session user's own story (server enforces ownership).
  Future<void> delete(String storyId) async {
    await _api.delete('/api/stories/$storyId');
  }
}
