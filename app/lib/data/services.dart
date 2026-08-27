import 'api_client.dart';
import 'push_service.dart';
import 'repositories/repositories.dart';
import 'token_store.dart';

/// Lightweight service locator for the data layer.
///
/// Created once at app startup and exposed via [Services.instance]. The UI
/// reads repositories from here instead of constructing Dio directly.
class Services {
  Services._({
    required this.apiClient,
    required this.repositories,
    required this.push,
  });

  static late final Services instance;

  /// False until [init] completed — guards test contexts that never
  /// initialize the real data layer.
  static bool isInitialized = false;

  final ApiClient apiClient;
  final Repositories repositories;
  final PushService push;

  AuthRepository get auth => repositories.auth;
  PostRepository get posts => repositories.posts;
  LikeRepository get likes => repositories.likes;
  CommentRepository get comments => repositories.comments;
  UserRepository get users => repositories.users;
  FriendRepository get friends => repositories.friends;
  NotificationRepository get notifications => repositories.notifications;
  UploadRepository get uploads => repositories.uploads;
  CustomizationRepository get customization => repositories.customization;
  ChatRepository get chat => repositories.chat;

  /// Initializes the data layer. Call once before runApp.
  static Future<Services> init() async {
    final tokenStore = TokenStore();
    final apiClient = ApiClient(tokenStore: tokenStore);
    final auth = AuthRepository(apiClient);
    final posts = PostRepository(apiClient);
    final likes = LikeRepository(apiClient);
    final comments = CommentRepository(apiClient);
    final users = UserRepository(apiClient);
    final friends = FriendRepository(apiClient);
    final notifications = NotificationRepository(apiClient);
    final uploads = UploadRepository(apiClient);
    final customization = CustomizationRepository(apiClient);
    final chat = ChatRepository(apiClient);
    final push = PushService(api: apiClient, tokenStore: tokenStore);
    final services = Services._(
      apiClient: apiClient,
      repositories: Repositories(
        auth: auth,
        posts: posts,
        likes: likes,
        comments: comments,
        users: users,
        friends: friends,
        notifications: notifications,
        uploads: uploads,
        customization: customization,
        chat: chat,
      ),
      push: push,
    );
    instance = services;
    isInitialized = true;
    return services;
  }
}
