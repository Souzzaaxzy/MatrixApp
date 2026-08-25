import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/features/profile/edit_profile_screen.dart';
import 'package:matrix_app/features/profile/profile_screen.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('renders own profile: avatar, @nickname, edit button, FAB', (tester) async {
    await pumpMatrixApp(tester, const ProfileScreen());

    expect(find.text('PERFIL'), findsOneWidget);
    expect(find.text('Leonardo'), findsOneWidget);
    expect(find.textContaining('leonardo', findRichText: true), findsOneWidget);
    expect(find.text('PUBLICAÇÕES'), findsOneWidget);
    expect(find.text('EDITAR PERFIL'), findsOneWidget);
    // Own profile has the floating "+" and no friendship button.
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.text('SEGUIR'), findsNothing);
    expect(find.text('SOLICITADO'), findsNothing);
    expect(find.text('AMIGOS'), findsNothing);
  });

  testWidgets('other user profile: shows Seguir, no edit, no FAB', (tester) async {
    await pumpMatrixApp(tester, const ProfileScreen(username: 'joao'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('joao', findRichText: true), findsOneWidget);
    expect(find.text('SEGUIR'), findsOneWidget);
    expect(find.text('EDITAR PERFIL'), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    // Their posts keep rendering on their profile.
    expect(find.byIcon(Icons.favorite_rounded), findsWidgets);
  });

  testWidgets('tapping Seguir sends the request and shows Solicitado', (tester) async {
    await pumpMatrixApp(tester, const ProfileScreen(username: 'joao'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('SEGUIR'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('SOLICITADO'), findsOneWidget);
  });

  testWidgets('shows current user posts in the grid', (tester) async {
    await pumpMatrixApp(tester, const ProfileScreen());

    // The mock feed ships at least one post authored by leonardo (p1, p4).
    expect(find.byIcon(Icons.favorite_rounded), findsWidgets);
  });

  group('EditProfileScreen', () {
    testWidgets('loads current user data into fields', (tester) async {
      await pumpMatrixApp(tester, const EditProfileScreen());

      expect(find.text('EDITAR PERFIL'), findsOneWidget);
      // Name field is pre-filled with "Leonardo".
      expect(find.widgetWithText(TextField, 'Leonardo'), findsOneWidget);
    });

    testWidgets('validates required name and username', (tester) async {
      await pumpMatrixApp(tester, const EditProfileScreen());

      // Clear the name field.
      await tester.enterText(find.byType(TextField).at(0), '');
      // Clear the username field.
      await tester.enterText(find.byType(TextField).at(1), '');

      await tester.tap(find.text('SALVAR'));
      await tester.pump();

      expect(find.text('Informe seu nome'), findsOneWidget);
      expect(find.text('Username obrigatório'), findsOneWidget);
    });

    testWidgets('saves updated profile remotely', (tester) async {
      final state = await seededAppState();
      await pumpMatrixApp(tester, const EditProfileScreen(), state: state);

      await tester.enterText(find.byType(TextField).at(0), 'Neo');
      await tester.enterText(find.byType(TextField).at(2), 'The one');
      await tester.tap(find.text('SALVAR'));
      await tester.pumpAndSettle();

      expect(state.currentUser!.name, 'Neo');
      expect(state.currentUser!.bio, 'The one');
    });
  });
}
