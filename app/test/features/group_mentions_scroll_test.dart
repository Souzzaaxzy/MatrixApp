import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/features/chat/chat_navigation.dart';
import 'package:matrix_app/features/chat/chat_screen.dart';
import 'package:matrix_app/features/chat/group_conversation_screen.dart';
import 'package:matrix_app/models/conversation.dart';
import 'package:matrix_app/models/matrix_user.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

/// The FakeStore used by the most recent [seededGroup] call (lets tests
/// inspect what was actually sent — mentions/ranges — end-to-end).
FakeStore? _lastStore;

/// The last group message persisted by the fake repository for the group
/// seeded by the most recent [seededGroup] call (compose→send round trip).
/// Throws when no message was persisted (a failed send path).
ChatMessage storeLastMessage() {
  final store = _lastStore;
  final messages = store?.groupMessagesById['g1'];
  if (messages == null || messages.isEmpty) {
    throw StateError('Nenhuma mensagem foi enviada pelo fake.');
  }
  return messages.last;
}

/// Seeds a group owned by u0 (leonardo) with u2 (joao) as a member and the
/// given messages (even index = u0's own, odd = u2's).
Future<AppState> seededGroup({
  List<String> messages = const [],
  String? sessionUserId,
  bool withCarla = false,
}) async {
  final repos = FakeRepositories();
  final store = repos.store;
  _lastStore = store;
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
  store.groupMemberIds[id] = {'u0', 'u2', if (withCarla) 'u3'};
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

    testWidgets(
        'menção é INLINE acima do composer (sem modal/nova rota) e filtra',
        (tester) async {
      final state = await seededGroup();
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      // Typing "@" shows the inline bar — NOT a new modal route.
      await tester.enterText(find.byType(TextField).last, '@');
      await tester.pumpAndSettle();
      expect(find.text('MENCIONAR'), findsOneWidget);
      // No bottom-sheet route was pushed — the bar is part of the chat
      // Column, so no BottomSheet widget exists.
      expect(find.byType(BottomSheet), findsNothing);

      // Filtering: "@jo" keeps only joao (nickname without the @ prefix).
      await tester.enterText(find.byType(TextField).last, '@jo');
      await tester.pumpAndSettle();
      expect(find.text('joao'), findsOneWidget);

      // Selecting inserts the mention and hides the bar.
      await tester.tap(find.text('joao'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField).last);
      expect(field.controller!.text, contains('@joao '));
      expect(find.text('MENCIONAR'), findsNothing);

      // Deleting the "@" never leaves a stray bar.
      await tester.enterText(find.byType(TextField).last, 'oi');
      await tester.pumpAndSettle();
      expect(find.text('MENCIONAR'), findsNothing);
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

    testWidgets('digitar @nickname MANUALMENTE e enviar NÃO cria mention',
        (tester) async {
      final state = await seededGroup();
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      // Type the nickname manually without opening/picking the suggestions.
      await tester.enterText(find.byType(TextField).last, 'Oi @joao!');
      await tester.pumpAndSettle();

      // Wait for the suggestion bar to disappear (no trailing token).
      await tester.pump(const Duration(milliseconds: 200));

      // Send the message.
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      final sent = storeLastMessage();
      expect(sent.content, 'Oi @joao!');
      // NO structured mention was created by mere text coincidence.
      expect(sent.mentions, isEmpty);
      expect(sent.mentionAll, isFalse);
      expect(sent.mentioned, isFalse);
    });

    testWidgets('selecionar usuário no menu cria mention REAL ao enviar',
        (tester) async {
      final state = await seededGroup();
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '@');
      await tester.pumpAndSettle();
      expect(find.text('MENCIONAR'), findsOneWidget);
      await tester.pumpAndSettle();

      // Pick joao in the suggestions.
      await tester.tap(find.text('joao').first);
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField).last);
      expect(field.controller!.text, contains('@joao '));

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      final sent = storeLastMessage();
      expect(sent.content, contains('@joao'));
      expect(sent.mentions, hasLength(1));
      final m = sent.mentions.first;
      expect(m.userId, 'u2');
      expect(m.nickname, 'joao');
      // The token range is anchored EXACTLY to "@joao".
      expect(m.start, isNotNull);
      expect(m.end, isNotNull);
      expect(sent.content.substring(m.start!, m.end!), '@joao');
    });

    testWidgets('apagar uma letra da mention selecionada a invalida',
        (tester) async {
      final state = await seededGroup();
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '@');
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.text('joao').first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byType(TextField).last)
            .controller!
            .text
            .contains('@joao '),
        isTrue,
      );

      // Delete one letter — "@joa" now.
      await tester.enterText(find.byType(TextField).last, '@joa ');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      final sent = storeLastMessage();
      expect(sent.mentions, isEmpty);
      expect(sent.mentionAll, isFalse);
    });

    testWidgets('alterar e VOLTAR ao nickname original NÃO restaura a mention',
        (tester) async {
      final state = await seededGroup();
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '@');
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.text('joao').first);
      await tester.pumpAndSettle();

      // @joao → @joa → @joao (delete then re-add the same letter). Each edit
      // fires onChanged so the tracker reconciles the range.
      await tester.enterText(find.byType(TextField).last, '@joa ');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '@joao ');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      final sent = storeLastMessage();
      // Reverting the text does NOT resurrect the destroyed mention — the
      // user must select joao again.
      expect(sent.mentions, isEmpty);
    });

    testWidgets('@todos SEM seleção é texto comum (não gera mentionAll)',
        (tester) async {
      final state = await seededGroup(); // u0 is the owner
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      // The owner just TYPES @todos — never picks it from the menu.
      await tester.enterText(find.byType(TextField).last, '@todos alguém?');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      final sent = storeLastMessage();
      expect(sent.mentions, isEmpty);
      expect(sent.mentionAll, isFalse);
      expect(sent.mentioned, isFalse);
    });

    testWidgets('@todos apenas SELEÇÃO no menu cria mention de todos',
        (tester) async {
      final state = await seededGroup(); // owner
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '@');
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.text('@todos'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      final sent = storeLastMessage();
      // @todos is serialized through mentionAll (mirrors the server).
      expect(sent.mentionAll, isTrue);
      expect(sent.content, contains('@todos'));
      expect(sent.mentioned, isTrue);
    });

    testWidgets('membro comum NÃO vê @todos no menu',
        (tester) async {
      final state = await seededGroup(sessionUserId: 'u2');
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '@');
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(find.text('@todos'), findsNothing);
    });

    testWidgets('múltiplas mentions independentes: editar uma não quebra a outra',
        (tester) async {
      final state = await seededGroup(withCarla: true);
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      // Pick joao.
      await tester.enterText(find.byType(TextField).last, '@');
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.text('joao').first);
      await tester.pumpAndSettle();

      // Pick carla right after.
      await tester.enterText(find.byType(TextField).last, '@joao @');
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.text('carla').first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byType(TextField).last)
            .controller!
            .text
            .contains('@carla '),
        isTrue,
      );

      // Edit ONLY the joao token (delete its last letter) — full-text edit that
      // fires onChanged, simulating a real caret edit.
      await tester.enterText(find.byType(TextField).last, '@joa @carla ');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      final sent = storeLastMessage();
      // joao is gone (destroyed); carla SURVIVES with her own range.
      expect(sent.mentions.where((m) => m.userId == 'u2'), isEmpty);
      final carla = sent.mentions.firstWhere((m) => m.userId == 'u3');
      expect(sent.content.substring(carla.start!, carla.end!), '@carla');
    });

    testWidgets('colar @nickname no composer NÃO cria mention', (tester) async {
      final state = await seededGroup();
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      // Pasting text containing @joao (no selection flow).
      await tester.enterText(find.byType(TextField).last, 'veja @joao agora');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      final sent = storeLastMessage();
      expect(sent.mentions, isEmpty);
      expect(sent.mentionAll, isFalse);
    });

    testWidgets('menção selecionada aparece em NEGRITO no composer',
        (tester) async {
      final state = await seededGroup(withCarla: true);
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      // Select joao.

      await tester.enterText(find.byType(TextField).last, '@');
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.text('joao').first);
      await tester.pumpAndSettle();

      // The composer text is still plain — ONLY the visual spans bold the
      // mention token,and everything around it stays normal.

      final field = tester.widget<TextField>(find.byType(TextField).last);
      final controller = field.controller!;
      expect(controller.text, contains('@joao '));

      final span = controller.buildTextSpan(
        context: tester.element(find.byType(TextField).last),
        style: const TextStyle(fontSize: 15),
        withComposing: false,
      );
      final bold = <String>[];
      final plain = <String>[];
      span.visitChildren((child) {
        if (child is TextSpan) {
          if (child.style?.fontWeight == FontWeight.w800) {
            bold.add(child.text ?? '');
          } else {
            plain.add(child.text ?? '');
          }
        }
        return true;
      });
      // ONLY "@joao" is bolded — normal text before/after keeps its style.

      expect(bold, ['@joao']);
      expect(plain.any((t) => t.contains('@joao')), isFalse);

      // Even after typing more text AFTER the mention (incremental caret
      // append — the token range itself is untouched), it stays bold.
      await tester.enterText(find.byType(TextField).last, '@joao tudo bem?');
      await tester.pumpAndSettle();
      final rebuilt = tester
          .widget<TextField>(find.byType(TextField).last)
          .controller!
          .buildTextSpan(
            context: tester.element(find.byType(TextField).last),
            style: const TextStyle(fontSize: 15),
            withComposing: false,
          );
      final bold2 = <String>[];
      rebuilt.visitChildren((child) {
        if (child is TextSpan && child.style?.fontWeight == FontWeight.w800) {
          bold2.add(child.text ?? '');
        }
        return true;
      });
      // ONLY the mention token is bold — surrounding normal text never is.
      expect(bold2, ['@joao']);
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

  group('Amigos — todas as amizades aparecem', () {
    testWidgets('mais de 50 amigos são carregados (paginação até o total)',
        (tester) async {
      final repos = FakeRepositories();
      final store = repos.store;
      // Seed friendships: current user u0 is friends with 55 users.
      for (var i = 0; i < 55; i++) {
        final id = 'f$i';
        store.users[id] =
            MatrixUser(id: id, nickname: 'amigo_$i', avatarSeed: 'amigo_$i');
        store.friendships.add('f$i|u0');
      }
      final state = AppState(repositories: repos);
      await state.restoreSession();
      await state.loadFeed();
      await state.loadConversations();
      await pumpMatrixApp(tester, const ChatScreen(), state: state);
      await tester.pumpAndSettle();

      // The horizontal friends row must render ALL friends — the LAST one is
      // reachable by scrolling right (right-to-left).
      await tester.drag(find.byType(ListView).first, const Offset(-6000, 0));
      await tester.pumpAndSettle();
      expect(find.text('amigo_54'), findsOneWidget);
    });
  });
}
