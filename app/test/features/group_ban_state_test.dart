import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/data/dtos/dtos.dart';
import 'package:matrix_app/features/chat/chat_navigation.dart';
import 'package:matrix_app/features/chat/conversation_screen.dart';
import 'package:matrix_app/features/chat/group_conversation_screen.dart';
import 'package:matrix_app/features/chat/group_members_screen.dart';
import 'package:matrix_app/models/conversation.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

/// Seeds a group owned by u0 (leonardo) with u2 (joao) as a member plus the
/// given messages. [bannedIds] marks currently-banned member ids (mirrors
/// the server's `bannedAt` rows).
Future<AppState> seededGroupState({
  List<String> messages = const ['bom dia', 'oi'],
  Set<String> bannedIds = const {},
}) async {
  final repos = FakeRepositories();
  final store = repos.store;
  const id = 'g1';
  store.groups[id] = GroupConversation(
    id: id,
    group: const GroupHeader(
      id: id,
      name: 'Equipe MATRIX',
      avatarUrl: null,
      description: 'Grupo de testes',
      createdById: 'u0',
      memberCount: 2,
    ),
    lastMessage: null,
    lastMine: false,
    unreadCount: 0,
    updatedAt: DateTime(2024, 1, 1),
  );
  store.groupMemberIds[id] = {'u0', 'u2'}..removeAll(bannedIds);
  store.groupBannedIds[id] = bannedIds;
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

Widget membersScreen() => const GroupMembersScreen(
      args: GroupMembersRouteArgs(
        groupId: 'g1',
        groupName: 'Equipe MATRIX',
        ownerId: 'u0',
      ),
    );

void main() {
  group('mensagens de usuário banido (banido(a))', () {
    testWidgets('history shows the banido(a) tag next to a banned sender name',
        (tester) async {
      // joao (u2) is CURRENTLY banned — his OLD messages must stay in the
      // history but be labeled "banido(a)". leonardo (u0) is not.
      final state = await seededGroupState(bannedIds: {'u2'});
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      expect(find.text('banido(a)'), findsOneWidget);
      expect(find.text('joao'), findsOneWidget);
      expect(find.text('leonardo'), findsOneWidget);
    });

    testWidgets('an un-banned sender does not get the banido(a) tag',
        (tester) async {
      final state = await seededGroupState(bannedIds: const {});
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      expect(find.text('banido(a)'), findsNothing);
    });

    testWidgets(
        'realtime chat_group_updated with bannedUserIds tags the loaded '
        'messages live (no reload)', (tester) async {
      final state = await seededGroupState(bannedIds: const {});
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();
      expect(find.text('banido(a)'), findsNothing);

      // Server bans joao → broadcasts a chat_group_updated frame with the
      // full banned set. The open conversation must tag joao's messages
      // immediately.
      state.handleIncomingGroupUpdated(GroupUpdatedEvent(
        groupId: 'g1',
        group: const GroupHeader(
          id: 'g1',
          name: 'Equipe MATRIX',
          avatarUrl: null,
          description: '',
          createdById: 'u0',
          memberCount: 1,
        ),
        bannedUserIds: const {'u2'},
      ));
      await tester.pumpAndSettle();

      expect(find.text('banido(a)'), findsOneWidget);
    });

    testWidgets('realtime unban clears the banido(a) tag live',
        (tester) async {
      final state = await seededGroupState(bannedIds: {'u2'});
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();
      expect(find.text('banido(a)'), findsOneWidget);

      state.handleIncomingGroupUpdated(GroupUpdatedEvent(
        groupId: 'g1',
        group: const GroupHeader(
          id: 'g1',
          name: 'Equipe MATRIX',
          avatarUrl: null,
          description: '',
          createdById: 'u0',
          memberCount: 2,
        ),
        bannedUserIds: const {},
      ));
      await tester.pumpAndSettle();

      expect(find.text('banido(a)'), findsNothing);
    });

    testWidgets('banido(a) is group-scoped: a DM peer never renders it',
        (tester) async {
      final repos = FakeRepositories();
      final store = repos.store;
      store.friendships.add('u0|u2');
      store.chatMessagesByPair['u0|u2'] = [
        ChatMessage(
          id: 'dm1',
          conversationId: 'u0|u2',
          senderId: 'u2',
          sender: const ChatUser(
            id: 'u2',
            nickname: 'joao',
            banned: true,
          ),
          content: 'mensagem privada',
          createdAt: DateTime(2024, 1, 1, 20, 0),
          mine: false,
        ),
      ];
      final state = AppState(repositories: repos);
      await state.restoreSession();
      await state.loadFeed();
      await state.loadConversations();
      await pumpMatrixApp(
        tester,
        const ConversationScreen(
          args: ConversationRouteArgs(
            conversationId: 'u0|u2',
            otherUserId: 'u2',
            otherNickname: 'joao',
          ),
        ),
        state: state,
      );
      await tester.pumpAndSettle();

      expect(find.text('banido(a)'), findsNothing);
    });
  });

  group('mini menu — banir usuário acessível', () {
    testWidgets('long-press shows Banir usuário fully visible for the owner',
        (tester) async {
      final state = await seededGroupState();
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      // Long-press joao's message (message from u2, not mine, owner session).
      await tester.longPress(find.text('oi'));
      await tester.pumpAndSettle();

      expect(find.text('Banir usuário'), findsOneWidget);
      final rect = tester.getRect(find.text('Banir usuário'));
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(rect.bottom, lessThanOrEqualTo(size.height));
    });
  });

  group('participantes — seção de banidos e desbanimento', () {
    testWidgets('owner sees the banned section with DESBANIR',
        (tester) async {
      final state = await seededGroupState(bannedIds: {'u2'});
      await pumpMatrixApp(tester, membersScreen(), state: state);
      await tester.pumpAndSettle();

      expect(find.text('BANIDOS'), findsOneWidget);
      expect(find.text('banido(a)'), findsOneWidget);
      expect(find.text('DESBANIR'), findsOneWidget);
    });

    testWidgets('DESBANIR returns the member to the active list',
        (tester) async {
      final state = await seededGroupState(bannedIds: {'u2'});
      await pumpMatrixApp(tester, membersScreen(), state: state);
      await tester.pumpAndSettle();
      expect(find.text('BANIDOS'), findsOneWidget);

      await tester.tap(find.text('DESBANIR'));
      await tester.pumpAndSettle();

      expect(find.text('BANIDOS'), findsNothing);
      expect(find.text('DESBANIR'), findsNothing);
    });
  });
}