import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/data/dtos/dtos.dart';
import 'package:matrix_app/features/customizations/customizations_screen.dart';
import 'package:matrix_app/features/customizations/widgets/profile_customization_preview.dart';
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
      expect(find.text('Moldura'), findsOneWidget);
      expect(find.text('Nome'), findsOneWidget);
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
}
