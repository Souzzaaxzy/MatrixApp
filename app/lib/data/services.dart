import 'api_client.dart';
import 'repositories/repositories.dart';
import 'token_store.dart';

/// Lightweight service locator for the data layer.
///
/// Created once at app startup and exposed via [Services.instance]. The UI
/// reads repositories from here instead of constructing Dio directly.
class Services {
  Services._({required this.apiClient, required this.repositories});

  static late final Services instance;

  final ApiClient apiClient;
  final Repositories repositories;

  AuthRepository get auth => repositories.auth;
  PostRepository get posts => repositories.posts;
  LikeRepository get likes => repositories.likes;
  CommentRepository get comments => repositories.comments;
  UserRepository get users => repositories.users;
  UploadRepository get uploads => repositories.uploads;

  /// Initializes the data layer. Call once before runApp.
  static Future<Services> init() async {
    final tokenStore = TokenStore();
    final apiClient = ApiClient(tokenStore: tokenStore);
    final auth = AuthRepository(apiClient);
    final posts = PostRepository(apiClient);
    final likes = LikeRepository(apiClient);
    final comments = CommentRepository(apiClient);
    final users = UserRepository(apiClient);
    final uploads = UploadRepository(apiClient);
    final services = Services._(
      apiClient: apiClient,
      repositories: Repositories(
        auth: auth,
        posts: posts,
        likes: likes,
        comments: comments,
        users: users,
        uploads: uploads,
      ),
    );
    instance = services;
    return services;
  }
}
