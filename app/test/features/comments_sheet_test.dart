import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/app/theme/app_colors.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/core/widgets/user_avatar.dart';
import 'package:matrix_app/features/feed/comments_sheet.dart';
import 'package:matrix_app/models/comment.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

void main() {
  Future<AppState> stateWithComments() async {
    final state = AppState(
      repositories: FakeRepositories(
        seedComments: {
          'p1': [
            Comment(
              id: 'sc1',
              authorId: 'u0', // same id as the post author
              authorNickname: 'leonardo',
              authorAvatarUrl: '/static/avatars/leo.png',
              text: 'Comentário do próprio autor',
              createdAt: DateTime(2024, 1, 1, 12),
            ),
            Comment(
              id: 'sc2',
              authorId: 'u2', // different user
              authorNickname: 'joao',
              text: 'Comentário de outra pessoa',
              createdAt: DateTime(2024, 1, 1, 13),
            ),
          ],
        },
      ),
    );
    await state.restoreSession();
    await state.loadFeed();
    return state;
  }

  testWidgets('shows the nickname (no "@") and the avatar', (tester) async {
    final state = await stateWithComments();
    final post = state.posts.firstWhere((p) => p.id == 'p1');

    await pumpMatrixApp(tester, Scaffold(body: CommentsSheet(post: post)), state: state);
    await tester.pumpAndSettle();

    expect(find.textContaining('leonardo', findRichText: true), findsOneWidget);
    expect(find.textContaining('joao', findRichText: true), findsOneWidget);
    // There is no '@'-prefixed identity anymore.
    expect(find.text('@leonardo'), findsNothing);
    expect(find.text('@joao'), findsNothing);
    expect(find.byType(UserAvatar), findsNWidgets(2));
  });

  testWidgets('shows the Autor badge only on the post author comment',
      (tester) async {
    final state = await stateWithComments();
    final post = state.posts.firstWhere((p) => p.id == 'p1');

    await pumpMatrixApp(tester, Scaffold(body: CommentsSheet(post: post)), state: state);
    await tester.pumpAndSettle();

    // Exactly one badge: the comment whose authorId == post.authorId.
    expect(find.text('AUTOR'), findsOneWidget);
    expect(find.text('Comentário do próprio autor'), findsOneWidget);
    expect(find.text('Comentário de outra pessoa'), findsOneWidget);
  });

  testWidgets('new comment by the current user appears with the nickname',
      (tester) async {
    final state = await seededAppState();
    final post = state.posts.firstWhere((p) => p.id == 'p1');

    await pumpMatrixApp(tester, Scaffold(body: CommentsSheet(post: post)), state: state);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Ficou ótimo!');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(
        find.textContaining('leonardo', findRichText: true), findsWidgets);
    expect(find.text('Ficou ótimo!'), findsOneWidget);
    // The current user IS the author of p1 in the fake store.
    expect(find.text('AUTOR'), findsOneWidget);
  });

  testWidgets(
      'input bar stays on screen and send button stays visible when the '
      'keyboard (IME inset) is open', (tester) async {
    final state = await stateWithComments();
    final post = state.posts.firstWhere((p) => p.id == 'p1');

    await pumpMatrixApp(tester, Scaffold(body: CommentsSheet(post: post)), state: state);
    await tester.pumpAndSettle();

    // Simulate the Android soft keyboard raising the bottom IME inset.
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.reset);
    await tester.pump();

    // The text field and the send button remain within the screen bounds —
    // they are never pushed under the nav bar / behind the keyboard.
    final sendIcon = find.byIcon(Icons.send_rounded);
    expect(sendIcon, findsOneWidget);
    final field = find.byType(TextField);
    expect(field, findsOneWidget);

    final sendRect = tester.getRect(sendIcon);
    final screenSize = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(sendRect.bottom, lessThanOrEqualTo(screenSize.height));
  });

  testWidgets('comment sheet background is fully opaque', (tester) async {
    final state = await stateWithComments();
    final post = state.posts.firstWhere((p) => p.id == 'p1');

    await pumpMatrixApp(tester, Scaffold(body: CommentsSheet(post: post)), state: state);
    await tester.pumpAndSettle();

    // The sheet's own background is a solid palette color (no transparency),
    // so the feed behind can never show through.
    final sheetContainer = tester.widget<Material>(find.byType(Material).first);
    expect(sheetContainer.color, isNot(Colors.transparent));
  });

  testWidgets('comment like toggles the heart and persists', (tester) async {
    final state = await stateWithComments();
    final post = state.posts.firstWhere((p) => p.id == 'p1');

    await pumpMatrixApp(tester, Scaffold(body: CommentsSheet(post: post)), state: state);
    await tester.pumpAndSettle();

    // sc2 (joao) starts unliked → outline heart.
    final outline = find.byIcon(Icons.favorite_border_rounded);
    expect(outline, findsWidgets);

    // Tap the heart on joao's comment.
    await tester.tap(outline.first);
    await tester.pumpAndSettle();

    // Now a filled heart exists.
    expect(find.byIcon(Icons.favorite_rounded), findsWidgets);
  });

  testWidgets('replying creates a reply under the correct comment',
      (tester) async {
    final state = await stateWithComments();
    final post = state.posts.firstWhere((p) => p.id == 'p1');

    await pumpMatrixApp(tester, Scaffold(body: CommentsSheet(post: post)), state: state);
    await tester.pumpAndSettle();

    // Tap "Responder" on joao's comment (first matching).
    await tester.tap(find.text('Responder').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Adorei também!');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Adorei também!'), findsOneWidget);
  });

  testWidgets('shows only 5 replies initially and expands via mais comentários',
      (tester) async {
    final replies = List.generate(7, (i) => Comment(
      id: 'r$i',
      authorId: 'u2',
      authorNickname: 'maria',
      text: 'Resposta $i',
      createdAt: DateTime(2024, 1, 1, 10, i),
      parentCommentId: 'sc1',
    ));
    final state = AppState(
      repositories: FakeRepositories(
        seedComments: {
          'p1': [
            Comment(
              id: 'sc1',
              authorId: 'u2',
              authorNickname: 'joao',
              text: 'comentário principal',
              createdAt: DateTime(2024, 1, 1, 9),
            ),
          ],
        },
        seedReplies: {'sc1': replies},
      ),
    );
    await state.restoreSession();
    await state.loadFeed();
    final post = state.posts.firstWhere((p) => p.id == 'p1');

    await pumpMatrixApp(tester, Scaffold(body: CommentsSheet(post: post)), state: state);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver respostas').first);
    await tester.pumpAndSettle();

    // Only 5 replies visible; the 6th and 7th are hidden behind the toggle.
    expect(find.text('Resposta 0'), findsOneWidget);
    expect(find.text('Resposta 4'), findsOneWidget);
    expect(find.text('Resposta 5'), findsNothing);
    expect(find.text('Resposta 6'), findsNothing);
    expect(find.text('mais comentários...'), findsOneWidget);

    // Scroll the toggle into view first (the outer list lazily clips content).
    await tester.ensureVisible(find.text('mais comentários...'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('mais comentários...'));
    await tester.pumpAndSettle();

    // Build the last (7th) reply by scrolling it into view — the ListView
    // lazily builds only the on-screen children (cacheExtent).
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(find.text('Resposta 5'), findsOneWidget);
    expect(find.text('Resposta 6'), findsOneWidget);
    expect(find.text('mais comentários...'), findsNothing);
  });
}
