import 'matrix_user.dart';

/// A pending friend request received by the current user, with the sender
/// embedded. The actionable card (Aceitar / Recusar) is rendered from this.
class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.sender,
    this.receiverId = '',
  });

  final String id;
  final String status; // PENDING | ACCEPTED | REJECTED
  final DateTime createdAt;
  final MatrixUser sender;

  /// Receiver id (kept from the wire when available; optional for the app).
  final String receiverId;
}

/// Friendship relationship between the viewer and a profile's owner — maps
/// to the friendship button states (Seguir / Solicitado / Amigos).
enum Friendship {
  none,
  outgoingPending,
  incomingPending,
  friends;

  static Friendship fromApi(String? value) {
    switch (value) {
      case 'OUTGOING_PENDING':
        return Friendship.outgoingPending;
      case 'INCOMING_PENDING':
        return Friendship.incomingPending;
      case 'FRIENDS':
        return Friendship.friends;
      default:
        return Friendship.none;
    }
  }
}
