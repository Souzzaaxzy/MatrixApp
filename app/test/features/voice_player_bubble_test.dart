import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/features/chat/chat_navigation.dart';
import 'package:matrix_app/features/chat/conversation_screen.dart';
import 'package:matrix_app/features/chat/voice_player_bubble.dart';
import 'package:matrix_app/models/conversation.dart';

import '../helpers/fake_just_audio.dart';
import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

/// A voice message as stored by the server (type voice, audioUrl + durationMs).
ChatMessage voiceMsg(
  String id, {
  bool mine = true,
  DateTime? createdAt,
  int durationMs = 3000,
}) =>
    ChatMessage(
      id: id,
      conversationId: 'u0|u2',
      senderId: mine ? 'u0' : 'u2',
      content: '',
      createdAt: createdAt ?? DateTime(2024, 1, 1, 22, 0),
      mine: mine,
      type: 'voice',
      audioUrl: 'file:///tmp/$id.m4a',
      durationMs: durationMs,
    );

/// Seeds the session user (u0) friend with joao (u2) + the given messages..
Future<AppState> seededVoiceChat(List<ChatMessage> messages) async {
  final repos = FakeRepositories();
  repos.store.friendships.add('u0|u2');
  repos.store.chatMessagesByPair['u0|u2'] = List.of(messages);
  final state = AppState(repositories: repos);
  await state.restoreSession();
  await state.loadFeed();
  await state.loadConversations();
  return state;
}

Future<void> pumpVoiceConversation(WidgetTester tester, AppState state) async {
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
}

/// Advances fake-async time while letting just_audio's platform chain (all
/// real `Future`s from [FakeJustAudio], which don't run on the fake clock)make
/// progress. `pump` alone starves the chain since it only advances test-zone
/// microtasks; `runAsync` bridges into real async so platform `init`/
/// `load`/`play` completions can re-enter the widget zone between frames.
Future<void> pumpPlatformChain(WidgetTester tester) async {
  for (var i = 1; i <= 200; i++) {
    await tester.pump(const Duration(milliseconds: 1));
    if (fakeJustAudio.players.isNotEmpty &&
        fakeJustAudio.players.first.playing) {

      return;
    }
    // Let a real-async round trip complete every few frames.
    if (i % 20 == 0) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)));
    }
  }
  throw StateError('Voice player did not reach playing state');
}

/// The progress indicator inside the given voice bubble..
Finder progressOf(Finder bubble) => find.descendant(
      of: bubble,
      matching: find.byType(LinearProgressIndicator),
    );

void main() {
  group('VoicePlayerBubble playback', () {
    testWidgets(
        'ao terminar o audio o botao volta ao play e o progresso zera,'
        ' e tocar novamente reproduz do zero', (tester) async {
      installFakeJustAudio();
      final state = await seededVoiceChat([voiceMsg('v1')]);
      await pumpVoiceConversation(tester, state);

      final bubble = find.byType(VoicePlayerBubble);
      expect(bubble, findsOneWidget);
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      unlockAudioFocus();
      await tester.pump();
      await pumpPlatformChain(tester);

      final player = fakeJustAudio.players.single;

      expect(player.playing, isTrue);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      // O audio chegou ao fim: a UI atualiza sozinha (sem sair, sem refresh}
      // e volta ao estado inicial: botao play + bar zerada..
      await player.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(player.playing, isFalse);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      final p1 = tester.widget<LinearProgressIndicator>(progressOf(bubble));
      expect(p1.value!, closeTo(0.0, 0.001));

      // Tocar novamente: o player faz seek para zero eind toca..
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      await pumpPlatformChain(tester);
      expect(player.seekCount, 1);
      expect(player.playing, isTrue);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      // Segundo termino: volta ao estado inicial novamente..
      await player.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      final p2 = tester.widget<LinearProgressIndicator>(progressOf(bubble));
      expect(p2.value!, closeTo(0.0, 0.001));
    });
  });
}
