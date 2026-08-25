import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/data/dtos/dtos.dart';
import 'package:matrix_app/features/customizations/customizations_screen.dart';
import 'package:matrix_app/features/customizations/widgets/profile_customization_preview.dart';
import 'package:flutter/material.dart';
import 'package:matrix_app/core/widgets/styled_username.dart';
import 'package:matrix_app/data/api_config.dart';
import 'package:matrix_app/models/cosmetic_item.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

/// Customizations screen (Personalizações) — infrastructure phase: preview
/// + slot sections live, real cosmetic catalog ships next update.
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

  group('CustomizationsScreen', () {
    testWidgets('renders the live preview and the placeholder sections',
        (tester) async {
      final state = await seededAppState();
      addTearDown(state.dispose);
      await pumpMatrixApp(tester, const CustomizationsScreen(), state: state);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('PERSONALIZAÇÕES'), findsOneWidget);
      expect(find.text('PRÉ-VISUALIZAÇÃO'), findsOneWidget);
      expect(find.byType(ProfileCustomizationPreview), findsOneWidget);
      expect(find.text('Leonardo'), findsOneWidget);
      expect(find.text('@leonardo'), findsOneWidget);
      expect(find.text('Cor do nickname'), findsOneWidget);

      // The placeholder sections sit below the fold on the test surface.
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pump();
      expect(find.text('Moldura'), findsOneWidget);
      expect(find.text('Efeito de nome'), findsOneWidget);
      expect(find.text('Badge'), findsOneWidget);
      expect(find.text('Em breve'), findsNWidgets(3));
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

  group('nickname colors', () {
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

    Future<AppState> stateWithPalette({
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

    testWidgets('renders the server palette grouped by category + Padrão',
        (tester) async {
      final state = await stateWithPalette();
      await pumpMatrixApp(tester, const CustomizationsScreen(), state: state);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Cor do nickname'), findsOneWidget);
      expect(find.text('Padrão'), findsOneWidget);
      expect(find.text('CORES BÁSICAS'), findsOneWidget);
      expect(find.text('TONS ESPECIAIS'), findsOneWidget);
      // The app never hardcodes colors: names come from the catalog.
      expect(find.byType(Tooltip), findsNWidgets(3));
    });

    testWidgets(
        'selecting a color updates the preview immediately and saving '
        'persists it through AppState', (tester) async {
      final state = await stateWithPalette();
      await pumpMatrixApp(tester, const CustomizationsScreen(), state: state);
      await tester.pump(const Duration(milliseconds: 100));

      // Nothing selected yet → no save button.
      expect(find.text('SALVAR'), findsNothing);

      final swatch = find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == 'Azul Matrix',
      );
      await tester.ensureVisible(swatch);
      await tester.pump();
      await tester.tap(swatch);
      await tester.pump();

      // Save button appears (MatrixButton uppercases its label) and the
      // preview carries the selected hex immediately.
      expect(find.text('SALVAR'), findsOneWidget);
      final preview = tester.widget<StyledUsername>(
        find.descendant(
          of: find.byType(ProfileCustomizationPreview),
          matching: find.byType(StyledUsername),
        ),
      );
      expect(preview.nameColor, '#0066FF');

      await tester.ensureVisible(find.text('SALVAR'));
      await tester.pump();
      await tester.tap(find.text('SALVAR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Server-validated state now holds the color and the GLOBAL session
      // user reflects it immediately (no restart / re-login).
      expect(state.myCosmetics[CosmeticItem.nameColor]?.id, 'matrix_blue');
      expect(state.currentUser?.nameColor, '#0066FF');
      expect(find.text('Cor do nickname atualizada.'), findsOneWidget);
    });

    testWidgets('Padrão removes the customization (nameColor = null)',
        (tester) async {
      final state = await stateWithPalette(equipped: const {
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

      await tester.ensureVisible(find.text('Padrão'));
      await tester.pump();
      await tester.tap(find.text('Padrão'));
      await tester.pump();
      await tester.ensureVisible(find.text('SALVAR'));
      await tester.pump();
      await tester.tap(find.text('SALVAR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(state.myCosmetics.containsKey(CosmeticItem.nameColor), isFalse);
      expect(state.currentUser?.nameColor, isNull);
    });

    test('AppState syncs the equipped color into the session user', () async {
      final state = await stateWithPalette();
      await state.loadNameColorCatalog();
      expect(state.nameColorCatalog.length, 3);

      await state.equipCosmetic('red');
      expect(state.currentUser?.nameColor, '#E53935');

      await state.equipCosmetic('matrix_blue');
      expect(state.currentUser?.nameColor, '#0066FF');

      await state.unequipCosmetic(CosmeticItem.nameColor);
      expect(state.currentUser?.nameColor, isNull);
    });

    test('the server-owned catalog rejects unknown color ids', () async {
      final state = await stateWithPalette();
      expect(
        () => state.equipCosmetic('#123456'),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
