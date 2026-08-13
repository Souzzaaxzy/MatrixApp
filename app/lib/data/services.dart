import 'api_client.dart';
import 'repositories/repositories.dart';
import 'token_store.dart';

/// Lightweight service locator for the data layer.
///
/// Created once at app startup and exposed via [Services.instance]. The UI
/// reads repositories from here instead of constructing Dio directly.
class Services {
  Services._({
    required this.apiClient,
    required this.auth,
    required this.posts,
    required this.likes,
    required this.comments,
    required this.users,
    required this.uploads,
  });

  static late final Services instance;

  final ApiClient apiClient;
  final AuthRepository auth;
  final PostRepository posts;
  final LikeRepository likes;
  final CommentRepository comments;
  final UserRepository users;
  final UploadRepository uploads;

  /// Initializes the data layer. Call once before runApp.
  static Future<Services> init() async {
    final tokenStore = TokenStore();
    final apiClient = ApiClient(tokenStore: tokenStore);
    final services = Services._(
      apiClient: apiClient,
      auth: AuthRepository(apiClient),
      posts: PostRepository(apiClient),
      likes: LikeRepository(apiClient),
      comments: CommentRepository(apiClient),
      users: UserRepository(apiClient),
      uploads: UploadRepository(apiClient),
    );
    instance = services;
    return services;
  }
}
