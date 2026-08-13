/// A MATRIX network user.
class MatrixUser {
  const MatrixUser({
    required this.id,
    required this.name,
    required this.username,
    this.bio = '',
    this.avatarSeed,
  });

  final String id;
  final String name;
  final String username;
  final String bio;
  final String? avatarSeed;

  MatrixUser copyWith({
    String? name,
    String? username,
    String? bio,
    String? avatarSeed,
  }) =>
      MatrixUser(
        id: id,
        name: name ?? this.name,
        username: username ?? this.username,
        bio: bio ?? this.bio,
        avatarSeed: avatarSeed ?? this.avatarSeed,
      );
}
