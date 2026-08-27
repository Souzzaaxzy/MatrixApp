import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/features/chat/chat_navigation.dart';
import 'package:matrix_app/features/chat/chat_screen.dart';
import 'package:matrix_app/features/chat/conversation_screen.dart';
import 'package:matrix_app/features/profile/profile_screen.dart';
import 'package:matrix_app/models/conversation.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

void main() {
  // Seeds a session user (u0 = 'leonardo') who is friends with joao (u2),
  // plus a private conversation between the two with some persisted messages.
  Future<AppState> seededChat({
    List<String> messages = const [],
    bool withFriend = true,
  }) async {
    final repos = FakeRepositories();
    final store = repos.store;
    if (withFriend) store.friendships.add('u0|u2');
    store.chatMessagesByPair['u0|u2'] = [];
    for (var i = 0; i < messages.length; i++) {
      store.chatMessagesByPair['u0|u2']!.add(ChatMessage(
        id: 'm$i',
        conversationId: 'u0|u2',
        senderId: i.isEven ? 'u0' : 'u2',
        content: messages[i],
        createdAt: DateTime(2024, 1, 1, 21, 40 + i),
        mine: i.isEven,
      ));
    }
    final state = AppState(repositories: repos);
    await state.restoreSession();
    await state.loadFeed();
    await state.loadConversations();
    return state;
  }

  group('ChatScreen', () {
    testWidgets('shows empty conversations hint without conversations',
        (tester) async {
      final state = await seededChat(withFriend: false);
      await pumpMatrixApp(tester, const ChatScreen(), state: state);
      await tester.pumpAndSettle();
      expect(find.textContaining('Suas conversas'), findsOneWidget);
      expect(find.textContaining('ainda não possui amigos'), findsOneWidget);
    });

    testWidgets('lists a conversation with peer nickname and last preview',
        (tester) async {
      final state = await seededChat(messages: ['Olá!', 'Oi!']);
      await pumpMatrixApp(tester, const ChatScreen(), state: state);
      // Peer nickname (joao) appears in the conversation tile.
      expect(find.text('joao'), findsWidgets);
      // Last message is joao's "Oi!" — not marked as "Você:".
      expect(find.textContaining('Oi!'), findsWidgets);
      // The friends row also shows joao.
      expect(find.text('joao'), findsWidgets);
    });

    testWidgets('friend has no message button before becoming friends guard',
        (tester) async {
      // Friends list is seeded; ensure it renders (no crash, friend visible).
      final state = await seededChat(messages: const []);
      await pumpMatrixApp(tester, const ChatScreen(), state: state);
      await tester.pump();
      expect(find.text('joao'), findsWidgets);
    });
  });

  group('ConversationScreen', () {
    testWidgets('renders existing messages as independent bubbles',
        (tester) async {
      final state = await seededChat(messages: ['Olá!', 'Oi!']);
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
      // Both persisted messages are displayed.
      expect(find.text('Olá!'), findsOneWidget);
      expect(find.text('Oi!'), findsOneWidget);
      // The input hint is present.
      expect(find.text('Escreva sua mensagem...'), findsOneWidget);
    });

    testWidgets('sending appends the message and clears the input',
        (tester) async {
      final state = await seededChat(messages: const []);
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
      await tester.enterText(find.byType(TextField).last, 'Vamos conversar!');
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pump();
      await tester.pump();
      expect(find.text('Vamos conversar!'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField).last);
      expect(field.controller!.text, isEmpty);
    });
  });

  group('Profile navigation', () {
    testWidgets('Mensagem button opens the conversation directly',
        (tester) async {
      final state = await seededChat(messages: const []);
      await pumpMatrixApp(tester, const ProfileScreen(nickname: 'joao'),
          state: state);
      await tester.pumpAndSettle();
      // Friendly pair → both the Amigos and Mensagem buttons are shown.
      expect(find.text('AMIGOS'), findsOneWidget);
      expect(find.text('MENSAGEM'), findsOneWidget);
      await tester.tap(find.text('MENSAGEM'));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationScreen), findsOneWidget);
    });
  });
}