/// A chat message in the Akame conversation.
class AkameMessage {
  AkameMessage({
    required this.id,
    required this.text,
    required this.fromUser,
    required this.createdAt,
  });

  final String id;
  final String text;
  final bool fromUser;
  final DateTime createdAt;
}
