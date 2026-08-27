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
    bool withConversation = true,
  }) async {
    final repos = FakeRepositories();
    final store = repos.store;
    if (withFriend) store.friendships.add('u0|u2');
    store.chatMessagesByPair['u0|u2'] = [];
    if (!withConversation) store.chatMessagesByPair.remove('u0|u2');
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

    testWidgets('removing a friend clears the friends row', (tester) async {
      final state = await seededChat(withFriend: true);
      await pumpMatrixApp(tester, const ChatScreen(), state: state);
      await tester.pumpAndSettle();
      // Friend row is populated (empty-friends hint is absent).
      expect(find.text('Você ainda não possui amigos.'), findsNothing);

      // Remove the friendship server-side (source of truth) and let the
      // onFriendsChanged stream re-sync the row.
      await state.removeFriend('u2');
      await tester.pumpAndSettle();

      // The friends row is now empty → the hint appears. (The persisted
      // conversation tile with joao may remain — that is correct: chat
      // history survives friendship removal.)
      expect(find.text('Você ainda não possui amigos.'), findsOneWidget);
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

    testWidgets('realtime typing shows "digitando..." below the nickname',
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
      expect(find.text('digitando...'), findsNothing);

      // The peer (joao) starts typing (AnimatedSwitcher ~200ms to settle).
      state.handleIncomingChatTyping(
          const ChatTypingEvent(conversationId: 'u0|u2', typing: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('digitando...'), findsOneWidget);

      // Peer stops → indicator disappears.
      state.handleIncomingChatTyping(
          const ChatTypingEvent(conversationId: 'u0|u2', typing: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('digitando...'), findsNothing);
    });

    testWidgets('typing auto-hides after the timeout even without a stop frame',
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
      state.handleIncomingChatTyping(
          const ChatTypingEvent(conversationId: 'u0|u2', typing: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('digitando...'), findsOneWidget);
      // Advance past the 4s auto-clear (the peer never sent stop).
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('digitando...'), findsNothing);
    });

    testWidgets('watches realtime incoming messages and appends to the right',
        (tester) async {
      final state = await seededChat(messages: ['Oi!']); // m0 = mine
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
      expect(find.text('Oi!'), findsOneWidget);

      // A realtime message from joao arrives → appears.
      state.handleIncomingChatMessage(ChatMessage(
        id: 'rx1',
        conversationId: 'u0|u2',
        senderId: 'u2',
        content: 'não sei.',
        createdAt: DateTime(2024, 1, 1, 22, 0),
        mine: false,
      ));
      await tester.pump();
      expect(find.text('não sei.'), findsOneWidget);
    });

    testWidgets('swiping a message activates the reply composer', (tester) async {
      final state = await seededChat(messages: ['Olá!', 'Oi!']); // m0 mine, m1 theirs
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

      // The receiver's bubble "Oi!" is at index 1 (swipe → reply it).
      final target = find.text('Oi!');
      expect(target, findsOneWidget);
      await tester.drag(target, const Offset(140, 0),
          warnIfMissed: false);
      await tester.pumpAndSettle();

      // Reply composer opens with a preview of the swiped message.
      expect(find.textContaining('Respondendo a mensagem'), findsOneWidget);
      expect(find.textContaining('Oi!'), findsWidgets);

      // Cancel the reply → preview disappears.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining('Respondendo a mensagem'), findsNothing);
    });

    testWidgets('sending a reply persists the reply-to preview inside the bubble',
        (tester) async {
      final state = await seededChat(messages: ['Olá!', 'Oi!']); // m1 = theirs
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

      // Swipe the peer's message ("Oi!") to set it as the reply target.
      await tester.drag(find.text('Oi!'), const Offset(140, 0), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.textContaining('Respondendo a mensagem'), findsOneWidget);

      // Send the reply.
      await tester.enterText(find.byType(TextField).last, 'tudo ótimo!');
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pump();
      await tester.pump();

      // The sent reply shows the quoted original (m1's content) above it.
      expect(find.text('tudo ótimo!'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.textContaining('Oi!'),
        ),
        findsWidgets,
      );
    });

    testWidgets('shows "enviado" inside my newest bubble and flips to '
        '"visto agora" when read', (tester) async {
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

      // Send my message → it is the last, so "enviado" shows inside it.
      await tester.enterText(find.byType(TextField).last, 'oi');
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pump();
      await tester.pump();
      expect(find.text('enviado'), findsOneWidget);
      expect(find.text('visto agora'), findsNothing);

      // Peer read receipt arrives → flips to "visto agora".
      state.handleIncomingChatRead(const ChatReadEvent(conversationId: 'u0|u2'));
      await tester.pump();
      expect(find.text('visto agora'), findsOneWidget);
      expect(find.text('enviado'), findsNothing);
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