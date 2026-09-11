import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/core/widgets/user_avatar.dart';
import 'package:matrix_app/features/chat/chat_navigation.dart';
import 'package:matrix_app/features/chat/group_conversation_screen.dart';
import 'package:matrix_app/features/chat/group_profile_screen.dart';
import 'package:matrix_app/features/profile/profile_screen.dart';
import 'package:matrix_app/models/conversation.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

/// Seeds a group owned by u0 (leonardo) with a fixed id e some messages.
Future<AppState> seededGroup({
  List<String> messages = const [],
  String? groupName = 'Equipe MATRIX',
  String? avatarUrl,
  int memberCount = 3,
}) async {
  final repos = FakeRepositories();
  final store = repos.store;
  final id = 'g1';
  final g = GroupConversation(
    id: id,
    group: GroupHeader(
      id: id,
      name: groupName ?? 'Equipe MATRIX',
      avatarUrl: avatarUrl,
      description: 'Grupo de testes',
      createdById: 'u0',
      memberCount: memberCount,
    ),
    lastMessage: null,
    lastMine: false,
    unreadCount: 0,
    updatedAt: DateTime(2024, 1, 1),
  );
  store.groups[id] = g;
  store.groupMessagesById[id] = [];
  store.groupMemberIds[id] = {'u0', 'u2'};
  for (var i = 0; i < messages.length; i++) {
    store.groupMessagesById[id]!.add(ChatMessage(
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
    ));
  }
  final state = AppState(repositories: repos);
  await state.restoreSession();
  await state.loadFeed();
  await state.loadConversations();
  return state;
}

Widget _groupScreen(String groupId, String name, String? avatar) {
  return GroupConversationScreen(
    args: GroupConversationRouteArgs(
      groupId: groupId,
      groupName: name,
      groupAvatarUrl: avatar,
    ),
  );
}

void main() {
  group('GroupConversationScreen header', () {
    testWidgets('shows back arrow, group photo,name and member count',
        (tester) async {
      final state = await seededGroup(avatarUrl: '/static/g1.png');
      await pumpMatrixApp(
        tester,
        _groupScreen('g1', 'Equipe MATRIX', '/static/g1.png'),
        state: state,
      );
      await tester.pumpAndSettle();

      expect(find.byType(BackButton), findsOneWidget);
      expect(find.text('Equipe MATRIX'), findsOneWidget);
      expect(find.textContaining('3 membros'), findsOneWidget);
      expect(find.byType(UserAvatar), findsWidgets);
    });

    testWidgets('long group name truncates without overflow', (tester) async {
      final longName = 'G' * 60;
      final state = await seededGroup(groupName: longName);
      await pumpMatrixApp(
        tester,
        _groupScreen('g1', longName, null),
        state: state,
      );
      await tester.pumpAndSettle();
      expect(find.text(longName), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('typing indicator shows single user and hides on stop',
        (tester) async {
      final state = await seededGroup();
      await pumpMatrixApp(tester, _groupScreen('g1', 'Equipe MATRIX', null), state: state);
      await tester.pumpAndSettle();

      expect(find.textContaining('digitando'), findsNothing);
      state.handleIncomingChatTyping(const ChatTypingEvent(
        groupId: 'g1',
        userId: 'u2',
        nickname: 'joao',
        typing: true,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('joao está digitando'), findsOneWidget);


      state.handleIncomingChatTyping(const ChatTypingEvent(
        groupId: 'g1',
        userId: 'u2',
        nickname: 'joao',
        typing: false,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('digitando'), findsNothing);
    });

    testWidgets('recording indicator shows single user', (tester) async {
      final state = await seededGroup();
      await pumpMatrixApp(tester, _groupScreen('g1', 'Equipe MATRIX', null), state: state);
      await tester.pumpAndSettle();

      expect(find.textContaining('gravando'), findsNothing);
      state.handleIncomingChatRecording(const ChatRecordingEvent(
        groupId: 'g1',
        userId: 'u2',
        nickname: 'joao',
        recording: true,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('joao está gravando áudio'), findsOneWidget);


      state.handleIncomingChatRecording(const ChatRecordingEvent(
        groupId: 'g1',
        userId: 'u2',
        nickname: 'joao',
        recording: false,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('gravando'), findsNothing);
    });

    testWidgets('multiple typing users show the plural label', (tester) async {
      final state = await seededGroup();
      await pumpMatrixApp(tester, _groupScreen('g1', 'Equipe MATRIX', null), state: state);
      await tester.pumpAndSettle();

      state.handleIncomingChatTyping(const ChatTypingEvent(
        groupId: 'g1', userId: 'u2', nickname: 'joao', typing: true,
      ));
      state.handleIncomingChatTyping(const ChatTypingEvent(
        groupId: 'g1', userId: 'u3', nickname: 'maria', typing: true,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('2 usuários estão digitando'), findsOneWidget);
    });
  });

  group('GroupConversationScreen keyboard/messages', () {
    testWidgets('composer renders above the keyboard when inset changes',
        (tester) async {
      final messages = List.generate(
        40,
        (i) => i.isEven ? 'minha $i' : 'dela $i',
      );
      final state = await seededGroup(messages: messages);
      await pumpMatrixApp(tester, _groupScreen('g1', 'Equipe MATRIX', null), state: state);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 50));
      // Scroll na parte inferior para revelar a última mensagem.

      for (var i = 0; i < 10; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('dela 39'), findsOneWidget);

      final original = tester.view.physicalSize;


      tester.view.physicalSize = Size(
        original.width,
        original.height - 300 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('dela 39').hitTestable(), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    });
  });

  group('GroupProfileScreen participantes', () {
    testWidgets('participant tap opens the correct profile and back returns',
        (tester) async {
      final state = await seededGroup();
      await pumpMatrixApp(
        tester,
        GroupProfileScreen(
          args: const GroupProfileRouteArgs(
            groupId: 'g1',
            initialName: 'Equipe MATRIX',
            initialAvatarUrl: null,
            initialDescription: 'Grupo de testes',
            initialOwnerId: 'u0',
            initialMemberCount: 3,
          ),
        ),
        state: state,
      );
      await tester.pumpAndSettle();

      expect(find.text('joao'), findsWidgets);

      await tester.tap(find.text('joao').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.textContaining('joao'), findsWidgets);
    });

    testWidgets('members do not show "@" prefix', (tester) async {
      final state = await seededGroup();
      await pumpMatrixApp(
        tester,
        GroupProfileScreen(
          args: const GroupProfileRouteArgs(
            groupId: 'g1',
            initialName: 'Equipe MATRIX',
            initialAvatarUrl: null,
            initialDescription: 'Grupo de testes',
            initialOwnerId: 'u0',
            initialMemberCount: 3,
          ),
        ),
        state: state,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('@joao'), findsNothing);
      expect(find.text('joao'), findsWidgets);
    });
  });
}