import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/core/widgets/nickname_renderer.dart';
import 'package:matrix_app/data/api_config.dart';
import 'package:matrix_app/data/dtos/dtos.dart';
import 'package:matrix_app/features/customizations/customizations_screen.dart';
import 'package:matrix_app/features/customizations/widgets/profile_customization_preview.dart';
import 'package:matrix_app/models/cosmetic_item.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

/// Customizations screen (Personalizações) — category menu (🎨 Cor do
/// nickname + 🖼️ Molduras) opening in-place sections, a live preview and
/// ONE consolidated "SALVAR ALTERAÇÕES" operation. Nickname effects were
/// REMOVED: the nickname carries only a color.
const palette = [

  CosmeticItem(
    id: 'red',
    slot: CosmeticItem.nameColor,
    name: 'Vermelho',
    assetUrl: '#E53935',
    category: 'basic',
    sortOrder: 0,
  ),
  CosmeticItem(
    id: 'blue',
    slot: CosmeticItem.nameColor,
    name: 'Azul',
    assetUrl: '#1E88E5',
    category: 'basic',
    sortOrder: 4,
  ),
  CosmeticItem(
    id: 'matrix_blue',
    slot: CosmeticItem.nameColor,
    name: 'Azul Matrix',
    assetUrl: '#0066FF',
    category: 'special',
    sortOrder: 62,
  ),
];

Future<AppState> stateWithCatalog({
  Map<String, CosmeticItem> equipped = const {},
}) async {
  final repos = FakeRepositories(
    seedCatalog: palette,
    seedEquippedCosmetics: equipped,
  );
  final state = AppState(repositories: repos);
  addTearDown(state.dispose);
  await state.restoreSession();
  await state.loadFeed();
  return state;
}

/// The palette content may sit below the fold on the 800x600 test
/// surface, so scroll it into view before interacting.
Future<void> reveal(WidgetTester tester, Finder target) =>
    tester.scrollUntilVisible(
      target,
      300,
      scrollable: find.byType(Scrollable),
    );

/// The preview is at the very top; scroll back up before reading it.
Future<NicknameRenderer> previewRenderer(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byType(ProfileCustomizationPreview),
    -300,
    scrollable: find.byType(Scrollable),
  );
  await tester.pump();
  return tester.widget<NicknameRenderer>(
    find.descendant(
      of: find.byType(ProfileCustomizationPreview),
      matching: find.byType(NicknameRenderer),
    ),
  );
}


