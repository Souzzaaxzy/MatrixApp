import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/features/post/post_detail_screen.dart';
import 'package:matrix_app/features/profile/profile_screen.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('loads the post by id and renders its content', (tester) async {
    final state = await seededAppState();
    final post = state.posts.first;
    await pumpMatrixApp(tester, PostDetailScreen(postId: post.id), state: state);
    await tester.pumpAndSettle();

    expect(find.text('PUBLICAÇÃO'), findsOneWidget);
    expect(find.text(post.authorName), findsOneWidget);
    expect(find.text(post.text), findsOneWidget);
    expect(find.text('${post.likes}'), findsOneWidget);
  });

  testWidgets('liking on the detail screen updates the shared post',
      (tester) async {
    final state = await seededAppState();
    final post = state.posts.first;
    final initialLikes = post.likes;
    await pumpMatrixApp(tester, PostDetailScreen(postId: post.id), state: state);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pumpAndSettle();

    // The SAME cached post object was updated — feed and profile see it too.
    expect(state.posts.first.liked, isTrue);
    expect(state.posts.first.likes, initialLikes + 1);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });

  testWidgets('back button pops the detail screen', (tester) async {
    final state = await seededAppState();
    await pumpMatrixApp(
      tester,
      PostDetailScreen(postId: state.posts.first.id),
      state: state,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(find.text('PUBLICAÇÃO'), findsNothing);
  });

  testWidgets('profile grid tile opens the post detail', (tester) async {
    final state = await seededAppState();
    await state.loadProfile(state.currentUser!.username);
    await pumpMatrixApp(tester, const ProfileScreen(), state: state);
    await tester.pumpAndSettle();

    // The fake store seeds one post authored by leonardo — tap its tile.
    expect(find.text('Test post'), findsOneWidget);
    final tile = find.descendant(
      of: find.byType(SliverGrid),
      matching: find.byType(InkWell),
    );
    await tester.ensureVisible(tile.first);
    await tester.pumpAndSettle();
    await tester.tap(tile.first);
    await tester.pumpAndSettle();

    expect(find.text('PUBLICAÇÃO'), findsOneWidget);
    expect(find.text('Test post'), findsWidgets);
  });
}
