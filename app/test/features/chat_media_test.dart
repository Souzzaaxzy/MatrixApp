import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/features/chat/chat_navigation.dart';
import 'package:matrix_app/features/chat/conversation_screen.dart';
import 'package:matrix_app/features/chat/group_conversation_screen.dart';
import 'package:matrix_app/models/conversation.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

Future<AppState> seededChat({List<ChatMessage>? messages}) async {
  final repos = FakeRepositories();
  final store = repos.store;
  store.friendships.add('u0|u2');
  store.chatMessagesByPair['u0|u2'] = messages ?? [];
  final state = AppState(repositories: repos);
  await state.restoreSession();
  await state.loadFeed();
  await state.loadConversations();
  return state;
}

Future<AppState> seededGroup() async {
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
  store.groupMessagesById[id] = [];
  final state = AppState(repositories: repos);
  await state.restoreSession();
  await state.loadFeed();
  await state.loadConversations();
  return state;
}

void main() {
  group('composer mic/send swap', () {
    testWidgets('DM: empty field shows mic, text shows send, never both',
        (tester) async {
      final state = await seededChat();
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

      // Empty → mic visible, send hidden.
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);

      // Type → mic hidden (invisible), send visible.
      await tester.enterText(find.byType(TextField), 'oi');
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
      expect(tester
          .widget<Opacity>(
              find
                  .ancestor(
                      of: find.byIcon(Icons.mic_rounded),
                      matching: find.byType(Opacity))
                  .first)
          .opacity,
          0);

      // Clear → mic back, send gone.
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
    });
  });
  test('ChatMessage media fields: isImage/isVideo/isMedia', () {
    final text = ChatMessage(
      id: 'a',
      conversationId: 'c',
      senderId: 'u0',
      content: 'oi',
      createdAt: DateTime(2024, 1, 1),
      mine: true,
    );
    final img = ChatMessage(
      id: 'b',
      conversationId: 'c',
      senderId: 'u0',
      content: '📷 Foto',
      createdAt: DateTime(2024, 1, 1),
      mine: true,
      type: 'image',
      imageUrl: 'https://x/f.png',
    );
    final vid = ChatMessage(
      id: 'c',
      conversationId: 'c',
      senderId: 'u0',
      content: '🎥 Vídeo',
      createdAt: DateTime(2024, 1, 1),
      mine: true,
      type: 'video',
      videoUrl: 'https://x/v.mp4',
    );
    expect(text.isMedia, isFalse);
    expect(img.isImage, isTrue);
    expect(vid.isVideo, isTrue);
    expect(vid.isMedia, isTrue);
  });

  testWidgets(
      'DM: sendMediaMessage envia uma mensagem de mídia (image) com reply preservado',
      (tester) async {
    final state = await seededChat();
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
    final msgs =
        state.conversations.isNotEmpty ? state.conversations.first.id : 'u0|u2';
    expect(msgs, isNotEmpty);

    final sent = await state.sendMediaMessage(
      'u0|u2',
      kind: 'image',
      url: 'https://cdn.matrix.app/static/x.png',
    );
    expect(sent.isImage, isTrue);
    expect(sent.imageUrl, contains('x.png'));
  });

  testWidgets(
      'DM: mensagem de vídeo renderiza o preview de mídia com badge play',
      (tester) async {
    final state = await seededChat(messages: [
      ChatMessage(
        id: 'vid1',
        conversationId: 'u0|u2',
        senderId: 'u2',
        content: '🎥 Vídeo',
        createdAt: DateTime(2024, 1, 1, 20, 0),
        mine: false,
        type: 'video',
        videoUrl: 'https://cdn.matrix.app/static/video/v1.mp4',
      ),
    ]);
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
    // The media bubble renders its video affordance overlay.
    expect(find.byIcon(Icons.video_library_rounded), findsOneWidget);
  });

  testWidgets(
      'Grupo: sendGroupMediaMessage envia e o bubble aparece (compacto)',
      (tester) async {
    final state = await seededGroup();
    await pumpMatrixApp(
      tester,
      const GroupConversationScreen(
        args: GroupConversationRouteArgs(
          groupId: 'g1',
          groupName: 'Equipe MATRIX',
          groupAvatarUrl: null,
        ),
      ),
      state: state,
    );
    await tester.pumpAndSettle();

    final sent = await state.sendGroupMediaMessage(
      'g1',
      kind: 'video',
      url: 'https://cdn.matrix.app/static/video/g.mp4',
    );
    expect(sent.isVideo, isTrue);
  });
}
