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
    this.type = 'image',
    this.text = '',
    this.thumbnailUrl,
    this.caption = '',
    this.viewed = false,
    this.mine = false,
    this.liked = false,
    this.likeCount = 0,
  });

  final String id;

  /// Stable server-side id of the author (nickname is mutable).
  final String authorId;
  final String authorNickname;

  /// Remote profile photo URL of the author (null → initials fallback).
  final String? authorAvatarUrl;

  /// The AUTHOR's own nickname color (hex). Null → default.

  /// The AUTHOR's equipped profile frame (asset key). Null → default.

  /// 'image' | 'video' | 'text' — ONE shape for every story kind.
  final String type;

  /// Image OR video reference (absolute or API-relative `/static/...`).
  /// Null for a TEXT story (which carries [text] instead).
  final String? mediaUrl;

  /// Text content (TEXT stories only; empty otherwise).
  final String text;

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

  bool get isVideo => type == 'video' || mediaType == 'video';
  bool get isText => type == 'text';

  /// Best still image for the card/viewer: the cover when present, else the
  /// media. Empty for a text story (rendered as text instead).
  String get coverUrl => thumbnailUrl ?? mediaUrl ?? '';

  /// Whether the SESSION user liked this story (same semantics as the feed).
  final bool liked;
  final int likeCount;

  /// Copies this story with a few fields replaced.
  ///
  /// Exists because rebuilding a [Story] field-by-field is error-prone: a
  /// forgotten field silently degrades the story (a TEXT story rebuilt without
  /// `type`/`text` renders as an empty IMAGE — the "broken picture" bug).
  /// Always prefer this over hand-written constructors.
  Story copyWith({
    String? id,
    String? authorId,
    String? authorNickname,
    String? authorAvatarUrl,
    String? authorNicknameColor,
    String? authorFrameId,
    String? authorFrameAsset,
    String? type,
    String? text,
    String? mediaType,
    String? caption,
    DateTime? createdAt,
    DateTime? expiresAt,
    bool? viewed,
    bool? mine,
    bool? liked,
    int? likeCount,
    // Nullable resolvers so these can be explicitly CLEARED too.
    String? Function()? mediaUrl,
    String? Function()? thumbnailUrl,
  }) =>
      Story(
        id: id ?? this.id,
        authorId: authorId ?? this.authorId,
        authorNickname: authorNickname ?? this.authorNickname,
        authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
        type: type ?? this.type,
        text: text ?? this.text,
        mediaType: mediaType ?? this.mediaType,
        mediaUrl: mediaUrl != null ? mediaUrl() : this.mediaUrl,
        thumbnailUrl: thumbnailUrl != null ? thumbnailUrl() : this.thumbnailUrl,
        caption: caption ?? this.caption,
        createdAt: createdAt ?? this.createdAt,
        expiresAt: expiresAt ?? this.expiresAt,
        viewed: viewed ?? this.viewed,
        mine: mine ?? this.mine,
        liked: liked ?? this.liked,
        likeCount: likeCount ?? this.likeCount,
      );
}

/// Active stories of ONE author, as the horizontal header consumes them.
class StoryGroup {
  const StoryGroup({
    required this.authorId,
    required this.authorNickname,
    required this.authorAvatarUrl,
    required this.stories,
    required this.allViewed,
  });

  final String authorId;
  final String authorNickname;
  final String? authorAvatarUrl;

  /// Newest-first.
  final List<Story> stories;

  /// True when the session user has seen every story of this author.
  final bool allViewed;

  /// A flat, newest-first list of this author's story ids (viewer order).
  List<Story> get ordered => stories;
}
