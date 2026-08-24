/// Named routes for the MATRIX app.
class AppRoutes {
  AppRoutes._();

  static const String splash = '/splash';
  static const String login = '/login';
  static const String register = '/register';
  static const String recover = '/recover';
  static const String home = '/home';
  static const String createPost = '/home/create-post';
  static const String editProfile = '/home/edit-profile';

  /// Post detail. Argument: the post's server id (String).
  static const String postDetail = '/home/post';
}
