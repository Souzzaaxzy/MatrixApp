import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/features/chat/chat_navigation.dart';
import 'package:matrix_app/features/chat/chat_screen.dart';
import 'package:matrix_app/features/chat/group_conversation_screen.dart';
import 'package:matrix_app/models/conversation.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

/// Seeds a group owned by u0 (leonardo) with u2 (joao) as a member and the
/// given messages (even index = u0's own, odd = u2's).
Future<AppState> seededGroup({
  List<String> messages = const [],
  String? sessionUserId,
}) async {
  final repos = FakeRepositories();
  final store = repos.store;
  if (sessionUserId != null) store.currentUserId = sessionUserId;
  const id = 'g1';
  store.groups[id] = GroupConversation(
    id: id,
    group: const GroupHeader(
      id: id,
      name: 'Equipe MATRIX',
      avatarUrl: null,
      description: 'conjunto de testes',
      createdById: 'u0',
      memberCount: 2,
    ),
    lastMessage: null,
    lastMine: false,
    unreadCount: 0,
    updatedAt: DateTime(2024, 1, 1),
  );
  store.groupMemberIds[id] = {'u0', 'u2'};
  store.groupMessagesById[id] = [
    for (var i = 0; i < messages.length; i++)
      ChatMessage(
        id: 'gm$i',
        groupId: id,
        conversationId: null,
        senderId: i.isEven ? 'u0' : 'u2',
        sender: ChatUser(
          id: i.isEven ? 'u0' : 'u2',
          nickname: i.isEven ? 'leonardo' : 'joao',
        ),
        content: messages[i],
        createdAt: DateTime(2024, 1, 1, 20, i),
        mine: i.isEven,
      ),
  ];
  final state = AppState(repositories: repos);
  await state.restoreSession();
  await state.loadFeed();
  await state.loadConversations();
  return state;
}

Widget groupScreen() => const GroupConversationScreen(
      args: GroupConversationRouteArgs(
        groupId: 'g1',
        groupName: 'Equipe MATRIX',
        groupAvatarUrl: null,
      ),
    );

