import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/features/feed/feed_screen.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('renders the feed header and online indicator', (tester) async {
    await pumpMatrixApp(tester, const FeedScreen());

    expect(find.text('MATRIX'), findsOneWidget);
    expect(find.text('ONLINE'), findsOneWidget);
  });

  testWidgets('renders posts and allows scrolling', (tester) async {
    await pumpMatrixApp(tester, const FeedScreen());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.favorite_border_rounded), findsWidgets);

    await tester.fling(find.byType(Scrollable), const Offset(0, -500), 2000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the like heart toggles like state and count',
      (tester) async {
    final state = await seededAppState();
    await pumpMatrixApp(tester, const FeedScreen(), state: state);
    await tester.pumpAndSettle();

    final initialLikes = state.posts.first.likes;
    final heart = find.byIcon(Icons.favorite_border_rounded).first;
    await tester.tap(heart);
    await tester.pumpAndSettle();

    expect(state.posts.first.liked, isTrue);
    expect(state.posts.first.likes, initialLikes + 1);
  });

  testWidgets('opens the comments sheet and adds a comment', (tester) async {
    final state = await seededAppState();
    await pumpMatrixApp(tester, const FeedScreen(), state: state);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('COMMENTS'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).last,
      'Comentário de teste',
    );
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    final comments = await state.loadComments(state.posts.first.id);
    expect(comments.last.text, 'Comentário de teste');
  });
}
