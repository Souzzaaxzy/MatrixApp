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

  group('like state belongs to the authenticated user', () {
    testWidgets(
        "another user's post shows an EMPTY heart until the viewer likes it",
        (tester) async {
      final state = await seededAppState();
      // p2 is authored by joao; the session user (leonardo) never liked it.
      final post = state.posts.firstWhere((p) => p.id == 'p2');
      expect(post.liked, isFalse);
      expect(post.likes, greaterThan(0)); // counter must NOT imply a like

      await pumpMatrixApp(
          tester, const PostDetailScreen(postId: 'p2'), state: state);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    });

    testWidgets('like → filled; reopen → still filled; unlike → empty',
        (tester) async {
      final state = await seededAppState();
      await pumpMatrixApp(
          tester, const PostDetailScreen(postId: 'p2'), state: state);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

      // Close and reopen: the state comes from the (fake) server store.
      await tester.pumpWidget(const SizedBox());
      await pumpMatrixApp(
          tester, const PostDetailScreen(postId: 'p2'), state: state);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    });

    testWidgets('profile grid never shows a filled heart as a counter',
        (tester) async {
      final state = await seededAppState();
      await state.loadProfile('joao');
      await pumpMatrixApp(tester, const ProfileScreen(username: 'joao'),
          state: state);
      await tester.pumpAndSettle();

      final grid = find.byType(SliverGrid);
      expect(grid, findsOneWidget);
      expect(
        find.descendant(
            of: grid, matching: find.byIcon(Icons.favorite_rounded)),
        findsNothing,
      );
      expect(
        find.descendant(
            of: grid, matching: find.byIcon(Icons.favorite_border_rounded)),
        findsWidgets,
      );
    });
  });

  group('delete post', () {
    testWidgets('author sees the menu and can delete after confirmation',
        (tester) async {
      final state = await seededAppState();
      await pumpMatrixApp(tester, const PostDetailScreen(postId: 'p1'),
          state: state);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir publicação'));
      await tester.pumpAndSettle();

      // Confirmation is required.
      expect(find.text('Excluir publicação?'), findsOneWidget);
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();

      // Post removed from the shared state and the screen popped.
      expect(state.posts.any((p) => p.id == 'p1'), isFalse);
      expect(find.text('PUBLICAÇÃO'), findsNothing);
    });

    testWidgets('cancelling keeps the post', (tester) async {
      final state = await seededAppState();
      await pumpMatrixApp(tester, const PostDetailScreen(postId: 'p1'),
          state: state);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir publicação'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(state.posts.any((p) => p.id == 'p1'), isTrue);
      expect(find.text('PUBLICAÇÃO'), findsOneWidget);
    });

    testWidgets('menu is hidden for posts by other users', (tester) async {
      final state = await seededAppState();
      await pumpMatrixApp(tester, const PostDetailScreen(postId: 'p2'),
          state: state);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
      expect(find.text('Post de outro usuário'), findsOneWidget);
    });
  });
}
