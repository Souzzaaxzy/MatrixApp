import 'cosmetic_item.dart';

/// A MATRIX network user.
class MatrixUser {
  const MatrixUser({
    required this.id,
    required this.name,
    required this.username,
    this.bio = '',
    this.avatarSeed,
    this.avatarUrl,
    this.friendsCount = 0,
    this.postsCount = 0,
    this.customization = const {},
  });

  final String id;
  final String name;
  final String username;
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

  /// The equipped cosmetic for [slot], or null (default rendering).
  CosmeticItem? cosmetic(String slot) => customization[slot];

  MatrixUser copyWith({
    String? name,
    String? username,
    String? bio,
    String? avatarSeed,
    String? avatarUrl,
    int? friendsCount,
    int? postsCount,
    CosmeticMap? customization,
  }) =>
      MatrixUser(
        id: id,
        name: name ?? this.name,
        username: username ?? this.username,
        bio: bio ?? this.bio,
        avatarSeed: avatarSeed ?? this.avatarSeed,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        friendsCount: friendsCount ?? this.friendsCount,
        postsCount: postsCount ?? this.postsCount,
        customization: customization ?? this.customization,
      );
}
