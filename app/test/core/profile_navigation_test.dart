import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/utils/profile_navigation.dart';
import 'package:matrix_app/features/profile/profile_screen.dart';
import 'package:matrix_app/models/matrix_user.dart';

import '../helpers/test_app.dart';

/// A container that renders a real [ProfileScreen] so it registers its
/// resolved user id in the navigation tracking, and exposes a tap target to
/// drive [openUserProfile] / [openProfileById].
class ProfileProbe extends StatelessWidget {
  const ProfileProbe({super.key, this.nickname});
  final String? nickname;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ProfileScreen(nickname: nickname),
    );
  }
}

void main() {
  final userB = MatrixUser(id: 'u2', nickname: 'joao', bio: '');

  setUp(() => resetProfileTracking());

  testWidgets('openUserProfile pushes the profile route by nickname',
      (tester) async {
    await pumpMatrixApp(tester, const Scaffold(body: SizedBox()));

    openUserProfile(tester.element(find.byType(Scaffold)), userB);
    await tester.pumpAndSettle();

    expect(find.text('PERFIL'), findsOneWidget);
    expect(find.textContaining('joao', findRichText: true), findsOneWidget);
  });

  testWidgets('openProfileById is a no-op when that profile is already open',
      (tester) async {
    // Open joao's (u2) profile first — registers its real id in the stack.
    await pumpMatrixApp(tester, const ProfileProbe(nickname: 'joao'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('joao', findRichText: true), findsOneWidget);

    // Attempt to open the SAME user again (same real id) — must be a no-op.
    openProfileById(
      tester.element(find.byType(ProfileScreen)),
      id: 'u2',
      nickname: 'joao',
    );
    await tester.pumpAndSettle();

    // Still exactly one profile route, still joao — nothing duplicated.
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.textContaining('joao', findRichText: true), findsOneWidget);
    expect(find.textContaining('beta', findRichText: true), findsNothing);
  });

  testWidgets('profile closes its slot when popped so it can be reopened',
      (tester) async {
    await pumpMatrixApp(tester, const Scaffold(body: SizedBox()));

    // Open joao's profile, then pop it.
    openProfileById(
      tester.element(find.byType(Scaffold)),
      id: 'u2',
      nickname: 'joao',
    );
    await tester.pumpAndSettle();
    expect(find.text('PERFIL'), findsOneWidget);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsNothing);

    // Now the same user can be reopened.
    openProfileById(
      tester.element(find.byType(Scaffold)),
      id: 'u2',
      nickname: 'joao',
    );
    await tester.pumpAndSettle();
    expect(find.text('PERFIL'), findsOneWidget);
    expect(find.textContaining('joao', findRichText: true), findsOneWidget);
  });
}