import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/features/chat/chat_navigation.dart';
import 'package:matrix_app/features/chat/conversation_screen.dart';
import 'package:matrix_app/features/chat/voice_player_bubble.dart';

import '../helpers/fake_record_channel.dart';
import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Gravação de voz (gestos)', () {
    Future<AppState> seededChat() async {
      final repos = FakeRepositories();
      repos.store.friendships.add('u0|u2');
      repos.store.chatMessagesByPair['u0|u2'] = [];
      final state = AppState(repositories: repos);
      await state.restoreSession();
      await state.loadFeed();
      await state.loadConversations();
      return state;
    }

    Future<void> pumpConversation(WidgetTester tester, AppState state) async {
      await pumpMatrixApp(
          tester,
          ConversationScreen(
            args: const ConversationRouteArgs(
              conversationId: 'u0|u2',
              otherUserId: 'u2',
              otherNickname: 'joao',
            ),
          ),
          state: state);
    }

    testWidgets('hold → release sends the audio automatically', (tester) async {
      final fake = FakeRecordChannels.install();
      addTearDown(fake.cleanup);
      final state = await seededChat();
      await pumpConversation(tester, state);

      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      final mic = find.byIcon(Icons.mic_rounded);
      final gesture = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('gravando áudio'), findsOneWidget);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('gravando áudio'), findsNothing);
      expect(find.text('Escreva sua mensagem...'), findsOneWidget);
      expect(fake.recordedPaths, hasLength(1));
      expect(find.byType(VoicePlayerBubble), findsOneWidget);
    });
    testWidgets('plain tap shows hold-to-record hint without capturing',
        (tester) async {
      final fake = FakeRecordChannels.install();
      addTearDown(fake.cleanup);
      final state = await seededChat();
      await pumpConversation(tester, state);

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('segure para gravar áudio'), findsOneWidget);
      expect(find.text('Escreva sua mensagem...'), findsOneWidget);
      expect(fake.recordedPaths, isEmpty);
      expect(find.text('gravando áudio'), findsNothing);
    });
    testWidgets('drag LEFT cancelsand discards the file', (tester) async {
      final fake = FakeRecordChannels.install();
      addTearDown(fake.cleanup);
      final state = await seededChat();
      await pumpConversation(tester, state);

      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      final mic = find.byIcon(Icons.mic_rounded);
      final gesture = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('gravando áudio'), findsOneWidget);
      await gesture.moveBy(const Offset(-80, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(fake.cancelCount, 1);
      expect(fake.recordedPaths, isEmpty);
      expect(find.text('gravando áudio'), findsNothing);
      expect(find.text('Escreva sua mensagem...'), findsOneWidget);
    });
    testWidgets('drag UP locks → mic becomes send → tap sends', (tester) async {
      final fake = FakeRecordChannels.install();
      addTearDown(fake.cleanup);
      final state = await seededChat();
      await pumpConversation(tester, state);

      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      final mic = find.byIcon(Icons.mic_rounded);
      final gesture = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump(const Duration(milliseconds: 300));
      expect(fake.recordedPaths, hasLength(1));
      expect(find.byType(VoicePlayerBubble), findsOneWidget);
    });
    testWidgets('permission denied → snackbar, composer stays usable',
        (tester) async {
      final fake = FakeRecordChannels.install();
      addTearDown(fake.cleanup);
      fake.permissionGranted = false;
      final state = await seededChat();
      await pumpConversation(tester, state);

      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Permissão do microfone'), findsOneWidget);
      expect(fake.recordedPaths, isEmpty);
      expect(find.text('gravando áudio'), findsNothing);
      expect(find.text('Escreva sua mensagem...'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.textContaining('Permissão do microfone'), findsNothing);
    });
    testWidgets('locked take survives release', (tester) async {
      final fake = FakeRecordChannels.install();
      addTearDown(fake.cleanup);
      final state = await seededChat();
      await pumpConversation(tester, state);

      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      final mic = find.byIcon(Icons.mic_rounded);
      final gesture = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('gravando áudio'), findsOneWidget);
      await gesture.moveBy(const Offset(0, -70));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      expect(find.text('gravando áudio'), findsOneWidget);
      expect(fake.recordedPaths, isEmpty);
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump(const Duration(milliseconds: 300));
      expect(fake.recordedPaths, hasLength(1));
      expect(find.byType(VoicePlayerBubble), findsOneWidget);
    });
  });
}
