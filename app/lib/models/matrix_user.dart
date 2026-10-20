import 'conversation.dart';
import 'profile_music.dart';

/// A MATRIX network user.
class MatrixUser {
  const MatrixUser({
    required this.id,
    required this.nickname,
    this.bio = '',
    this.avatarSeed,
    this.avatarUrl,
    this.bannerUrl,
    this.publicId,
    this.publicIdLabel,
    this.friendsCount = 0,
    this.postsCount = 0,
    this.music,
  });

  final String id;

  /// The single visual identity of the user. Rendered everywhere as plain
  /// text (never prefixed with '@'). Legacy name/username were merged into
  /// this field by the identity migration.
  final String nickname;
  final String bio;

  /// Seed for the deterministic gradient/initials fallback avatar.
  final String? avatarSeed;

  /// Remote profile photo URL (served by the API). When null, the
  /// fallback initials avatar is shown.
  final String? avatarUrl;

  /// Wide profile banner (cover image) URL, served by the API. When null the
  /// profile screen draws its default gradient cover instead.
  final String? bannerUrl;

  /// Public sequential identifier (`#00000001`). Null when the payload did not
  /// include it (e.g. a lighter author fragment) — the UI simply omits it.
  final int? publicId;

  /// The public id already formatted for display (`#00000001`), as sent by the
  /// server. Preferred over building it locally so the server stays the single
  /// source of truth for the format.
  final String? publicIdLabel;

  /// The `#id` to show, or null when unknown.
  String? get publicIdText =>
      publicIdLabel ?? (publicId != null ? '#${publicId!.toString().padLeft(8, '0')}' : null);

  /// Real server-side counters (profile endpoint only): accepted
  /// friendships and posts owned by this user. Zero when the endpoint did
  /// not return them (e.g. search results) — the profile screen only
  /// renders counters after a profile load.
  final int friendsCount;
  final int postsCount;





  /// The song pinned to this profile (Instagram-style), or null when the
  /// user has none. Comes from the profile endpoint only — lighter author
  /// payloads (feed, search) do not carry it.
  final ProfileMusic? music;

  /// A lightweight [ChatUser] reference (same identity) used to open
  /// conversations from search results/friends/profile.
  ChatUser toChatUser() => ChatUser(
        id: id,
        nickname: nickname,
        avatarUrl: avatarUrl,
      );

  MatrixUser copyWith({
    String? nickname,
    String? bio,
    String? avatarSeed,
    String? avatarUrl,
    int? friendsCount,
    int? postsCount,
    String? Function()? bannerUrl,
    int? Function()? publicId,
    String? Function()? publicIdLabel,
    ProfileMusic? Function()? music,
  }) =>
      MatrixUser(
        id: id,
        nickname: nickname ?? this.nickname,
        bio: bio ?? this.bio,
        avatarSeed: avatarSeed ?? this.avatarSeed,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        friendsCount: friendsCount ?? this.friendsCount,
        postsCount: postsCount ?? this.postsCount,
        // Same nullable-resolver pattern so the banner can be cleared
        // (`bannerUrl: () => null`) as well as replaced.
        bannerUrl: bannerUrl != null ? bannerUrl() : this.bannerUrl,
        publicId: publicId != null ? publicId() : this.publicId,
        publicIdLabel: publicIdLabel != null ? publicIdLabel() : this.publicIdLabel,
        // Resolver so the pinned song can be CLEARED (`music: () => null`),
        // not just replaced.
        music: music != null ? music() : this.music,
      );
}