void main() {
  group('customization DTO parsing', () {
    test('parses the profile customization map; absent/invalid → empty', () {
      final map = parseCustomization({
        'AVATAR_FRAME': {
          'itemId': 'f1',
          'name': 'Cyber Blue',
          'assetUrl': 'frames/cyber',
          'rarity': 'RARE',
        },
      });
      expect(map['AVATAR_FRAME']!.name, 'Cyber Blue');
      expect(map['AVATAR_FRAME']!.rarity, 'RARE');
      expect(parseCustomization(null), isEmpty);
      expect(parseCustomization('junk'), isEmpty);
      expect(parseCustomization({'BADGE': 'not-a-map'}), isEmpty);
    });
  });

  group('CustomizationsScreen — category menu', () {
    testWidgets(
        'shows the preview and the category buttons; nothing opens until tapped',
        (tester) async {
      final state = await seededAppState();
      addTearDown(state.dispose);
      await pumpMatrixApp(tester, const CustomizationsScreen(), state: state);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('PERSONALIZAÇÕES'), findsOneWidget);
      expect(find.text('PRÉ-VISUALIZAÇÃO'), findsOneWidget);
      expect(find.byType(ProfileCustomizationPreview), findsOneWidget);
      expect(
          find.textContaining('leonardo', findRichText: true), findsWidgets);
      expect(find.text('@leonardo'), findsNothing);

      // The categories are buttons: palette stays closed until tapped.
      expect(find.text('Cor do nickname'), findsOneWidget);
      expect(find.text('Molduras'), findsOneWidget);
      expect(find.text('Padrão'), findsNothing);
      expect(find.text('CORES BÁSICAS'), findsNothing);
      // The removed category must not exist anywhere.
      expect(find.textContaining('Efeito'), findsNothing);
    });

    testWidgets('Cor do nickname opens the palette; Voltar returns to the menu',
        (tester) async {
      final state = await stateWithCatalog();
      await pumpMatrixApp(tester, const CustomizationsScreen(), state: state);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Cor do nickname'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('COR DO NICKNAME'), findsOneWidget);
      expect(find.text('Padrão'), findsOneWidget);
      // The menu is gone while the category is open.
      expect(find.text('Molduras'), findsNothing);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('PERSONALIZAÇÕES'), findsOneWidget);
      expect(find.text('Cor do nickname'), findsOneWidget);
      expect(find.text('Molduras'), findsOneWidget);
      expect(find.text('Padrão'), findsNothing);
    });

    testWidgets('Molduras opens its prepared section without breaking',
        (tester) async {
      final state = await seededAppState();
      addTearDown(state.dispose);
      await pumpMatrixApp(tester, const CustomizationsScreen(), state: state);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Molduras'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('MOLDURAS'), findsOneWidget);
      expect(find.textContaining('Em breve'), findsOneWidget);
      expect(find.text('Cor do nickname'), findsNothing);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('PERSONALIZAÇÕES'), findsOneWidget);
    });

    testWidgets('preview reflects cosmetics equipped server-side',
        (tester) async {
      final repos = FakeRepositories(seedEquippedCosmetics: {
        CosmeticItem.badge: const CosmeticItem(
          id: 'b1',
          slot: CosmeticItem.badge,
          name: 'Founder',
          rarity: 'LEGENDARY',
        ),
      });
      final state = AppState(repositories: repos);
      addTearDown(state.dispose);
      await state.restoreSession();
      await state.loadFeed();
      await pumpMatrixApp(tester, const CustomizationsScreen(), state: state);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('FOUNDER'), findsOneWidget);
    });
  });

    testWidgets('the palette lists the colors grouped by category',
        (tester) async {
      final state = await stateWithCatalog();
      await pumpMatrixApp(tester, const CustomizationsScreen(), state: state);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Cor do nickname'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Padrão'), findsOneWidget);
      expect(find.text('CORES BÁSICAS'), findsOneWidget);
      expect(find.text('TONS ESPECIAIS'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Vermelho'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
            (w) => w is Tooltip && w.message == 'Azul Matrix'),
        findsOneWidget,
      );
    });

    testWidgets(
        'selecting a color updates the preview immediately and '
        'SALVAR ALTERAÇÕES persists it in ONE operation', (tester) async {
      final state = await stateWithCatalog();
      await pumpMatrixApp(tester, const CustomizationsScreen(), state: state);
      await tester.pump(const Duration(milliseconds: 100));

      // Nothing pending yet → no save button.
      expect(find.text('SALVAR ALTERAÇÕES'), findsNothing);

      await tester.tap(find.text('Cor do nickname'));
      await tester.pump(const Duration(milliseconds: 100));

      final swatch = find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == 'Azul Matrix',
      );
      await reveal(tester, swatch);
      await tester.pump();
      await tester.tap(swatch);
      await tester.pump();

      // The preview carries the pending selection before saving.
      expect(find.text('SALVAR ALTERAÇÕES'), findsOneWidget);
      final preview = await previewRenderer(tester);
      expect(preview.nameColor, '#0066FF');

      // The server still holds the OLD state until the save.
      expect(state.myCosmetics[CosmeticItem.nameColor], isNull);

      await reveal(tester, find.text('SALVAR ALTERAÇÕES'));
      await tester.pump();
      await tester.tap(find.text('SALVAR ALTERAÇÕES'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Consolidated save confirmed: slot equipped and the global state of
      // the session user updated immediately (no restart / re-login).
      expect(state.myCosmetics[CosmeticItem.nameColor]?.id, 'matrix_blue');
      expect(state.currentUser?.nameColor, '#0066FF');
      expect(find.text('Personalizações salvas.'), findsOneWidget);
    });

    testWidgets('Padrão removes the color back to the default',
        (tester) async {
      final state = await stateWithCatalog(equipped: const {
        CosmeticItem.nameColor: CosmeticItem(
          id: 'matrix_blue',
          slot: CosmeticItem.nameColor,
          name: 'Azul Matrix',
          assetUrl: '#0066FF',
        ),
      });
      await state.loadMyCosmetics();
      expect(state.currentUser?.nameColor, '#0066FF');

      await pumpMatrixApp(tester, const CustomizationsScreen(), state: state);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Cor do nickname'));
      await tester.pump(const Duration(milliseconds: 100));

      await reveal(tester, find.text('Padrão'));
      await tester.pump();
      await tester.tap(find.text('Padrão'));
      await tester.pump();

      // Preview: color cleared (default).
      final preview = await previewRenderer(tester);
      expect(preview.nameColor, isNull);

      await reveal(tester, find.text('SALVAR ALTERAÇÕES'));
      await tester.pump();
      await tester.tap(find.text('SALVAR ALTERAÇÕES'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(state.myCosmetics.containsKey(CosmeticItem.nameColor), isFalse);
      expect(state.currentUser?.nameColor, isNull);
    });

    test('AppState syncs the color into the session user', () async {
      final state = await stateWithCatalog();
      await state.loadNameColorCatalog();
      expect(state.nameColorCatalog.length, 3);

      await state.saveCosmetics(nameColorId: 'red');
      expect(state.currentUser?.nameColor, '#E53935');

      await state.saveCosmetics(nameColorId: 'matrix_blue');
      expect(state.currentUser?.nameColor, '#0066FF');

      await state.saveCosmetics(nameColorId: null);
      expect(state.currentUser?.nameColor, isNull);
    });

    test('a fresh session restores the saved configuration (persistence)',
        () async {
      // Fechar e abrir: a NEW AppState over the SAME store must restore the
      // exact color saved before — nothing lives only in memory.
      final repos = FakeRepositories(seedCatalog: palette);
      final first = AppState(repositories: repos);
      await first.restoreSession();
      await first.loadFeed();
      await first.loadNameColorCatalog();
      await first.saveCosmetics(nameColorId: 'red');
      first.dispose();

      final second = AppState(repositories: repos);
      addTearDown(second.dispose);
      await second.restoreSession();
      await second.loadMyCosmetics();
      expect(second.myCosmetics[CosmeticItem.nameColor]?.id, 'red');
      expect(second.currentUser?.nameColor, '#E53935');
    });

    test('the server-owned catalog rejects unknown ids', () async {
      final state = await stateWithCatalog();
      expect(
        () => state.saveCosmetics(nameColorId: '#123456'),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => state.saveCosmetics(nameColorId: 'text-shadow: 0 0 50px red'),
        throwsA(isA<ApiException>()),
      );
    });

}