void main() {
  group('auto-scroll inteligente', () {
    testWidgets(
        'no final: nova mensagem chega e é adicionada; usuário continua',
        (tester) async {
      final state = await seededGroup(messages: ['a', 'b', 'c']);
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      state.handleIncomingChatMessage(ChatMessage(
        id: 'rx1',
        groupId: 'g1',
        senderId: 'u2',
        sender: const ChatUser(id: 'u2', nickname: 'joao'),
        content: 'chegou nova',
        createdAt: DateTime(2024, 1, 1, 21, 0),
        mine: false,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('chegou nova'), findsOneWidget);
    });

    testWidgets('lendo antigas: nova mensagem NÃO força o scroll para baixo',
        (tester) async {
      final state =
          await seededGroup(messages: List.generate(40, (i) => 'm$i'));
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      // Scroll UP to read history (away from the bottom).
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 700));
      await tester.pumpAndSettle();
      final before = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      expect(before, greaterThan(0));

      // Message arrives while reading history.
      state.handleIncomingChatMessage(ChatMessage(
        id: 'rx1',
        groupId: 'g1',
        senderId: 'u2',
        sender: const ChatUser(id: 'u2', nickname: 'joao'),
        content: 'nova enquanto leio',
        createdAt: DateTime(2024, 1, 1, 21, 0),
        mine: false,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final after = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      // The user is NOT yanked to the bottom.
      final max = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .maxScrollExtent;
      expect(after, lessThan(max - 100));
      expect((after - before).abs(), lessThan(160));
    });
  });

  group('menções @usuario e @todos', () {
    testWidgets('digitar "@" abre o sheet; selecionar insere @Nick ',
        (tester) async {
      final state = await seededGroup();
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '@');
      await tester.pumpAndSettle();
      // The mention sheet opens (loads members asynchronously).
      expect(find.text('MENCIONAR'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('joao'), findsWidgets);

      await tester.tap(find.text('joao').first);
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField).last);
      expect(field.controller!.text, contains('@joao '));
    });

    testWidgets('@todos aparece no picker para o DONO', (tester) async {
      final ownerState = await seededGroup();
      await pumpMatrixApp(tester, groupScreen(), state: ownerState);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '@');
      await tester.pumpAndSettle();
      expect(find.text('@todos'), findsOneWidget);
    });

    testWidgets('@todos NÃO aparece no picker para um membro comum',
        (tester) async {
      final memberState = await seededGroup(sessionUserId: 'u2');
      await pumpMatrixApp(tester, groupScreen(), state: memberState);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '@');
      await tester.pumpAndSettle();
      expect(find.text('@todos'), findsNothing);
    });

    testWidgets('mensagem com menção renderiza com RichText (destaque)',
        (tester) async {
      final repos = FakeRepositories();
      final store = repos.store;
      const id = 'g1';
      store.groups[id] = GroupConversation(
        id: id,
        group: const GroupHeader(
          id: id,
          name: 'Equipe MATRIX',
          avatarUrl: null,
          description: '',
          createdById: 'u0',
          memberCount: 2,
        ),
        lastMessage: null,
        lastMine: false,
        unreadCount: 0,
        updatedAt: DateTime(2024, 1, 1),
      );
      store.groupMemberIds[id] = {'u0', 'u2'};
      store.groupMessagesById[id] = [
        ChatMessage(
          id: 'gm1',
          groupId: id,
          conversationId: null,
          senderId: 'u0',
          sender: const ChatUser(id: 'u0', nickname: 'leonardo'),
          content: 'Oi @joao, olha isso!',
          createdAt: DateTime(2024, 1, 1, 20, 1),
          mine: false,
          mentions: const [ChatMention(userId: 'u2', nickname: 'joao')],
          mentioned: true,
        ),
      ];
      final state = AppState(repositories: repos);
      await state.restoreSession();
      await state.loadFeed();
      await state.loadConversations();
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      // The content is split by the mention renderer.
      expect(find.textContaining('Oi @joao'), findsOneWidget);
    });
  });

  testWidgets('lista de chats mostra o indicador "@" quando mencionado',
      (tester) async {
    final repos = FakeRepositories();
    final store = repos.store;
    const id = 'g1';
    store.groups[id] = GroupConversation(
      id: id,
      group: const GroupHeader(
        id: id,
        name: 'Equipe MATRIX',
        avatarUrl: null,
        description: '',
        createdById: 'u0',
        memberCount: 2,
      ),
      lastMessage: ConversationLastMessage(
        id: 'gm1',
        content: 'Oi @joao, olha isso!',
        senderId: 'u0',
        createdAt: DateTime(2024, 1, 1, 20, 0),
        senderNickname: 'leonardo',
      ),
      lastMine: false,
      unreadCount: 0,
      updatedAt: DateTime(2024, 1, 1, 20, 0),
      mentioned: true,
    );
    final state = AppState(repositories: repos);
    await state.restoreSession();
    await state.loadFeed();
    await state.loadConversations();
    await pumpMatrixApp(tester, const ChatScreen(), state: state);
    await tester.pumpAndSettle();

    // Scroll the group tile into view and verify the "@" indicator.
    await tester.scrollUntilVisible(find.text('Equipe MATRIX'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('@'), findsOneWidget);
  });

  group('Visto/Enviado', () {
    testWidgets(
        'long-press em mensagem PRÓPRIA mostra "Visto/Enviado" e o painel abre',
        (tester) async {
      final state = await seededGroup(messages: ['minha msg', 'msg do joao']);
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      // 'minha msg' is u0's own message (index even).
      await tester.longPress(find.text('minha msg'));
      await tester.pumpAndSettle();
      expect(find.text('Visto/Enviado'), findsOneWidget);

      await tester.tap(find.text('Visto/Enviado'));
      await tester.pumpAndSettle();
      // The panel opens (chat stays behind) with the two sections.
      expect(find.text('VISTO/ENVIADO'), findsOneWidget);
      expect(find.textContaining('VISTO ('), findsOneWidget);
      expect(find.textContaining('ENVIADO ('), findsOneWidget);
    });

    testWidgets('long-press em mensagem de OUTRO não mostra "Visto/Enviado"',
        (tester) async {
      final state = await seededGroup(messages: ['minha msg', 'deles']);
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      await tester.longPress(find.text('deles'));
      await tester.pumpAndSettle();
      expect(find.text('Visto/Enviado'), findsNothing);
    });
  });
}
