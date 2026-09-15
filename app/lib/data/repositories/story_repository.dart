import '../api_client.dart';
import '../dtos/dtos.dart';
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
  Future<Story> create({
    required String mediaUrl,
    required String mediaType,
    String? thumbnailUrl,
    String caption = '',
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/api/stories',
      data: {
        'mediaUrl': mediaUrl,
        'mediaType': mediaType,
        if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
        if (caption.trim().isNotEmpty) 'caption': caption.trim(),
      },
    );
    return StoryDto.fromJson(json).toModel();
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
