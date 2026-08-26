import '../../models/akame_message.dart';
import '../../models/comment.dart';
import '../../models/matrix_user.dart';
import '../../models/post.dart';

/// Local mocked data for Phase 1.
///
/// This is intentionally a plain Dart service so it can be swapped later
/// for a real backend/repository implementation without touching the UI.
class MockDataService {
  MockDataService._();

  static const MatrixUser currentUser = MatrixUser(
    id: 'u0',
    nickname: 'leonardo',
    bio: 'Construindo o futuro, uma linha por vez. ⚡',
    avatarSeed: 'leonardo',
  );

  static List<Post> initialPosts() {
    final now = DateTime.now();
    return [
      Post(
        id: 'p1',
        authorNickname: 'Leonardo',
        text: 'Finalmente terminei isso! 🚀',
        createdAt: now.subtract(const Duration(minutes: 2)),
        avatarSeed: 'leonardo',
        likes: 12,
        comments: [
          Comment(
            id: 'c1',
            authorId: 'mock-maria',
            authorNickname: 'maria',
            text: 'Gostei muito!',
            createdAt: now.subtract(const Duration(minutes: 1)),
          ),
        ],
      ),
      Post(
        id: 'p2',
        authorNickname: 'Maria',
        text: 'Olhem isso 👀',
        imageUrl:
            'https://images.unsplash.com/photo-1518770660439-4636190af475?w=900',
        createdAt: now.subtract(const Duration(minutes: 7)),
        avatarSeed: 'maria',
        likes: 24,
        comments: [
          Comment(
            id: 'c2',
            authorId: 'mock-joao',
            authorNickname: 'joao',
            text: 'Ficou muito bom.',
            createdAt: now.subtract(const Duration(minutes: 6)),
          ),
          Comment(
            id: 'c3',
            authorId: 'mock-leonardo',
            authorNickname: 'leonardo',
            text: '🔥🔥🔥',
            createdAt: now.subtract(const Duration(minutes: 5)),
          ),
        ],
      ),
      Post(
        id: 'p3',
        authorNickname: 'João',
        text: 'Novo commit no repositório. O sistema está estável. ✅',
        createdAt: now.subtract(const Duration(minutes: 23)),
        avatarSeed: 'joao',
        likes: 8,
        comments: const [],
      ),
      Post(
        id: 'p4',
        authorNickname: 'Akame',
        text: 'A rede MATRIX está online. Bem-vindos. ✦',
        createdAt: now.subtract(const Duration(hours: 1)),
        avatarSeed: 'akame',
        likes: 56,
        comments: [
          Comment(
            id: 'c4',
            authorId: 'mock-leonardo',
            authorNickname: 'leonardo',
            text: 'Sistema impecável.',
            createdAt: now.subtract(const Duration(minutes: 58)),
          ),
        ],
      ),
      Post(
        id: 'p5',
        authorNickname: 'Maria',
        text: 'Trabalhando em algo novo essa semana. Em breve novidades. 💻',
        createdAt: now.subtract(const Duration(hours: 3)),
        avatarSeed: 'maria',
        likes: 33,
        comments: const [],
      ),
    ];
  }

  static List<MatrixUser> users() => const [
        currentUser,
        MatrixUser(
          id: 'u2',
          nickname: 'maria',
          bio: 'Design e código em harmonia.',
          avatarSeed: 'maria',
        ),
        MatrixUser(
          id: 'u3',
          nickname: 'joao',
          bio: 'Engenheiro de software. Café ☕.',
          avatarSeed: 'joao',
        ),
        MatrixUser(
          id: 'u4',
          nickname: 'akame',
          bio: 'Núcleo da rede MATRIX. ✦',
          avatarSeed: 'akame',
        ),
      ];

  /// Akame mock reply. Replace with a real AI API call in a future phase.
  static List<AkameMessage> initialAkameMessages() {
    final now = DateTime.now();
    return [
      AkameMessage(
        id: 'a1',
        text: 'Olá, Leonardo.\nComo posso ajudar?',
        fromUser: false,
        createdAt: now.subtract(const Duration(minutes: 2)),
      ),
    ];
  }

  /// Deterministic mock replies used by the Akame chat in Phase 1.
  static const List<String> akameReplies = [
    'Interessante. Pode me contar mais?',
    'Entendi. Estou processando essa informação. ✦',
    'Estou aqui para ajudar no que precisar.',
    'Recebido. A rede MATRIX está ativa.',
    'Boa pergunta. Vamos explorar isso juntos.',
    'Sistema operando normalmente. Como posso apoiar?',
  ];
}
