import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/features/feed/feed_screen.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('renders the feed header and online indicator', (tester) async {
    await pumpMatrixApp(tester, const FeedScreen());

    expect(find.text('MATRIX'), findsOneWidget);
    expect(find.text('ONLINE'), findsOneWidget);
  });

  testWidgets('renders mocked posts and allows scrolling', (tester) async {
    final state = AppState();
    await pumpMatrixApp(tester, const FeedScreen(), state: state);

    expect(state.posts.length, greaterThan(1));
    expect(find.byIcon(Icons.favorite_border_rounded), findsWidgets);

    // Scrolling down should not throw.
    await tester.fling(find.byType(Scrollable), const Offset(0, -500), 2000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the like heart toggles like state and count',
      (tester) async {
    final state = AppState();
    await pumpMatrixApp(tester, const FeedScreen(), state: state);

    final initialLikes = state.posts.first.likes;
    final heart = find.byIcon(Icons.favorite_border_rounded).first;
    await tester.tap(heart);
    await tester.pump();

    expect(state.posts.first.liked, isTrue);
    expect(state.posts.first.likes, initialLikes + 1);
  });

  testWidgets('opens the comments sheet and adds a comment', (tester) async {
    final state = AppState();
    await pumpMatrixApp(tester, const FeedScreen(), state: state);

    final initialComments = state.posts.first.comments.length;

    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('COMMENTS'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).last,
      'Comentário de teste',
    );
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    expect(state.posts.first.comments.length, initialComments + 1);
    expect(state.posts.first.comments.last.text, 'Comentário de teste');
  });
}
