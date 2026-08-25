import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/data/dtos/dtos.dart';
import 'package:matrix_app/features/customizations/customizations_screen.dart';
import 'package:matrix_app/features/customizations/widgets/profile_customization_preview.dart';
import 'package:flutter/material.dart';
import 'package:matrix_app/core/widgets/nickname_renderer.dart';
import 'package:matrix_app/data/api_config.dart';
import 'package:matrix_app/models/cosmetic_item.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

/// Customizations screen (Personalizações) — 🎨 Cor do nickname +
/// ✨ Efeito do nickname as two independent categories with a live preview
/// and ONE consolidated "SALVAR ALTERAÇÕES" operation.
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

    test('parses the embedded nameEffect payload (id + config)', () {
      final effect = parseNameEffect({
        'id': 'glow',
        'name': 'Glow',
        'config': {'animation': 'glow', 'intensity': 0.6, 'speed': 1.0},
      });
      expect(effect, isNotNull);
      expect(effect!.id, 'glow');
      expect(effect.intensity, 0.6);
      expect(parseNameEffect(null), isNull);
      expect(parseNameEffect({'name': 'no-id'}), isNull);
      expect(parseNameEffect('text-shadow: 0 0 50px red'), isNull);
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
      expect(find.text('Leonardo'), findsWidgets);
      expect(find.text('@leonardo'), findsOneWidget);
      expect(find.text('Cor do nickname'), findsOneWidget);
      expect(find.text('Efeito do nickname'), findsOneWidget);

      // The placeholder sections sit below the fold on the test surface.
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pump();
      expect(find.text('Moldura'), findsOneWidget);
      expect(find.text('Badge'), findsOneWidget);
      expect(find.text('Em breve'), findsNWidgets(2));
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

  group('nickname cosmetics (color + effect)', () {
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
      CosmeticItem(
        id: 'glow',
        slot: CosmeticItem.nameEffect,
        name: 'Glow',
        category: 'glow',
        sortOrder: 100,
        config: {'animation': 'glow', 'intensity': 0.6, 'speed': 1.0},
      ),
      CosmeticItem(
        id: 'glitch',
        slot: CosmeticItem.nameEffect,
        name: 'Glitch',
        category: 'glitch',
        sortOrder: 200,
        config: {'animation': 'glitch', 'intensity': 0.8, 'speed': 1.5},
      ),
      CosmeticItem(
        id: 'fire',
        slot: CosmeticItem.nameEffect,
        name: 'Fire',
        category: 'elemental',
        sortOrder: 300,
        config: {
          'animation': 'fire',
          'intensity': 0.9,
          'speed': 1.2,
          'particles': true,
          'colors': ['#FF5722', '#FFC107'],
        },
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

    /// The effect section sits below the fold on the 800x600 test surface,
    /// so scroll it into view before interacting.
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

    testWidgets('renders colors and effects grouped by category + Nenhum',
        (tester) async {
      final state = await stateWithCatalog();
      await pumpMatrixApp(tester, const CustomizationsScreen(), state: state);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Cor do nickname'), findsOneWidget);
      expect(find.text('Padrão'), findsOneWidget);

      await reveal(tester, find.text('Efeito do nickname'));
      await tester.pump();
      expect(find.text('Nenhum'), findsOneWidget);
      expect(find.text('CORES BÁSICAS'), findsOneWidget);
      expect(find.text('✨ EFEITOS DE BRILHO'), findsOneWidget);
      // Effect tiles render a live preview of their own name (glitch
      // renders RGB ghost layers, hence findsWidgets).
      expect(find.text('Glow'), findsOneWidget);
      expect(find.text('Glitch'), findsWidgets);
      expect(find.text('Fire'), findsOneWidget);
    });

    testWidgets(
        'selecting color + effect updates the preview immediately and '
        'SALVAR ALTERAÇÕES persists both in ONE operation', (tester) async {
      final state = await stateWithCatalog();
      await pumpMatrixApp(tester, const CustomizationsScreen(), state: state);
      await tester.pump(const Duration(milliseconds: 100));

      // Nothing pending yet → no save button.
      expect(find.text('SALVAR ALTERAÇÕES'), findsNothing);

      final swatch = find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == 'Azul Matrix',
      );
      await reveal(tester, swatch);
      await tester.pump();
      await tester.tap(swatch);
      await tester.pump();

      final effectChip = find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == 'Glow',
      );
      await reveal(tester, effectChip);
      await tester.pump();
      await tester.tap(effectChip);
      await tester.pump();

      // The preview carries BOTH pending selections immediately (color +
      // effect are independent), before anything hits the server.
      expect(find.text('SALVAR ALTERAÇÕES'), findsOneWidget);
      final preview = await previewRenderer(tester);
      expect(preview.nameColor, '#0066FF');
      expect(preview.effect?.id, 'glow');

      // The server still holds the OLD state until the save.
      expect(state.myCosmetics[CosmeticItem.nameColor], isNull);
      expect(state.myCosmetics[CosmeticItem.nameEffect], isNull);

      await reveal(tester, find.text('SALVAR ALTERAÇÕES'));
      await tester.pump();
      await tester.tap(find.text('SALVAR ALTERAÇÕES'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Consolidated save confirmed: both slots equipped, global state of
      // the session user updated immediately (no restart / re-login).
      expect(state.myCosmetics[CosmeticItem.nameColor]?.id, 'matrix_blue');
      expect(state.myCosmetics[CosmeticItem.nameEffect]?.id, 'glow');
      expect(state.currentUser?.nameColor, '#0066FF');
      expect(state.currentUser?.nameEffect?.id, 'glow');
      expect(find.text('Personalizações salvas.'), findsOneWidget);
    });

    testWidgets('Nenhum removes only the effect; the color keeps working',
        (tester) async {
      final state = await stateWithCatalog(equipped: const {
        CosmeticItem.nameColor: CosmeticItem(
          id: 'matrix_blue',
          slot: CosmeticItem.nameColor,
          name: 'Azul Matrix',
          assetUrl: '#0066FF',
        ),
        CosmeticItem.nameEffect: CosmeticItem(
          id: 'glitch',
          slot: CosmeticItem.nameEffect,
          name: 'Glitch',
          config: {'animation': 'glitch', 'intensity': 0.8},
        ),
      });
      await state.loadMyCosmetics();
      expect(state.currentUser?.nameColor, '#0066FF');
      expect(state.currentUser?.nameEffect?.id, 'glitch');

      await pumpMatrixApp(tester, const CustomizationsScreen(), state: state);
      await tester.pump(const Duration(milliseconds: 100));

      await reveal(tester, find.text('Nenhum'));
      await tester.pump();
      await tester.tap(find.text('Nenhum'));
      await tester.pump();

      // Preview: color stays, effect cleared.
      final preview = await previewRenderer(tester);
      expect(preview.nameColor, '#0066FF');
      expect(preview.effect, isNull);

      await reveal(tester, find.text('SALVAR ALTERAÇÕES'));
      await tester.pump();
      await tester.tap(find.text('SALVAR ALTERAÇÕES'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(state.myCosmetics.containsKey(CosmeticItem.nameEffect), isFalse);
      expect(state.myCosmetics[CosmeticItem.nameColor]?.id, 'matrix_blue');
      expect(state.currentUser?.nameColor, '#0066FF');
      expect(state.currentUser?.nameEffect, isNull);
    });

    test('AppState syncs color and effect independently into the session user',
        () async {
      final state = await stateWithCatalog();
      await state.loadNameColorCatalog();
      await state.loadNameEffectCatalog();
      expect(state.nameColorCatalog.length, 3);
      expect(state.nameEffectCatalog.length, 3);

      // Any color combines with any effect — no restrictions.
      await state.saveCosmetics(nameColorId: 'red', nameEffectId: 'fire');
      expect(state.currentUser?.nameColor, '#E53935');
      expect(state.currentUser?.nameEffect?.id, 'fire');

      await state.saveCosmetics(nameColorId: 'matrix_blue', nameEffectId: 'glitch');
      expect(state.currentUser?.nameColor, '#0066FF');
      expect(state.currentUser?.nameEffect?.id, 'glitch');

      // Only the effect changes; the color is untouched.
      await state.saveCosmetics(nameColorId: 'matrix_blue', nameEffectId: null);
      expect(state.currentUser?.nameColor, '#0066FF');
      expect(state.currentUser?.nameEffect, isNull);
    });

    test('a fresh session restores the saved configuration (persistence)',
        () async {
      // Fechar e abrir: a NEW AppState over the SAME store must restore the
      // exact color + effect saved before — nothing lives only in memory.
      final repos = FakeRepositories(seedCatalog: palette);
      final first = AppState(repositories: repos);
      await first.restoreSession();
      await first.loadFeed();
      await first.loadNameColorCatalog();
      await first.loadNameEffectCatalog();
      await first.saveCosmetics(nameColorId: 'red', nameEffectId: 'glow');
      first.dispose();

      final second = AppState(repositories: repos);
      addTearDown(second.dispose);
      await second.restoreSession();
      await second.loadMyCosmetics();
      expect(second.myCosmetics[CosmeticItem.nameColor]?.id, 'red');
      expect(second.myCosmetics[CosmeticItem.nameEffect]?.id, 'glow');
      expect(second.currentUser?.nameColor, '#E53935');
      expect(second.currentUser?.nameEffect?.id, 'glow');
    });

    test('the server-owned catalog rejects unknown ids (color or effect)',
        () async {
      final state = await stateWithCatalog();
      expect(
        () => state.saveCosmetics(
          nameColorId: '#123456',
          nameEffectId: 'glow',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => state.saveCosmetics(
          nameColorId: 'matrix_blue',
          nameEffectId: 'text-shadow: 0 0 50px red',
        ),
        throwsA(isA<ApiException>()),
      );
      // A color id is not a valid effect and vice-versa.
      expect(
        () => state.saveCosmetics(
          nameColorId: 'glow',
          nameEffectId: 'matrix_blue',
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
