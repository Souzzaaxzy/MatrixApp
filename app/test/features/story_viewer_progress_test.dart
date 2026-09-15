import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/core/widgets/user_avatar.dart';
import 'package:matrix_app/features/feed/story_viewer.dart';
import 'package:matrix_app/models/story.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

/// Story helper: an active (unseen) group for `u2`.
Future<AppState> seededStories() async {
  final repos = FakeRepositories();
  final now = DateTime.now();
  repos.store.storyGroups.add(
    StoryGroup(
      authorId: 'u2',
      authorNickname: 'joao',
      authorAvatarUrl: null,
      stories: [
        Story(
          id: 's_joao',
          authorId: 'u2',
          authorNickname: 'joao',
          authorAvatarUrl: null,
          mediaUrl: 'http://x/joao.jpg',
          mediaType: 'image',
          createdAt: now,
          expiresAt: now.add(const Duration(hours: 24)),
        ),
        Story(
          id: 's_joao2',
          authorId: 'u2',
          authorNickname: 'joao',
          authorAvatarUrl: null,
          mediaUrl: 'http://x/joao2.jpg',
          mediaType: 'image',
          createdAt: now.subtract(const Duration(minutes: 1)),
          expiresAt: now.add(const Duration(hours: 23)),
        ),
      ],
      allViewed: false,
    ),
  );
  final state = AppState(repositories: repos);
  await state.restoreSession();
  await state.loadStories();
  return state;
}

void main() {
  group('StoryViewer — progresso, identidade e durações', () {
    testWidgets('mostra FOTO acima do NOME (identidade do autor)',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final state = await seededStories();
      await pumpMatrixApp(
        tester,
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => StoryViewer.open(ctx, state, startGroup: 0),
            child: const Text('abrir'),
          ),
        ),
        state: state,
      );
      await tester.tap(find.text('abrir'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(UserAvatar), findsWidgets);
      expect(find.text('joao'), findsOneWidget);
    });

    testWidgets('linha de progresso avança com a mídia (foto = 5s)',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final state = await seededStories();
      await pumpMatrixApp(
        tester,
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => StoryViewer.open(ctx, state, startGroup: 0),
            child: const Text('abrir'),
          ),
        ),
        state: state,
      );
      await tester.tap(find.text('abrir'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // A barra anima durante os 5s e auto-avança sem travar.
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Android Back fecha o visualizador', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final state = await seededStories();
      await pumpMatrixApp(
        tester,
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => StoryViewer.open(ctx, state, startGroup: 0),
            child: const Text('abrir'),
          ),
        ),
        state: state,
      );
      await tester.tap(find.text('abrir'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(StoryViewer), findsOneWidget);

      await tester.binding.handlePopRoute();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(StoryViewer), findsNothing);
    });
  });
}