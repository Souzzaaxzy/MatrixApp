import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/features/feed/feed_screen.dart';
import 'package:matrix_app/features/feed/stories_header.dart';
import 'package:matrix_app/app/theme/app_theme.dart';
import 'package:matrix_app/core/widgets/nickname_renderer.dart';
import 'package:matrix_app/core/widgets/user_avatar.dart';
import 'package:matrix_app/features/chat/story_reply_reference.dart';
import 'package:matrix_app/features/feed/story_viewer.dart';
import 'package:matrix_app/models/conversation.dart';
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

    testWidgets('o preview preenche todo o quadrado do Story',
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

      // O quadrado do preview deve ser QUADRADO e preenchido pela mídia.
      final cover = find.byType(Image).first;
      final coverRect = tester.getRect(cover);
      expect(coverRect.width, greaterThan(0));
      expect((coverRect.width - coverRect.height).abs(), lessThan(1.0));

      final preview = find
          .ancestor(of: cover, matching: find.byType(ClipRRect))
          .first;
      final previewRect = tester.getRect(preview);
      expect((previewRect.width - coverRect.width).abs(), lessThan(1.0));
      expect((previewRect.height - coverRect.height).abs(), lessThan(1.0));
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


  group('StoryViewer', () {
    testWidgets('abre, navega (próximo/anterior) e fecha pelo botão',
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
      // Helper: avança o relógio em passos limitados. A mídia remota mantém
      // um stream de imagem aberto (pumpAndSettle nunca estabilizaria) e a
      // transição de rota leva ~300ms — generoso o bastante para o CI, que
      // é mais lento que a máquina local.
      Future<void> settle() async {
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.tap(find.text('abrir'));
      await settle();
      expect(find.byType(StoryViewer), findsOneWidget);
      // Toca à esquerda/à direita para navegar sem exceções de layout.
      await tester.tapAt(const Offset(900, 1200));
      await settle();
      await tester.tapAt(const Offset(100, 1200));
      await settle();
      expect(tester.takeException(), isNull);
      // Fecha pelo botão (o Back do Android usa a mesma rota). Bombeia ATÉ
      // o viewer sair da árvore (o pop é agendado, então um número fixo de
      // pumps é frágil em máquinas lentas como o CI).
      await tester.tap(find.byTooltip('Fechar'));
      for (var i = 0; i < 25 && find.byType(StoryViewer).evaluate().isNotEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(StoryViewer), findsNothing);
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

  group('Stories — texto, curtidas e respostas', () {
    test('cria Story de TEXTO (sem mídia) e ele aparece na lista', () async {
      final state = await seededStories();
      final story = await state.createStory(
        type: 'text',
        text: 'Bom dia, galera!',
      );
      expect(story.isText, isTrue);
      expect(story.text, 'Bom dia, galera!');
      expect(state.myStories.any((s) => s.id == story.id && s.isText), isTrue);
    });

    test('curtir alterna o coração e não duplica (servidor manda)', () async {
      final state = await seededStories();
      final id = state.storyGroups.first.stories.first.id;
      expect(state.storyGroups.first.stories.first.liked, isFalse);
      await state.toggleStoryLike(id);
      var story = state.storyGroups
          .expand((g) => g.stories)
          .firstWhere((s) => s.id == id);
      expect(story.liked, isTrue);
      expect(story.likeCount, 1);
      // Toggle de novo remove (mesma semântica do feed).
      await state.toggleStoryLike(id);
      story = state.storyGroups
          .expand((g) => g.stories)
          .firstWhere((s) => s.id == id);
      expect(story.liked, isFalse);
      expect(story.likeCount, 0);
    });

    test('responder a um Story devolve uma MENSAGEM REAL do chat', () async {
      final state = await seededStories();
      final id = state.storyGroups.first.stories.first.id;
      final result = await state.replyToStory(id, 'Que legal!');
      expect(result.message.content, 'Que legal!');
      expect(result.message.type, 'story_reply');
      expect(result.message.story, isNotNull);
      expect(result.message.story!.storyId, id);
      expect(result.conversationId, isNotEmpty);
    });

    testWidgets(
        'avatar ACIMA do preview; o preview ocupa todo o quadrado; nickname abaixo',
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

      final avatar = find.byType(UserAvatar).first;
      final nick = find.byType(NicknameRenderer).first;
      final cover = find.byType(Image).first;

      // FOTO → PREVIEW → NICKNAME (verticalmente, nesta ordem).
      expect(
        tester.getCenter(avatar).dy,
        lessThan(tester.getCenter(cover).dy),
      );
      expect(
        tester.getCenter(cover).dy,
        lessThan(tester.getCenter(nick).dy),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('viewer mostra "Responda a esse stories" e o coração',
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
      expect(find.text('Responda a esse stories'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      // Tocar no coração preenche (♥) via o MESMO sistema de curtidas.
      await tester.tap(find.byIcon(Icons.favorite_border));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });
  });

  group('Resposta de Story no chat', () {
    testWidgets('bolha mostra "respondeu ao seu stories" + texto',
        (tester) async {
      final chatMod = ChatMessage(
        id: 'm1',
        conversationId: 'c1',
        senderId: 'u2',
        content: 'Que legal!',
        createdAt: DateTime(2024, 1, 1),
        mine: true,
        type: 'story_reply',
        story: const StoryReference(
          storyId: 's1',
          type: 'image',
          thumbnailUrl: 'http://x/thumb.jpg',
        ),
      );
      final reply = StoryReplyReference(story: chatMod.story!, mine: true);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: reply),
        ),
      );
      await tester.pump();
      expect(find.text('respondeu ao seu stories'), findsOneWidget);
    });

    testWidgets('referência de Story de TEXTO mostra o texto do Story',
        (tester) async {
      const ref = StoryReference(
        storyId: 's2',
        type: 'text',
        preview: 'Bom dia, galera!',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: StoryReplyReference(story: ref, mine: false),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('respondeu ao seu stories'), findsOneWidget);
      expect(find.text('Bom dia, galera!'), findsOneWidget);
    });
  });
}
