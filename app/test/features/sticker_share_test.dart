import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/core/utils/sticker_import_validator.dart';
import 'package:matrix_app/features/chat/chat_navigation.dart';
import 'package:matrix_app/features/chat/conversation_screen.dart';
import 'package:matrix_app/features/chat/sticker_picker.dart';
import 'package:matrix_app/models/sticker.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // PNG real (fixture) — leitura do assets de frames para decodificar bem.
  Uint8List fixturePng() {
    final f = File('assets/frames/cometa.png');
    return f.readAsBytesSync();
  }

  group('StickerImportValidator', () {
    test('aceita PNG e calcula SHA-256', () async {
      final dir = await Directory.systemTemp.createTemp('sticker_test');
      final file = File('${dir.path}/sticker.png')..writeAsBytesSync(fixturePng());
      final valid = await StickerImportValidator.validate(file);
      expect(valid, isNotNull);
      expect(valid!.sha256, hasLength(64));
      dir.deleteSync(recursive: true);
    });

    test('rejeita bytes não-imagem', () async {
      final dir = await Directory.systemTemp.createTemp('sticker_bad');
      final file = File('${dir.path}/fake.png')
        ..writeAsBytesSync(Uint8List.fromList(List.filled(20, 0x42)));
      final reasons = <String, String>{};
      final valid = await StickerImportValidator.validate(
        file,
        invalidReasons: reasons,
      );
      expect(valid, isNull);
      expect(reasons, isNotEmpty);
      dir.deleteSync(recursive: true);
    });
  });

  group('importSharedStickers (AppState)', () {
    test('importa lote e cria paquete no fake', () async {
      final repos = FakeRepositories();
      final state = AppState(repositories: repos);
      await state.restoreSession();

      final dir = await Directory.systemTemp.createTemp('sticker_import');
      final file = File('${dir.path}/a.png')..writeAsBytesSync(fixturePng());
      final valid = await StickerImportValidator.validate(file);
      expect(valid, isNotNull);

      final result = await state.importSharedStickers(
        name: 'Compartilhados',
        stickers: [valid!],
      );
      expect(result.created, 1);
      expect(result.skipped, 0);
      expect(
        repos.store.stickerPackages.any((p) => p.name == 'Compartilhados'),
        isTrue,
      );
      dir.deleteSync(recursive: true);
    });

    test('dedupe por hash: reenvío no duplica', () async {
      final repos = FakeRepositories();
      final state = AppState(repositories: repos);
      await state.restoreSession();

      final dir = await Directory.systemTemp.createTemp('sticker_dedupe');
      final file = File('${dir.path}/b.png')..writeAsBytesSync(fixturePng());
      final valid = await StickerImportValidator.validate(file);

      final first = await state.importSharedStickers(
        name: 'Pack',
        stickers: [valid!],
      );
      expect(first.created, 1);
      final second = await state.importSharedStickers(
        name: 'Pack',
        stickers: [valid],
      );
      expect(second.created, 0);
      expect(second.skipped, 1);
      dir.deleteSync(recursive: true);
    });
  });

  group('Composer: fechamento do painel de stickers', () {
    Future<AppState> seededChat() async {
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
          Sticker(
            id: 's1',
            packageId: 'p1',
            order: 0,
            fileUrl: 'http://x/s.png',
            width: 256,
            height: 256,
          ),
        ],
      ));
      final state = AppState(repositories: repos);
      await state.restoreSession();
      await state.loadConversations();
      await state.loadStickers();
      return state;
    }

    testWidgets('tocar no campo fecha o painel e devolve o foco', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final state = await seededChat();
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

      // Abre o painel de stickers pelo botão (ícone real, não emoji).
      final stickerBtn = find.byIcon(Icons.sticky_note_2_outlined);
      expect(stickerBtn, findsOneWidget);
      await tester.tap(stickerBtn);
      await tester.pumpAndSettle();
      expect(find.byType(StickerPicker), findsOneWidget);

      // Toca no campo de mensagem → painel fecha.
      final field = find.byType(TextField).first;
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(find.byType(StickerPicker), findsNothing);
    });
  });
}