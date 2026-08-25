/// A MATRIX notification (like, comment, friend request, friend accepted).
///
/// The server owns notification creation; the APK only renders them. Every
/// notification embeds the acting user (actor) so no second lookup is
/// needed, and may reference a post / comment / friend request.
class MatrixNotification {
  const MatrixNotification({
    required this.id,
    required this.type,
    required this.read,
    required this.createdAt,
    required this.actorId,
    required this.actorName,
    required this.actorUsername,
    this.actorAvatarUrl,
    this.actorNameColor,
    this.postId,
    this.commentId,
    this.friendRequestId,
    this.friendRequestStatus,
  });

  final String id;

  /// LIKE | COMMENT | FRIEND_REQUEST | FRIEND_ACCEPTED — extensible on the
  /// server, so we keep it as a plain string.
  final String type;
  final bool read;
  final DateTime createdAt;

  final String actorId;
  final String actorName;
  final String actorUsername;
  final String? actorAvatarUrl;

  /// The ACTOR's own nickname color (hex), embedded by the server. Null →
  /// default color.
  final String? actorNameColor;

  final String? postId;
  final String? commentId;
  final String? friendRequestId;

  /// Current status of the referenced friend request (e.g. PENDING). Null
  /// for non-request types. Used to decide if the actionable card shows.
  final String? friendRequestStatus;

  MatrixNotification copyWith({bool? read}) => MatrixNotification(
        id: id,
        type: type,
        read: read ?? this.read,
        createdAt: createdAt,
        actorId: actorId,
        actorName: actorName,
        actorUsername: actorUsername,
        actorAvatarUrl: actorAvatarUrl,
        actorNameColor: actorNameColor,
        postId: postId,
        commentId: commentId,
        friendRequestId: friendRequestId,
        friendRequestStatus: friendRequestStatus,
      );
}
