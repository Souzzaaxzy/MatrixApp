import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/features/feed/story_viewer.dart';
import 'package:matrix_app/core/widgets/user_avatar.dart';
import 'package:matrix_app/features/profile/profile_screen.dart';
import 'package:matrix_app/models/story.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

/// Builds an AppState where `joao` (u2) has one ACTIVE, unseen story.
Future<AppState> stateWithStory({required bool viewed}) async {
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
          viewed: viewed,
        ),
      ],
      allViewed: viewed,
    ),
  );
  final state = AppState(repositories: repos);
  await state.restoreSession();
  await state.loadStories();
  return state;
}

void main() {
  group('Perfil — foto: clique abre Story, pressão amplia', () {
    testWidgets('clique na foto com Story ativo abre o visualizador',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final state = await stateWithStory(viewed: false);
      await pumpMatrixApp(
        tester,
        const ProfileScreen(nickname: 'joao'),
        state: state,
      );
      await tester.pump(const Duration(milliseconds: 400));

      // Toca a foto de perfil (o avatar do cabeçalho).
      await tester.tap(find.byType(UserAvatar).first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // Sem Story o viewer não abriria; com Story ativo ele abre.
      expect(find.byType(StoryViewer), findsOneWidget);
    });

    testWidgets('clique na foto SEM Story ativo não abre o visualizador',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      // joao sem story algum.
      final repos = FakeRepositories();
      final state = AppState(repositories: repos);
      await state.restoreSession();
      await state.loadStories();

      await pumpMatrixApp(
        tester,
        const ProfileScreen(nickname: 'joao'),
        state: state,
      );
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byType(UserAvatar).first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(StoryViewer), findsNothing);
    });

    testWidgets('pressão na foto abre a foto ampliada (não o Story)',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final state = await stateWithStory(viewed: false);
      await pumpMatrixApp(
        tester,
        const ProfileScreen(nickname: 'joao'),
        state: state,
      );
      await tester.pump(const Duration(milliseconds: 400));

      // Long press na foto → diálogo de zoom (imagem ampliada), e NÃO o
      // visualizador de Stories.
      await tester.longPress(find.byType(UserAvatar).first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(StoryViewer), findsNothing);
    });
  });

  group('Perfil — borda de Story na foto', () {
    testWidgets('Story não visto mostra borda branca', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final state = await stateWithStory(viewed: false);
      await pumpMatrixApp(
        tester,
        const ProfileScreen(nickname: 'joao'),
        state: state,
      );
      await tester.pump(const Duration(milliseconds: 400));

      // A moldura (AnimatedContainer) com borda BRANCA existe.
      final ring = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .any((c) {
        final d = c.decoration;
        if (d is! BoxDecoration || d.border == null) return false;
        final b = d.border as Border;
        return b.top.color == Colors.white;
      });
      expect(ring, isTrue);
    });

    testWidgets('Story visto não mostra borda branca', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final state = await stateWithStory(viewed: true);
      await pumpMatrixApp(
        tester,
        const ProfileScreen(nickname: 'joao'),
        state: state,
      );
      await tester.pump(const Duration(milliseconds: 400));

      final ring = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .any((c) {
        final d = c.decoration;
        if (d is! BoxDecoration || d.border == null) return false;
        final b = d.border as Border;
        return b.top.color == Colors.white;
      });
      expect(ring, isFalse);
    });

    test('hasUnseenStory / storyGroupIndexFor refletem o estado', () async {
      final unseen = await stateWithStory(viewed: false);
      expect(unseen.hasUnseenStory('u2'), isTrue);
      expect(unseen.storyGroupIndexFor('u2'), 0);
      expect(unseen.hasUnseenStory('u9'), isFalse);
      expect(unseen.storyGroupIndexFor('u9'), -1);

      final seen = await stateWithStory(viewed: true);
      expect(seen.hasUnseenStory('u2'), isFalse);
      // Mesmo visto, o Story continua acessível para abrir.
      expect(seen.storyGroupIndexFor('u2'), 0);
    });
  });
}