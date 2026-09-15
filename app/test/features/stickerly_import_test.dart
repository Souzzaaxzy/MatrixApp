import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/features/chat/chat_navigation.dart';
import 'package:matrix_app/features/chat/conversation_screen.dart';
import 'package:matrix_app/features/chat/sticker_picker.dart';
import 'package:matrix_app/features/chat/stickerly_import_sheet.dart';
import 'package:matrix_app/features/chat/sticker_panel.dart';
import 'package:matrix_app/models/sticker.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

Future<AppState> seededState() async {
  final repos = FakeRepositories();
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
      Sticker(
        id: 's1',
        packageId: 'p1',
        order: 0,
        fileUrl: 'http://x/s.png',
      ),
    ],
  ));
  final state = AppState(repositories: repos);
  await state.restoreSession();
  await state.loadStickers();
  return state;
}

void main() {
  group('Sticker.ly — AppState', () {
    test('preview devolve os dados do pacote sem importar', () async {
      final state = await seededState();
      final preview = await state.previewStickerlyPack('QSXLKY');
      expect(preview.code, 'QSXLKY');
      expect(preview.name, isNotEmpty);
      expect(preview.stickerCount, greaterThan(0));
      expect(preview.alreadyInstalled, isFalse);
      // Nada foi adicionado à coleção ainda.
      expect(
        state.stickerPackages.any((p) => p.id.startsWith('ly_')),
        isFalse,
      );
    });

    test('código inexistente vira erro amigável', () async {
      final state = await seededState();
      expect(
        () => state.previewStickerlyPack('MISSING'),
        throwsA(isA<Exception>()),
      );
    });

    test('importa o pacote e não duplica ao reimportar', () async {
      final state = await seededState();
      final first = await state.importStickerlyPack('QSXLKY');
      expect(first.created, 1);
      expect(first.package, isNotNull);
      expect(
        state.stickerPackages.any((p) => p.id.startsWith('ly_')),
        isTrue,
      );
      final second = await state.importStickerlyPack('QSXLKY');
      expect(second.already, isTrue);
      expect(second.created, 0);
    });
  });

  group('StickerPicker', () {
    testWidgets('mostra o botão Adicionar e a grade compacta',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final state = await seededState();
      await pumpMatrixApp(
        tester,
        Scaffold(
          body: StickerPicker(state: state, onPick: (_) {}),
        ),
        state: state,
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Adicionar pacote (Sticker.ly)'), findsOneWidget);
      expect(find.text('RECENTES'), findsOneWidget);
      expect(find.text('FAVORITOS'), findsOneWidget);
    });

    testWidgets('tocar numa figurinha dispara onPick', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      // Recents seeded via the fake repo → the initial tab has a sticker.
      final repos = FakeRepositories();
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
      await state.loadStickers();
      await state.loadStickerRecents();

      String? picked;
      await pumpMatrixApp(
        tester,
        Scaffold(
          body: StickerPicker(state: state, onPick: (s) => picked = s.id),
        ),
        state: state,
      );
      await tester.pumpAndSettle();

      // A grade de Recentes tem 1 figurinha; tocar dispara onPick.
      await tester.tap(find.byType(CachedNetworkImage).last);
      await tester.pump();
      expect(picked, 's1');
    });

    testWidgets('não estoura o layout em tela estreita (360dp)', (tester) async {
      tester.view.physicalSize = const Size(720, 1280);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final state = await seededState();
      await pumpMatrixApp(
        tester,
        Scaffold(
          body: StickerPicker(state: state, onPick: (_) {}),
        ),
        state: state,
      );
      await tester.pumpAndSettle();

      // O header (abas + pacotes + Adicionar) precisa caber; Flutter lança
      // exceção de overflow se não couber e o teste falharia aqui.
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Adicionar pacote (Sticker.ly)'), findsOneWidget);
    });

    testWidgets('abre o modal Adicionar pacote', (tester) async {
      addTearDown(tester.view.reset);

      final state = await seededState();
      await pumpMatrixApp(
        tester,
        Scaffold(
          body: StickerPicker(state: state, onPick: (_) {}),
        ),
        state: state,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Adicionar pacote (Sticker.ly)'));
      await tester.pumpAndSettle();
      expect(find.byType(StickerlyImportSheet), findsOneWidget);
      expect(find.text('BUSCAR'), findsOneWidget);
      expect(find.text('CANCELAR'), findsOneWidget);
    });
  });

  group('StickerlyImportSheet — fluxo', () {
    testWidgets('ID inválido/vazio mostra erro em português', (tester) async {
      final state = await seededState();
      await pumpMatrixApp(
        tester,
        Scaffold(body: StickerlyImportSheet(state: state)),
        state: state,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('BUSCAR'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Digite o código'),
        findsOneWidget,
      );
    });

    testWidgets('código válido mostra prévia e importa ao confirmar',
        (tester) async {
      final state = await seededState();
      await pumpMatrixApp(
        tester,
        Scaffold(body: StickerlyImportSheet(state: state)),
        state: state,
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'QSXLKY');
      await tester.tap(find.text('BUSCAR'));
      await tester.pumpAndSettle();

      // Prévia: nome do pacote + botão de confirmação.
      expect(find.text('Pacote Sticker.ly'), findsOneWidget);
      expect(find.text('ADICIONAR AO MATRIX'), findsOneWidget);

      await tester.tap(find.text('ADICIONAR AO MATRIX'));
      await tester.pumpAndSettle();

      expect(
        state.stickerPackages.any((p) => p.id.startsWith('ly_')),
        isTrue,
      );
      // O pacote importado passa a aparecer na coleção do painel.
      expect(
        state.installedStickerPackages.any((p) => p.id.startsWith('ly_')),
        isTrue,
      );
    });
  });

  group('AnimatedStickerPanel', () {
    testWidgets('monta o filho só quando visível', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedStickerPanel(
              visible: false,
              child: Text('painel'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('painel'), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedStickerPanel(
              visible: true,
              child: Text('painel'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('painel'), findsOneWidget);
    });
  });

  group('Conversa — integração do painel', () {
    testWidgets('abrir o painel não estoura e tocar no campo fecha',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

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
      final state = AppState(repositories: repos);
      await state.restoreSession();
      await state.loadConversations();
      await state.loadStickers();

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

      // Abre o painel pelo ícone de figurinhas do composer.
      await tester.tap(find.byIcon(Icons.sticky_note_2_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(StickerPicker), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Tocar no campo fecha o painel (comportamento preservado).
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      expect(find.byType(StickerPicker), findsNothing);
    });
  });
}
