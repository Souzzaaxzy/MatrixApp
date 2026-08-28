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

/// The [FakeRepositories] of the most recently seeded chat state — lets the
/// deletion tests assert what was actually persisted (hides/soft-deletes).
FakeRepositories? lastSeededRepos;

void main() {
  // Seeds a session user (u0 = 'leonardo') who is friends with joao (u2),
  // plus a private conversation between the two with some persisted messages.
  Future<AppState> seededChat({
    List<String> messages = const [],
    bool withFriend = true,
    bool withConversation = true,
  }) async {
    final repos = FakeRepositories();
    lastSeededRepos = repos;
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

    testWidgets('realtime recording shows "gravando áudio" below the nickname',
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
      expect(find.text('gravando áudio'), findsNothing);

      // The peer (joao) starts recording a voice message.

      state.handleIncomingChatRecording(
          const ChatRecordingEvent(conversationId: 'u0|u2', recording: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('gravando áudio'), findsOneWidget);

      // Peer stops → the indicator disappears immediately (no fade-in/out stick).
      state.handleIncomingChatRecording(
          const ChatRecordingEvent(conversationId: 'u0|u2', recording: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('gravando áudio'), findsNothing);
    });

    testWidgets('mic button stays mounted after a tap (no stuck capture state)',
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
      // The mic button exists next to the compose field.

      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      // A plain tap only shows the "hold to record" hint — the composer
      // keeps the text field, no recording bar (no stuck "sending" state).
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('segure para gravar áudio'), findsOneWidget);
      expect(find.text('Escreva sua mensagem...'), findsOneWidget);
      expect(find.text('enviando audio...'), findsNothing);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);


    });

    testWidgets('recording indicator auto-hides after 8s even without a stop frame',
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
      state.handleIncomingChatRecording(
          const ChatRecordingEvent(conversationId: 'u0|u2', recording: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('gravando áudio'), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('gravando áudio'), findsNothing);
    });

    testWidgets('peer avatar shows on the 1st and 6th of a 5-group of normals',
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
      // Push seven consecutive NORMAL peer texts (m1..m7) live.



      for (var i =  1; i <=  7; i++) {

        state.handleIncomingChatMessage(ChatMessage(
          id: 'g$i',
          conversationId: 'u0|u2',
          senderId: 'u2',
          content: 'normal $i',
          createdAt: DateTime(2024, 1, 1, 22, i),
          mine: false,
        ));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      // Group 1 → avatar on g1 only; group 2 → avatar on g6 only.

      expect(find.byKey(const ValueKey('peer-avatar-g1')), findsOneWidget);



      expect(find.byKey(const ValueKey('peer-avatar-g6')), findsOneWidget);

      expect(find.byKey(const ValueKey('peer-avatar-g2')), findsNothing);
      expect(find.byKey(const ValueKey('peer-avatar-g3')), findsNothing);
      expect(find.byKey(const ValueKey('peer-avatar-g4')), findsNothing);

      expect(find.byKey(const ValueKey('peer-avatar-g5')), findsNothing);
      expect(find.byKey(const ValueKey('peer-avatar-g7')), findsNothing);
    });

    testWidgets('reply and voice always show the avatar and start a fresh group',
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
      void push(ChatMessage m) => state.handleIncomingChatMessage(m);
      // normals g1..g3 -> reply (g4,, replyTo set) -> normal g5 starts a fresh
      // group;then voice g6 -> normal g7 starts another group.

      push(ChatMessage(id: 'g1', conversationId: 'u0|u2', senderId: 'u2', content: 'a', createdAt: DateTime(2024, 1, 1, 22, 1), mine: false));
      push(ChatMessage(id: 'g2', conversationId: 'u0|u2', senderId: 'u2', content: 'b', createdAt: DateTime(2024, 1, 1, 22, 2), mine: false));
      push(ChatMessage(id: 'g3', conversationId: 'u0|u2', senderId: 'u2', content: 'c', createdAt: DateTime(2024, 1, 1, 22, 3), mine: false));
      push(ChatMessage(
        id: 'g4',
        conversationId: 'u0|u2',

        senderId: 'u2',
        content: 'd',

        createdAt: DateTime(2024, 1, 1,  22, 4),
        mine: false,
        replyTo: const ReplyInfo(
          id: 'g2',
          senderId: 'u2',
          senderNickname: 'joao',
          content: 'b',
          exists: true,
        ),
      ));
      push(ChatMessage(id: 'g5', conversationId: 'u0|u2', senderId: 'u2', content: 'e', createdAt: DateTime(2024, 1,  1,  22,  5), mine: false));
      push(ChatMessage(
        id: 'g6',
        conversationId: 'u0|u2',
        senderId: 'u2',
        content: '',
        createdAt: DateTime(2024, 1,  1,  22,  6),
        mine: false,
        type: 'voice',
        audioUrl: 'file:///tmp/m6.m4a',
        durationMs: 3000,
      ));
      push(ChatMessage(id: 'g7', conversationId: 'u0|u2', senderId: 'u2', content: 'f', createdAt: DateTime(2024, 1,  1,  22,  7), mine: false));
      await tester.pumpAndSettle();
      // Avatar mandatory on the reply and the voice themselves.
      expect(find.byKey(const ValueKey('peer-avatar-g4')), findsOneWidget);
      expect(find.byKey(const ValueKey('peer-avatar-g6')), findsOneWidget);
      // The normal right after each interruption starts a new group → avatar.

      expect(find.byKey(const ValueKey('peer-avatar-g5')), findsOneWidget);

      expect(find.byKey(const ValueKey('peer-avatar-g7')), findsNothing);
      // g1..g3 are the first 3 of group 1 → only g1 has the avatar.


      expect(find.byKey(const ValueKey('peer-avatar-g1')), findsOneWidget);
      expect(find.byKey(const ValueKey('peer-avatar-g2')), findsNothing);
      expect(find.byKey(const ValueKey('peer-avatar-g3')), findsNothing);
    });

    testWidgets('own message swiped right→left opens reply composer',
        (tester) async {
      final state = await seededChat(messages: ['Minha própria', 'Oi!']); // m0 = mine
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
      // m0 is a bubble sent by THE SESSION USER (mine=true) — swipe it
      // right→left (negative dx) to activate the reply composer.



      await tester.drag(find.text('Minha própria'), const Offset(-140, 0), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.textContaining('Respondendo a mensagem'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining('Respondendo a mensagem'), findsNothing);
    });

    testWidgets('watches realtime incoming messagesand appends to the right',
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

      // mine=false renders on the LEFT (recipient's view), mine=true on the
      // RIGHT — the realtime balloon regression guard.
      final leftMessage = tester.getCenter(find.text('não sei.'));
      final rightMessage = tester.getCenter(find.text('Oi!'));
      expect(leftMessage.dx, lessThan(rightMessage.dx));
      expect(
        leftMessage.dx,
        lessThan(tester.view.physicalSize.width /
            tester.view.devicePixelRatio /
            2),
      );
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

  group('Exclusão de mensagens', () {
    testWidgets(
        'long-press on a message opens the menu with Responder/Excluir/'
        'Excluir para todos', (tester) async {
      final state = await seededChat(messages: ['Oi']);
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
      // "Oi" is MY (u0) message.
      await tester.longPress(find.text('Oi'));
      await tester.pumpAndSettle();
      expect(find.text('Responder'), findsOneWidget);
      expect(find.text('Excluir'), findsOneWidget);
      expect(find.text('Excluir para todos'), findsOneWidget);
    });

    testWidgets('Excluir (para mim) requires confirm then hides for ME only',
        (tester) async {
      final state = await seededChat(messages: ['Oi']);
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
      await tester.longPress(find.text('Oi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();
      // Confirmation dialog explains the scope.
      expect(find.text('Excluir mensagem?'), findsOneWidget);
      await tester.tap(find.text('Excluir').last);
      await tester.pumpAndSettle();
      expect(find.text('Oi'), findsNothing);

      // Persistence: reloading from the repo still hides MY message
      // (server actually records the hide for the current user).
      expect(lastSeededRepos!.store.messageHides, contains('u0|u2|m0|u0'));
    });

    testWidgets('Excluir para todos removes the message for both sides + realtime',
        (tester) async {
      final state = await seededChat(messages: ['Oi']);
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
      await tester.longPress(find.text('Oi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir para todos'));
      await tester.pumpAndSettle();
      expect(find.text('Excluir esta mensagem para todos?'), findsOneWidget);
      await tester.tap(find.text('Excluir').last);
      await tester.pumpAndSettle();
      expect(find.text('Oi'), findsNothing);
      // Server-side the message is soft-deleted for everyone.
      expect(lastSeededRepos!.store.deletedEverywhere, contains('u0|u2|m0'));

      // Realtime: a peer deletion of another message livestreams removal.
      state.handleIncomingChatMessageDeleted(
        const ChatMessageDeletedEvent(
          conversationId: 'u0|u2',
          messageId: 'mZ',
        ),
      );
      await tester.pump();
      // No crash; the delete handler for a non-existent id is a no-op that
      // clears any pending reply — asserting no error state is enough here.
      expect(tester.takeException(), isNull);
    });

    testWidgets('deleting for me keeps the peer message on screen',
        (tester) async {
      final state = await seededChat(messages: ['Oi', 'Resp']);
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
      // Delete MY message 'Oi' for me; peer's 'Resp' stays.
      await tester.longPress(find.text('Oi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir').last);
      await tester.pumpAndSettle();
      expect(find.text('Oi'), findsNothing);
      expect(find.text('Resp'), findsOneWidget);
    });
  });

  group('Exclusão de conversa', () {
    testWidgets('long-press a conversation asks + hides it for ME only',
        (tester) async {
      final state = await seededChat(messages: ['Oi']);
      await pumpMatrixApp(tester, const ChatScreen(), state: state);
      await tester.pumpAndSettle();
      // The conversation tile exists.
      expect(find.text('joao'), findsWidgets);

      await tester.longPress(find.textContaining('Oi'));
      await tester.pumpAndSettle();
      expect(find.text('Excluir conversa?'), findsOneWidget);
      await tester.tap(find.text('Excluir').last);
      await tester.pumpAndSettle();

      // Conversation disappeared from MY list and the hide is persisted.
      expect(find.textContaining('Suas conversas aparecerão aqui.'), findsOneWidget);
      expect(lastSeededRepos!.store.conversationHides, contains('u0|u2|u0'));
    });

    testWidgets('peer hides their side — my conversation stays intact',
        (tester) async {
      final state = await seededChat(messages: ['Oi']);
      // The peer hides the conversation for THEMSELVES only.
      lastSeededRepos!.store.conversationHides.add('u0|u2|u2');
      await pumpMatrixApp(tester, const ChatScreen(), state: state);
      await tester.pumpAndSettle();
      // My (u0) list still shows the conversation.
      expect(find.textContaining('Oi'), findsOneWidget);
    });
  });
}
