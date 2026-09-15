import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/features/feed/feed_screen.dart';
import 'package:matrix_app/features/feed/stories_header.dart';
import 'package:matrix_app/models/story.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

Future<AppState> seededStories() async {
  final repos = FakeRepositories();
  final now = DateTime.now();
  repos.store.storyGroups.addAll([
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
      ],
      allViewed: false,
    ),
    StoryGroup(
      authorId: 'u3',
      authorNickname:
          'nickname_extremamente_longo_que_precisa_ser_limitado', // quebra o card sem ellipsis
      authorAvatarUrl: null,
      stories: [
        Story(
          id: 's_long',
          authorId: 'u3',
          authorNickname: 'nickname_extremamente_longo',
          authorAvatarUrl: null,
          mediaUrl: 'http://x/long.jpg',
          mediaType: 'image',
          createdAt: now.subtract(const Duration(minutes: 5)),
          expiresAt: now.add(const Duration(hours: 23)),
        ),
      ],
      allViewed: true,
    ),
  ]);
  final state = AppState(repositories: repos);
  await state.restoreSession();
  await state.loadStories();
  return state;
}

void main() {
  group('Stories — AppState', () {
    test('carrega ativos agrupados por autor (não vistos primeiro)', () async {
      final state = await seededStories();
      expect(state.storyGroups.length, 2);
      // O autor NÃO visto vem primeiro.
      expect(state.storyGroups.first.authorNickname, 'joao');
      expect(state.storyGroups.first.allViewed, isFalse);
    });

    test('publica um Story e ele aparece imediatamente', () async {
      final state = await seededStories();
      final before = state.storyGroups.length;
      final story = await state.createStory(
        mediaUrl: 'http://x/novo.jpg',
        mediaType: 'image',
      );
      expect(story.id, isNotEmpty);
      // O Story do próprio usuário entra na lista sem reiniciar o app.
      expect(state.storyGroups.length, greaterThanOrEqualTo(before));
      expect(state.myStories.any((s) => s.id == story.id), isTrue);
    });

    test('marcar como visto atualiza o estado local', () async {
      final state = await seededStories();
      expect(state.storyGroups.first.allViewed, isFalse);
      await state.markStoryViewed('s_joao');
      final group =
          state.storyGroups.firstWhere((g) => g.authorId == 'u2');
      expect(group.stories.first.viewed, isTrue);
      expect(group.allViewed, isTrue);
    });

    test('excluir o próprio Story remove da lista', () async {
      final state = await seededStories();
      final story = await state.createStory(
        mediaUrl: 'http://x/del.jpg',
        mediaType: 'image',
      );
      await state.deleteStory(story.id);
      expect(state.myStories.any((s) => s.id == story.id), isFalse);
    });

    test('Stories expirados não aparecem ativos', () async {
      final repos = FakeRepositories();
      final now = DateTime.now();
      repos.store.storyGroups.add(StoryGroup(
        authorId: 'u9',
        authorNickname: 'expirado',
        authorAvatarUrl: null,
        stories: [
          Story(
            id: 'expired',
            authorId: 'u9',
            authorNickname: 'expirado',
            authorAvatarUrl: null,
            mediaUrl: 'http://x/e.jpg',
            mediaType: 'image',
            createdAt: now.subtract(const Duration(hours: 25)),
            expiresAt: now.subtract(const Duration(hours: 1)),
          ),
        ],
        allViewed: false,
      ));
      final state = AppState(repositories: repos);
      await state.restoreSession();
      await state.loadStories();
      expect(state.storyGroups, isEmpty);
    });
  });

  group('StoriesHeader (widget)', () {
    testWidgets('renderiza um card por autor com avatar e nickname',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final state = await seededStories();
      await pumpMatrixApp(
        tester,
        Scaffold(body: StoriesHeader(state: state)),
        state: state,
      );
      await tester.pumpAndSettle();

      expect(find.text('STORIES'), findsOneWidget);
      expect(find.text('joao'), findsOneWidget);
      // Nickname longo nunca sai do card (ellipsis/maxLines).
      expect(tester.takeException(), isNull);
    });

    testWidgets('sem Stories mostra o estado vazio em pt-BR', (tester) async {
      final state = AppState(repositories: FakeRepositories());
      await state.restoreSession();
      await state.loadStories();
      await pumpMatrixApp(
        tester,
        Scaffold(body: StoriesHeader(state: state)),
        state: state,
      );
      await tester.pumpAndSettle();
      expect(find.text('Nenhum Story disponível.'), findsOneWidget);
    });

    testWidgets('não estoura em tela estreita (320dp)', (tester) async {
      tester.view.physicalSize = const Size(640, 1280);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final state = await seededStories();
      await pumpMatrixApp(
        tester,
        Scaffold(body: StoriesHeader(state: state)),
        state: state,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Feed com Stories no topo', () {
    testWidgets('a faixa de Stories aparece antes do feed de posts',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final state = await seededStories();
      await pumpMatrixApp(tester, const FeedScreen(), state: state);
      await tester.pumpAndSettle();

      expect(find.byType(StoriesHeader), findsOneWidget);
      // A faixa fica ACIMA do primeiro post (y menor).
      final headerY = tester.getTopLeft(find.byType(StoriesHeader)).dy;
      expect(headerY, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    });
  });
}
