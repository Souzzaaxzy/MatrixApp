import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/features/home/home_screen.dart';
import 'package:matrix_app/features/profile/edit_profile_screen.dart';
import 'package:matrix_app/features/profile/friends_sheet.dart';
import 'package:matrix_app/features/profile/profile_screen.dart';

import '../helpers/fake_repositories.dart';
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
    expect(find.text('ADICIONAR'), findsNothing);
    expect(find.text('SOLICITADO'), findsNothing);
    expect(find.text('AMIGOS'), findsNothing);
  });

  testWidgets('other user profile: shows Adicionar, no edit, no FAB', (tester) async {
    await pumpMatrixApp(tester, const ProfileScreen(username: 'joao'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('joao', findRichText: true), findsOneWidget);
    expect(find.text('ADICIONAR'), findsOneWidget);
    expect(find.text('EDITAR PERFIL'), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    // Their posts keep rendering on their profile.
    expect(find.byIcon(Icons.favorite_rounded), findsWidgets);
  });

  testWidgets('tapping Adicionar sends the request and shows Solicitado', (tester) async {
    await pumpMatrixApp(tester, const ProfileScreen(username: 'joao'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('ADICIONAR'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('SOLICITADO'), findsOneWidget);
  });

  testWidgets('shows current user posts in the grid', (tester) async {
    await pumpMatrixApp(tester, const ProfileScreen());

    // The mock feed ships at least one post authored by leonardo (p1, p4).
    expect(find.byIcon(Icons.favorite_rounded), findsWidgets);
  });

  group('profile counters and friends sheet', () {
    testWidgets('shows the real Amigos/Posts counters from the server',
        (tester) async {
      final repos = FakeRepositories();
      repos.store.friendships.add('u0|u2');
      final state = AppState(repositories: repos);
      await pumpMatrixApp(tester, const ProfileScreen(), state: state);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Amigos'), findsOneWidget);
      expect(find.text('Posts'), findsOneWidget);
      // Leonardo: 1 accepted friendship + 1 owned post — both counters.
      expect(find.text('1'), findsNWidgets(2));
    });

    testWidgets('viewed profile shows THAT user counters, not the session',
        (tester) async {
      await pumpMatrixApp(tester, const ProfileScreen(username: 'joao'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Amigos'), findsOneWidget);
      expect(find.text('Posts'), findsOneWidget);
      // João has exactly 1 post (0 friends) — his counters, not the
      // session user's.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets(
        'Amigos opens the friends bottom sheet with the real list, and the '
        'item opens that friend profile', (tester) async {
      final repos = FakeRepositories();
      repos.store.friendships.add('u0|u2');
      final state = AppState(repositories: repos);
      await pumpMatrixApp(tester, const ProfileScreen(), state: state);
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('Amigos'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(FriendsSheet), findsOneWidget);
      expect(find.text('AMIGOS DE @LEONARDO'), findsOneWidget);
      expect(find.text('@joao'), findsOneWidget);

      await tester.tap(find.text('@joao'));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 800));

      // The friend's profile opened — friendship button reflects Friends.
      expect(find.text('AMIGOS'), findsOneWidget);

      // Going back must restore the own profile — never the friend data.
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.textContaining('leonardo', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('joao', findRichText: true), findsNothing);
    });
  });

  group('profile navigation bug regression', () {
    testWidgets(
        'search → viewed profile → back → own profile shows the session '
        'user, never the viewed user', (tester) async {
      await pumpMatrixApp(tester, const HomeScreen());
      await tester.pump(const Duration(milliseconds: 400));

      // Buscar tab, query for another user.
      await tester.tap(find.text('Buscar'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), 'joao');
      await tester.pump(const Duration(milliseconds: 400));

      // Open the viewed profile (loaded in its own keyed slot).
      await tester.tap(find.text('@joao'));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('ADICIONAR'), findsOneWidget);

      // Back to the shell, then open the own profile tab.
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Perfil'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // The session user's profile renders immediately — no residue of the
      // previously viewed profile, no need for a manual refresh.
      expect(
        find.textContaining('leonardo', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('joao', findRichText: true), findsNothing);
    });
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
      expect(find.text('Nickname obrigatório'), findsOneWidget);
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
