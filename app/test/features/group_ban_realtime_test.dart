import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/app/theme/app_theme.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/core/widgets/app_state_scope.dart';
import 'package:matrix_app/features/chat/chat_navigation.dart';
import 'package:matrix_app/features/chat/conversation_screen.dart';
import 'package:matrix_app/features/chat/group_conversation_screen.dart';
import 'package:matrix_app/models/conversation.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

/// Pumps a bare root (a Scaffold) and pushes the group screen on top so
/// [Navigator.maybePop] can actually close it on the realtime ban frame.
Future<void> pumpGroupPushed(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(
    AppStateScope(
      state: state,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: Center(child: Text('root'))),
      ),
    ),
  );
  await tester.pumpAndSettle();
  Navigator.of(tester.element(find.text('root'))).push(
    MaterialPageRoute<void>(builder: (_) => _groupScreen('g1')),
  );
  await tester.pumpAndSettle();
}

/// Seeds a group owned by u0 (leonardo) with member u2 (joao) plus a couple
/// of messages: gm0 owned by u0, gm1 owned by u2.
Future<AppState> seededGroupForBan() async {
  final repos = FakeRepositories();
  final store = repos.store;
  const id = 'g1';
  final g = GroupConversation(
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
  store.groups[id] = g;
  store.groupMessagesById[id] = <ChatMessage>[
    ChatMessage(
      id: 'gm0',
      groupId: id,
      conversationId: null,
      senderId: 'u0',
      sender: const ChatUser(id: 'u0', nickname: 'leonardo'),
      content: 'Olá grupo',
      createdAt: DateTime(2024, 1, 1, 20, 0),
      mine: true,
    ),
    ChatMessage(
      id: 'gm1',
      groupId: id,
      conversationId: null,
      senderId: 'u2',
      sender: const ChatUser(id: 'u2', nickname: 'joao'),
      content: 'Oi leo',
      createdAt: DateTime(2024, 1, 1, 20, 1),
      mine: false,
    ),
  ];
  store.groupMemberIds[id] = {'u0', 'u2'};
  final state = AppState(repositories: repos);
  await state.restoreSession();
  await state.loadFeed();
  await state.loadConversations();
  return state;
}

Widget _groupScreen(String groupId) {
  return GroupConversationScreen(
    args: GroupConversationRouteArgs(
      groupId: groupId,
      groupName: 'Equipe MATRIX',
      groupAvatarUrl: null,
    ),
  );
}

void main() {
  group('real-time ban (chat_group_banned)', () {
    testWidgets(
        'kicks the session user out when the server bans them from the group',
        (tester) async {
      final state = await seededGroupForBan();
      await pumpGroupPushed(tester, state);
      expect(find.byType(GroupConversationScreen), findsOneWidget);

      // Server bans the session user (frame arrives from push_service).
      state.handleIncomingGroupBanned(
        const GroupBannedEvent(groupId: 'g1', groupName: 'Equipe MATRIX'),
      );
      await tester.pumpAndSettle();

      // The open group screen closed itself.
      expect(find.byType(GroupConversationScreen), findsNothing);
      expect(find.textContaining('banido'), findsOneWidget);
    });

    testWidgets('does not kick unrelated group screens', (tester) async {
      final state = await seededGroupForBan();
      await pumpGroupPushed(tester, state);

      // Ban event for a DIFFERENT group — this screen must stay open.
      state.handleIncomingGroupBanned(
        const GroupBannedEvent(groupId: 'g9', groupName: 'Outro'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GroupConversationScreen), findsOneWidget);
      expect(find.textContaining('banido'), findsNothing);
    });
  });

  group('real-time group deletion/leave (chat_group_deleted)', () {
    testWidgets('closes the open group screen when the owner deletes the group',
        (tester) async {
      final state = await seededGroupForBan();
      await pumpGroupPushed(tester, state);
      expect(find.byType(GroupConversationScreen), findsOneWidget);

      state.handleIncomingGroupDeleted(
        const GroupDeletedEvent(groupId: 'g1', groupName: 'Equipe MATRIX'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GroupConversationScreen), findsNothing);
      expect(find.textContaining('já não está disponível'), findsOneWidget);
    });

    testWidgets('drops the group from the cached list', (tester) async {
      final state = await seededGroupForBan();
      expect(state.groups.where((g) => g.id == 'g1'), hasLength(1));

      state.handleIncomingGroupDeleted(
        const GroupDeletedEvent(groupId: 'g1', groupName: 'Equipe MATRIX'),
      );
      await pumpMatrixApp(tester, const SizedBox(), state: state);
      await tester.pumpAndSettle();

      expect(state.groups.where((g) => g.id == 'g1'), isEmpty);
    });

    testWidgets('does not close unrelated group screens', (tester) async {
      final state = await seededGroupForBan();
      await pumpGroupPushed(tester, state);

      state.handleIncomingGroupDeleted(
        const GroupDeletedEvent(groupId: 'g9', groupName: 'Outro'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GroupConversationScreen), findsOneWidget);
    });
  });

  group('reply quote tap-to-locate', () {
    testWidgets(
        'tapping the server-resolved quote scrolls in the DM when the target is loaded',
        (tester) async {
      final repos = FakeRepositories();
      final store = repos.store;
      store.friendships.add('u0|u2');
      store.chatMessagesByPair['u0|u2'] = [];
      final state = AppState(repositories: repos);
      await state.restoreSession();
      await state.loadFeed();
      await state.loadConversations();
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

      // Original + a reply referencing it.
      state.handleIncomingChatMessage(ChatMessage(
        id: 'm1',
        conversationId: 'u0|u2',
        senderId: 'u2',
        content: 'mensagem original',
        createdAt: DateTime(2024, 1, 1, 22, 1),
        mine: false,
      ));
      state.handleIncomingChatMessage(ChatMessage(
        id: 'm2',
        conversationId: 'u0|u2',
        senderId: 'u2',
        content: 'respondendo…',
        createdAt: DateTime(2024, 1, 1, 22, 2),
        mine: false,
        replyTo: const ReplyInfo(
          id: 'm1',
          senderId: 'u2',
          senderNickname: 'joao',
          content: 'mensagem original',
          exists: true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(
          find.text('mensagem original'), findsNWidgets(2)); // quote + bubble
      expect(find.text('respondendo…'), findsOneWidget);
    });
  });
}
