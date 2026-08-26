import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
