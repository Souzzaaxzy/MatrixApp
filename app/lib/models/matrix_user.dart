/// A MATRIX network user.
class MatrixUser {
  const MatrixUser({
    required this.id,
    required this.name,
    required this.username,
    this.bio = '',
    this.avatarSeed,
    this.avatarUrl,
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

  MatrixUser copyWith({
    String? name,
    String? username,
    String? bio,
    String? avatarSeed,
    String? avatarUrl,
  }) =>
      MatrixUser(
        id: id,
        name: name ?? this.name,
        username: username ?? this.username,
        bio: bio ?? this.bio,
        avatarSeed: avatarSeed ?? this.avatarSeed,
        avatarUrl: avatarUrl ?? this.avatarUrl,
      );
}
