import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/utils/profile_navigation.dart';
import 'package:matrix_app/core/widgets/user_avatar.dart';
import 'package:matrix_app/features/feed/feed_screen.dart';
import 'package:matrix_app/features/profile/profile_screen.dart';

import '../helpers/test_app.dart';

void main() {
  setUp(() => resetProfileTracking());

  testWidgets('tapping the post author photo opens THAT author profile',
      (tester) async {
    await pumpMatrixApp(tester, const FeedScreen());
    await tester.pumpAndSettle();

    // p2 is authored by joao (another user), the SECOND card in the
    // chronological feed (p1 = leonardo, p2 = joao). Tap joao's avatar.
    expect(find.textContaining('joao', findRichText: true), findsWidgets);
    await tester.tap(find.byType(UserAvatar).at(1));
    await tester.pumpAndSettle();

    // The opened profile is JOÃO's, not the session user (leonardo)'s.
    expect(find.byType(ProfileScreen), findsWidgets);
    expect(find.text('PERFIL'), findsWidgets);
    expect(find.textContaining('joao', findRichText: true), findsWidgets);
  });

  testWidgets('tapping the post author nickname opens THAT author profile',
      (tester) async {
    await pumpMatrixApp(tester, const FeedScreen());
    await tester.pumpAndSettle();

    // Tap joao's nickname within his post card.
    await tester.tap(find.textContaining('joao', findRichText: true).first);
    await tester.pumpAndSettle();

    expect(find.byType(ProfileScreen), findsWidgets);
    expect(find.textContaining('joao', findRichText: true), findsWidgets);
  });
}