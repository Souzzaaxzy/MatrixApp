/// A Story in the MATRIX feed header — ephemeral media that expires 24h
/// after publication.
///
/// Reuses the SAME identity a post author carries (nickname + avatar +
/// cosmetics), so the card renders with the existing avatar widget and
/// nickname renderer — no second avatar/user system.
class Story {
  const Story({
    required this.id,
    required this.authorId,
    required this.authorNickname,
    required this.authorAvatarUrl,
    required this.mediaUrl,
    required this.mediaType,
    required this.createdAt,
    required this.expiresAt,
    this.authorNicknameColor,
    this.authorFrameId,
    this.authorFrameAsset,
    this.thumbnailUrl,
    this.caption = '',
    this.viewed = false,
    this.mine = false,
  });

  final String id;

  /// Stable server-side id of the author (nickname is mutable).
  final String authorId;
  final String authorNickname;

  /// Remote profile photo URL of the author (null → initials fallback).
  final String? authorAvatarUrl;

  /// The AUTHOR's own nickname color (hex). Null → default.
  final String? authorNicknameColor;

  /// The AUTHOR's equipped profile frame (asset key). Null → default.
  final String? authorFrameId;
  final String? authorFrameAsset;

  /// Image OR video reference (absolute or API-relative `/static/...`).
  final String mediaUrl;

  /// `image` | `video` — drives the viewer (video autoplays muted).
  final String mediaType;

  /// Cover of a VIDEO story when available.
  final String? thumbnailUrl;

  final String caption;
  final DateTime createdAt;

  /// Server-computed expiry (createdAt + 24h). The app never decides this.
  final DateTime expiresAt;

  /// Whether the SESSION user already opened this story (discrete ring).
  final bool viewed;

  /// Whether the SESSION user is the author (drives the delete action).
  final bool mine;

  bool get isVideo => mediaType == 'video';

  /// Best still image for the card: the cover when present, else the media.
  String get coverUrl => thumbnailUrl ?? mediaUrl;
}

/// Active stories of ONE author, as the horizontal header consumes them.
class StoryGroup {
  const StoryGroup({
    required this.authorId,
    required this.authorNickname,
    required this.authorAvatarUrl,
    required this.stories,
    required this.allViewed,
    this.authorNicknameColor,
    this.authorFrameId,
    this.authorFrameAsset,
  });

  final String authorId;
  final String authorNickname;
  final String? authorAvatarUrl;
  final String? authorNicknameColor;
  final String? authorFrameId;
  final String? authorFrameAsset;

  /// Newest-first.
  final List<Story> stories;

  /// True when the session user has seen every story of this author.
  final bool allViewed;

  /// A flat, newest-first list of this author's story ids (viewer order).
  List<Story> get ordered => stories;
}
