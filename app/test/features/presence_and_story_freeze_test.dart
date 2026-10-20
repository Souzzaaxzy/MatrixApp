import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/core/widgets/online_status.dart';
import 'package:matrix_app/data/dtos/dtos.dart';
import 'package:matrix_app/features/chat/chat_navigation.dart';
import 'package:matrix_app/features/chat/conversation_screen.dart';
import 'package:matrix_app/features/feed/story_viewer.dart';
import 'package:matrix_app/models/conversation.dart';
import 'package:matrix_app/models/story.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

/// Seeds the session user (u0) with a friend (u2) and a private conversation.
/// The peer's online state is then driven by the REAL mechanism — the
/// realtime `presence` frame the server sends — so the tests exercise the
/// same path production uses.
Future<AppState> seededDm() async {
  final repos = FakeRepositories();
  final store = repos.store;
  store.friendships.add('u0|u2');
  store.chatMessagesByPair['u0|u2'] = [];
  final state = AppState(repositories: repos);
  await state.restoreSession();
  await state.loadConversations();
  return state;
}

Future<void> openDm(WidgetTester tester, AppState state) async {
  await pumpMatrixApp(
    tester,
    ConversationScreen(
      args: const ConversationRouteArgs(
        conversationId: 'u0|u2',
        otherUserId: 'u2',
        otherNickname: 'joao',
      ),
    ),
    state: state,
  );
  await tester.pumpAndSettle();
}

