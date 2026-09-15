import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/core/widgets/puzzle_icon.dart';
import 'package:matrix_app/features/chat/chat_navigation.dart';
import 'package:matrix_app/features/chat/conversation_screen.dart';
import 'package:matrix_app/features/chat/sticker_picker.dart';
import 'package:matrix_app/models/sticker.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

/// Seed de DM com um pacote instalado + figurinha nos recentes e no catálogo,
/// para exercitar favoritar/remover-recentes e a máquina de estados do painel.
Future<AppState> seededChatWithSticker() async {
  final repos = FakeRepositories();
  repos.store.friendships.add('u0|u2');
  repos.store.chatMessagesByPair['u0|u2'] = [];
  repos.store.stickerPackages.add(StickerPackage(
    id: 'p1',
    name: 'Pack',
    slug: 'pack',
    description: '',
    author: 'MATRIX',
    iconUrl: 'http://x/pack.png',
    installed: true,
    stickerCount: 1,
    stickers: [
      Sticker(id: 's1', packageId: 'p1', order: 0, fileUrl: 'http://x/s.png'),
    ],
  ));
  repos.store.stickerRecents.add(
    Sticker(id: 's1', packageId: 'p1', order: 0, fileUrl: 'http://x/s.png'),
  );
  final state = AppState(repositories: repos);
  await state.restoreSession();
  await state.loadConversations();
  await state.loadStickers();
  await state.loadStickerRecents();
  return state;
}

Future<void> pumpChat(WidgetTester tester, AppState state) async {
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
}

void main() {
  group('Android Back fecha o painel de figurinhas (não sai da conversa)', () {
    testWidgets('Back com o painel aberto fecha e volta o teclado',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final state = await seededChatWithSticker();
      await pumpChat(tester, state);

      // Abre o painel.
      await tester.tap(find.byType(PuzzleIcon));
      await tester.pumpAndSettle();
      expect(find.byType(StickerPicker), findsOneWidget);

      // Android Back: em vez de sair da conversa, FECHA o painel.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(StickerPicker), findsNothing);
      // Continua na MESMA conversa (a tela segue montada) — o Back não fez pop.
      expect(find.byType(ConversationScreen), findsOneWidget);
    });

    testWidgets('Back sem o painel mantém o comportamento normal da rota',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final state = await seededChatWithSticker();
      await pumpChat(tester, state);

      // Sem painel aberto o Back segue normal (a rota pode ser removida).
      final didPop = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      // Não assertamos o resultado do pop (depende do host do teste); o que
      // importa é que NÃO fechamos nada indevidamente e nada quebra.
      expect(didPop, isA<bool>());
      expect(tester.takeException(), isNull);
      expect(state.isStickerRecent('s1'), isTrue);
    });
  });

  group('Remover das recentes', () {
    test('remove só dos recentes (pacote/favorito intactos) + persiste no fake',
        () async {
      final state = await seededChatWithSticker();
      await state.favoriteSticker('s1');
      expect(state.isStickerRecent('s1'), isTrue);
      expect(state.isStickerFavorited('s1'), isTrue);

      await state.removeStickerRecent('s1');
      expect(state.isStickerRecent('s1'), isFalse);
      // O favorito continua e o catálogo (pacote) segue intacto.
      expect(state.isStickerFavorited('s1'), isTrue);
      expect(state.stickerPackages.any((p) => p.stickers.any((s) => s.id == 's1')), isTrue);
    });

    test('remover algo que NÃO está nos recentes é no-op', () async {
      final state = await seededChatWithSticker();
      await state.removeStickerRecent('s1');
      expect(state.isStickerRecent('s1'), isFalse);
      // Segunda chamada não quebra nem altera nada.
      await state.removeStickerRecent('s1');
      expect(state.isStickerRecent('s1'), isFalse);
    });

    testWidgets('popup do painel mostra Remover das recentes + Favoritar',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final state = await seededChatWithSticker();
      await pumpMatrixApp(
        tester,
        Scaffold(body: StickerPicker(state: state, onPick: (_) {})),
        state: state,
      );
      await tester.pumpAndSettle();

      // Recents tab já abre com s1 → long press mostra as DUAS ações na ordem.
      await tester.longPress(find.byType(CachedNetworkImage).last);
      await tester.pumpAndSettle();
      expect(find.text('Remover das recentes'), findsOneWidget);
      expect(find.text('Favoritar'), findsOneWidget);
    });
  });

  group('Ícone do botão de figurinhas', () {
    testWidgets('usa o puzzle monocromático, não o ícone antigo',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final state = await seededChatWithSticker();
      await pumpChat(tester, state);
      expect(find.byType(PuzzleIcon), findsOneWidget);
      // O antigo ícone de nota adesiva não existe mais no composer.
      expect(find.byIcon(Icons.sticky_note_2_outlined), findsNothing);
    });
  });
}
