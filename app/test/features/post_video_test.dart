import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/features/feed/feed_screen.dart';
import 'package:matrix_app/features/feed/post_card.dart';
import 'package:matrix_app/models/post.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

void main() {
  testWidgets(
      'PostCard renders a video preview with play overlay for video posts',
      (tester) async {
    final repos = FakeRepositories();
    final store = repos.store;
    store.posts = [
      Post(
        id: 'pv1',
        authorId: 'u0',
        authorNickname: 'leonardo',
        text: 'meu vídeo',
        createdAt: DateTime(2024, 1, 1),
        imageUrl: null,
        videoUrl: 'https://fake.matrix.app/u/test.mp4',
        likes: 0,
        liked: false,
        comments: const [],
      ),
    ];
    final state = AppState(repositories: repos);
    await state.restoreSession();
    await state.loadFeed();
    await pumpMatrixApp(tester, const FeedScreen(), state: state);
    await tester.pumpAndSettle();

    // The video post is rendered with a play affordance (video indicator).
    expect(find.byType(PostCard), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
  });

  testWidgets('Post.isVideo is true only when videoUrl is present',
      (tester) async {
    final img = Post(
      id: 'a',
      authorNickname: 'x',
      text: '',
      createdAt: DateTime.now(),
      imageUrl: '/static/a.png',
    );
    final vid = Post(
      id: 'b',
      authorNickname: 'x',
      text: '',
      createdAt: DateTime.now(),
      videoUrl: '/static/video/b.mp4',
    );
    final none = Post(
      id: 'c',
      authorNickname: 'x',
      text: 'oi',
      createdAt: DateTime.now(),
    );
    expect(img.isVideo, isFalse);
    expect(vid.isVideo, isTrue);
    expect(none.isVideo, isFalse);
  });
}
