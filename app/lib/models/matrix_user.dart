import 'conversation.dart';
import 'cosmetic_item.dart';

/// A MATRIX network user.
class MatrixUser {
  const MatrixUser({
    required this.id,
    required this.nickname,
    this.bio = '',
    this.avatarSeed,
    this.avatarUrl,
    this.friendsCount = 0,
    this.postsCount = 0,
    this.customization = const {},
    this.nameColor,
    this.frameId,
    this.frameAsset,
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

  /// Real server-side counters (profile endpoint only): accepted
  /// friendships and posts owned by this user. Zero when the endpoint did
  /// not return them (e.g. search results) — the profile screen only
  /// renders counters after a profile load.
  final int friendsCount;
  final int postsCount;

  /// Equipped cosmetics of THIS user, keyed by slot (AVATAR_FRAME, BADGE,
  /// ...). Comes from the profile endpoint; empty when nothing is equipped
  /// or when the endpoint did not include it (search results, friends).
  final CosmeticMap customization;

  /// Resolved nickname color (hex, e.g. "#0066FF") of THIS user, embedded
  /// by the server in every payload that renders a user. Null → the
  /// default MATRIX nickname color. The color belongs to the user, never
  /// to the viewer: profiles/posts/comments carry the OWNER's value.
  final String? nameColor;

  /// The equipped AVATAR_FRAME catalog id (e.g. `frame_coroa`), embedded by
  /// the server. Null → "Nenhuma" (default avatar look).
  final String? frameId;

  /// The equipped frame asset key (`frames/coroa`), embedded by the server.
  /// Maps to the bundled sprite via [frameAssetPath]. Null → no frame.
  final String? frameAsset;

  /// The equipped cosmetic for [slot], or null (default rendering).
  CosmeticItem? cosmetic(String slot) => customization[slot];

  /// The equipped frame cosmetic, or null when nothing is equipped.
  /// Prefers the rich `customization.AVATAR_FRAME` entry (profile photos
  /// carry it); falls back to the flat `frameId`/`frameAsset` fragment that
  /// lighter author payloads (feed, search) embed.
  CosmeticItem? get frame =>
      cosmetic(CosmeticItem.avatarFrame) ?? _frameFromFlat();

  CosmeticItem? _frameFromFlat() {
    final id = frameId;
    if (id == null) return null;
    return CosmeticItem(
      id: id,
      slot: CosmeticItem.avatarFrame,
      name: id,
      assetUrl: frameAsset ?? '',
    );
  }

  /// A lightweight [ChatUser] reference (same identity, nickname cosmetics)
  /// used to open conversations from search results/friends/profile.
  ChatUser toChatUser() => ChatUser(
        id: id,
        nickname: nickname,
        avatarUrl: avatarUrl,
        nameColor: nameColor,
        frameId: frameId,
        frameAsset: frameAsset,
      );

  MatrixUser copyWith({
    String? nickname,
    String? bio,
    String? avatarSeed,
    String? avatarUrl,
    int? friendsCount,
    int? postsCount,
    CosmeticMap? customization,
    String? Function()? nameColor,
    String? Function()? frameId,
    String? Function()? frameAsset,
  }) =>
      MatrixUser(
        id: id,
        nickname: nickname ?? this.nickname,
        bio: bio ?? this.bio,
        avatarSeed: avatarSeed ?? this.avatarSeed,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        friendsCount: friendsCount ?? this.friendsCount,
        postsCount: postsCount ?? this.postsCount,
        customization: customization ?? this.customization,
        // Nullable resolver so a copy can explicitly CLEAR the color
        // (back to default) — `nameColor: () => null`.
        nameColor: nameColor != null ? nameColor() : this.nameColor,
        frameId: frameId != null ? frameId() : this.frameId,
        frameAsset: frameAsset != null ? frameAsset() : this.frameAsset,
      );
}