void main() {
  // ── Estado online/offline (DM) ───────────────────────────────
  // O servidor é a autoridade: o app só reflete o que chega. Quem está fora
  // do aplicativo aparece OFFLINE.
  group('DM — estado online/offline', () {
    testWidgets('mostra a bolinha e "online" ao lado do nome', (tester) async {
      final state = await seededDm();
      await openDm(tester, state);

      // O servidor avisa que o peer está com o app aberto.
      state.handleIncomingPresence(
        const PresenceEvent(userId: 'u2', online: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('joao'), findsOneWidget);
      expect(find.byType(OnlineDot), findsOneWidget);
      expect(find.text('online'), findsOneWidget);
    });

    testWidgets('um usuário fora do aplicativo aparece offline',
        (tester) async {
      final state = await seededDm();
      await openDm(tester, state);

      expect(find.byType(OnlineDot), findsOneWidget);
      expect(find.text('offline'), findsOneWidget);
      expect(find.text('online'), findsNothing);
    });

    testWidgets('a bolinha fica à ESQUERDA do nome', (tester) async {
      final state = await seededDm();
      await openDm(tester, state);
      state.handleIncomingPresence(
        const PresenceEvent(userId: 'u2', online: true),
      );
      await tester.pumpAndSettle();

      final dotX = tester.getCenter(find.byType(OnlineDot)).dx;
      final nameX = tester.getCenter(find.text('joao')).dx;
      expect(dotX, lessThan(nameX));
    });

    testWidgets('o frame de presença atualiza a bolinha ao vivo',
        (tester) async {
      final state = await seededDm();
      await openDm(tester, state);
      expect(find.text('offline'), findsOneWidget);

      // Entrou no aplicativo → online.
      state.handleIncomingPresence(
        const PresenceEvent(userId: 'u2', online: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('online'), findsOneWidget);

      // Saiu do aplicativo → offline (o requisito literal).
      state.handleIncomingPresence(
        const PresenceEvent(userId: 'u2', online: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('offline'), findsOneWidget);
    });

    testWidgets('a bolinha tem rótulo acessível', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: OnlineDot(online: true, semanticLabel: 'joao está online'),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('joao está online'), findsOneWidget);
      handle.dispose();
    });
  });

  // ── A contagem de online NUNCA é estimada localmente ─────────
  group('PresenceEvent — espelhamento no AppState', () {
    test('atualiza a contagem de online do grupo que veio do servidor',
        () async {
      final repos = FakeRepositories();
      repos.store.groups['g1'] = GroupConversation(
        id: 'g1',
        group: const GroupHeader(
          id: 'g1',
          name: 'Equipe',
          avatarUrl: null,
          description: '',
          createdById: 'u0',
          memberCount: 5,
          onlineCount: 0,
        ),
        lastMessage: null,
        lastMine: false,
        unreadCount: 0,
        updatedAt: DateTime(2024, 1, 1),
      );
      final state = AppState(repositories: repos);
      await state.restoreSession();
      await state.loadConversations();

      state.handleIncomingPresence(const PresenceEvent(
        userId: 'u2',
        online: true,
        groups: [(groupId: 'g1', onlineCount: 3)],
      ));
      await Future<void>.delayed(Duration.zero);

      expect(state.groups.first.group.onlineCount, 3);
      // O total de membros NÃO muda (é outra informação).
      expect(state.groups.first.group.memberCount, 5);
    });

    test('atualiza a bolinha do peer no cache de conversas', () async {
      final state = await seededDm();
      expect(state.conversations.first.otherUser.online, isFalse);

      state.handleIncomingPresence(
        const PresenceEvent(userId: 'u2', online: true),
      );
      await Future<void>.delayed(Duration.zero);

      expect(state.conversations.first.otherUser.online, isTrue);
    });

    test('um grupo não compartilhado não é afetado', () async {
      final repos = FakeRepositories();
      repos.store.groups['g1'] = GroupConversation(
        id: 'g1',
        group: const GroupHeader(
          id: 'g1',
          name: 'Equipe',
          avatarUrl: null,
          description: '',
          createdById: 'u0',
          memberCount: 4,
          onlineCount: 2,
        ),
        lastMessage: null,
        lastMine: false,
        unreadCount: 0,
        updatedAt: DateTime(2024, 1, 1),
      );
      final state = AppState(repositories: repos);
      await state.restoreSession();
      await state.loadConversations();

      // O frame fala de OUTRO grupo → nada muda.
      state.handleIncomingPresence(const PresenceEvent(
        userId: 'u2',
        online: true,
        groups: [(groupId: 'g-outro', onlineCount: 9)],
      ));
      await Future<void>.delayed(Duration.zero);

      expect(state.groups.first.group.onlineCount, 2);
    });
  });

  // ── Story congelado ao responder ─────────────────────────────
  // Enquanto o campo de resposta está focado, o Story NÃO avança; ao enviar
  // (que tira o foco), ele retoma.
  group('StoryViewer — congela ao responder', () {
    Future<AppState> seededStory() async {
      final repos = FakeRepositories();
      final now = DateTime.now();
      repos.store.storyGroups.add(
        StoryGroup(
          authorId: 'u2',
          authorNickname: 'joao',
          authorAvatarUrl: null,
          stories: [
            Story(
              id: 's1',
              authorId: 'u2',
              authorNickname: 'joao',
              authorAvatarUrl: null,
              mediaUrl: 'http://x/1.jpg',
              mediaType: 'image',
              createdAt: now,
              expiresAt: now.add(const Duration(hours: 24)),
            ),
            Story(
              id: 's2',
              authorId: 'u2',
              authorNickname: 'joao',
              authorAvatarUrl: null,
              mediaUrl: 'http://x/2.jpg',
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

    Future<void> openViewer(WidgetTester tester, AppState state) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('com o campo focado o Story NÃO avança', (tester) async {
      final state = await seededStory();
      await openViewer(tester, state);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );

      // MUITO além dos 5s de uma foto: se o Story estivesse andando, o
      // viewer já teria avançado tudo e FECHADO.
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Responda a esse stories'), findsOneWidget);
    });

    testWidgets('a caixa de resposta NÃO tem cantos arredondados',
        (tester) async {
      final state = await seededStory();
      await openViewer(tester, state);

      final container = tester.widget<Container>(
        find
            .ancestor(
              of: find.byType(TextField),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration?.borderRadius, isNull);
      // A moldura continua (só o arredondado saiu).
      expect(decoration?.border, isNotNull);
    });

    testWidgets('ao enviar a resposta o Story descongela (perde o foco)',
        (tester) async {
      final state = await seededStory();
      await openViewer(tester, state);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'que legal!');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // O envio tira o foco → o Story volta a andar.
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isFalse,
      );
      expect(find.text('Resposta enviada para o chat.'), findsOneWidget);
    });
  });
}
