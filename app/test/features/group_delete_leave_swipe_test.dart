import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/features/chat/chat_navigation.dart';
import 'package:matrix_app/features/chat/group_conversation_screen.dart';
import 'package:matrix_app/features/chat/group_members_screen.dart';
import 'package:matrix_app/features/chat/group_profile_screen.dart';
import 'package:matrix_app/models/conversation.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

/// Seeds a group owned by [ownerId] (default 'u0' = leonardo) with
/// [memberIds] (default {u0, u2}) and optional messages. The session user is
/// [sessionUserId] when provided (defaults to the FakeStore's 'u0').
Future<AppState> seededGroup({
  List<String> messages = const [],
  String groupName = 'Equipe MATRIX',
  Set<String> memberIds = const {'u0', 'u2'},
  String ownerId = 'u0',
  String? sessionUserId,
}) async {
  final repos = FakeRepositories();
  final store = repos.store;
  if (sessionUserId != null) store.currentUserId = sessionUserId;
  const id = 'g1';
  store.groups[id] = GroupConversation(
    id: id,
    group: GroupHeader(
      id: id,
      name: groupName,
      avatarUrl: null,
      description: 'Grupo de testes',
      createdById: ownerId,
      memberCount: memberIds.length,
    ),
    lastMessage: null,
    lastMine: false,
    unreadCount: 0,
    updatedAt: DateTime(2024, 1, 1),
  );
  store.groupMemberIds[id] = {...memberIds};
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

Widget profileScreen() => const GroupProfileScreen(
      args: GroupProfileRouteArgs(
        groupId: 'g1',
        initialName: 'Equipe MATRIX',
        initialAvatarUrl: null,
        initialDescription: 'Grupo de testes',
        initialOwnerId: 'u0',
        initialMemberCount: 2,
      ),
    );

void main() {
  group('swipe to reply em grupos (reusa ReplySwipe do privado)', () {
    testWidgets(
        'deslizar esquerda→direita na mensagem de OUTRO user ativa responder',
        (tester) async {
      final state = await seededGroup(messages: ['Oi!', 'Bora!']);
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      // "Bora!" is joao's (u2) message — swipe it left→right (+140 dx).
      await tester.drag(find.text('Bora!'), const Offset(140, 0),
          warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.textContaining('Respondendo a joao'), findsOneWidget);
    });

    testWidgets('deslizar direita→esquerda na PRÓPRIA mensagem ativa responder',
        (tester) async {
      final state = await seededGroup(messages: ['Eu', 'Deles']);
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      // "Eu" is the session user's message — swipe right→left (-140 dx).
      await tester.drag(find.text('Eu'), const Offset(-140, 0),
          warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.textContaining('Respondendo a leonardo'), findsOneWidget);
    });

    testWidgets('cancelar o reply via ✕ limpa o preview do grupo',
        (tester) async {
      final state = await seededGroup(messages: ['Oi!', 'Bora!']);
      await pumpMatrixApp(tester, groupScreen(), state: state);
      await tester.pumpAndSettle();

      await tester.drag(find.text('Bora!'), const Offset(140, 0),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.textContaining('Respondendo a joao'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining('Respondendo a joao'), findsNothing);
    });
  });

  group('EXCLUIR GRUPO (dono)', () {
    testWidgets('o menu de edição exibe "Excluir grupo" somente para o dono',
        (tester) async {
      // Session user IS the owner → menu shows the destructive option.
      final ownerState = await seededGroup(ownerId: 'u0');
      await pumpMatrixApp(tester, profileScreen(), state: ownerState);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Excluir grupo'), findsOneWidget);
    });

    testWidgets('confirmar exclui o grupo e sai da tela', (tester) async {
      final state = await seededGroup(ownerId: 'u0');
      await pumpMatrixApp(tester, profileScreen(), state: state);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir grupo'));
      await tester.pumpAndSettle();

      // Confirmation dialog appears with the destructive warning.
      expect(find.text('Excluir grupo?'), findsOneWidget);
      expect(find.textContaining('não é uma simples saída'), findsOneWidget);

      await tester.tap(find.text('Excluir').last);
      await tester.pumpAndSettle();

      // The group is gone from the cache → the profile screen popped.
      expect(state.groups.where((g) => g.id == 'g1'), isEmpty);
    });
  });

  group('SAIR DO GRUPO (mini menu de participantes)', () {
    testWidgets('membro ativo vê "Sair do grupo" no mini menu', (tester) async {
      // Session user is joao (u2), a MEMBER (owner = u0) → can leave.
      final state = await seededGroup(sessionUserId: 'u2');
      await pumpMatrixApp(
        tester,
        const GroupMembersScreen(
          args: GroupMembersRouteArgs(
            groupId: 'g1',
            groupName: 'Equipe MATRIX',
            ownerId: 'u0',
          ),
        ),
        state: state,
      );
      await tester.pumpAndSettle();

      // Tap any participant → the mini menu includes "Sair do grupo".
      await tester.tap(find.text('joao').first);
      await tester.pumpAndSettle();

      expect(find.text('Ver perfil'), findsOneWidget);
      expect(find.text('Sair do grupo'), findsOneWidget);
    });

    testWidgets('dono não vê "Sair do grupo" no mini menu', (tester) async {
      final state = await seededGroup(ownerId: 'u0'); // session user = owner
      await pumpMatrixApp(
        tester,
        const GroupMembersScreen(
          args: GroupMembersRouteArgs(
            groupId: 'g1',
            groupName: 'Equipe MATRIX',
            ownerId: 'u0',
          ),
        ),
        state: state,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('joao').first);
      await tester.pumpAndSettle();

      expect(find.text('Ver perfil'), findsOneWidget);
      expect(find.text('Sair do grupo'), findsNothing);
    });

    testWidgets('confirmar sair remove o usuário do grupo e sai da tela',
        (tester) async {
      final state = await seededGroup(sessionUserId: 'u2');
      await pumpMatrixApp(
        tester,
        const GroupMembersScreen(
          args: GroupMembersRouteArgs(
            groupId: 'g1',
            groupName: 'Equipe MATRIX',
            ownerId: 'u0',
          ),
        ),
        state: state,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('leonardo').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sair do grupo'));
      await tester.pumpAndSettle();

      expect(find.text('Sair do grupo?'), findsOneWidget);
      await tester.tap(find.text('Sair').last);
      await tester.pumpAndSettle();

      // Session user left → the group is no longer in the cache.
      expect(state.groups.where((g) => g.id == 'g1'), isEmpty);
    });
  });
}
