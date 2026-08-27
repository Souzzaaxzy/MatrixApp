import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/core/utils/profile_navigation.dart';
import 'package:matrix_app/core/widgets/matrix_card.dart';
import 'package:matrix_app/core/widgets/user_avatar.dart';
import 'package:matrix_app/features/home/home_screen.dart';
import 'package:matrix_app/features/profile/edit_profile_screen.dart';
import 'package:matrix_app/features/profile/friends_sheet.dart';
import 'package:matrix_app/features/profile/profile_screen.dart';
import 'package:matrix_app/models/post.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

void main() {
      testWidgets('renders own profile: avatar, nickname, edit button, FAB', (tester) async {
    await pumpMatrixApp(tester, const ProfileScreen());

    expect(find.text('PERFIL'), findsOneWidget);
    expect(find.textContaining('leonardo', findRichText: true), findsOneWidget);
    expect(find.text('PUBLICAÇÕES'), findsOneWidget);
    expect(find.text('EDITAR PERFIL'), findsOneWidget);
    // Own profile has the floating "+" and no friendship button.
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.text('SOLICITAR'), findsNothing);
    expect(find.text('SOLICITADO'), findsNothing);
    expect(find.text('AMIGOS'), findsNothing);
  });

  testWidgets('other user profile: shows Solicitado, no edit, no FAB', (tester) async {
    await pumpMatrixApp(tester, const ProfileScreen(nickname: 'joao'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('joao', findRichText: true), findsOneWidget);
    expect(find.text('SOLICITAR'), findsOneWidget);
    expect(find.text('EDITAR PERFIL'), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    // Their posts keep rendering on their profile — with the NEUTRAL
    // counter icon, never a filled heart (a filled heart means "I liked
    // it", which is only true on the detail screen).
    expect(find.byIcon(Icons.favorite_border_rounded), findsWidgets);
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
  });

  testWidgets('tapping Solicitado sends the request and shows Solicitado',
      (tester) async {
    await pumpMatrixApp(tester, const ProfileScreen(nickname: 'joao'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('SOLICITAR'), findsOneWidget);

    await tester.tap(find.text('SOLICITAR'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('SOLICITADO'), findsOneWidget);
  });

  testWidgets('tapping Solicitado again cancels back to Solicitado',
      (tester) async {
    await pumpMatrixApp(tester, const ProfileScreen(nickname: 'joao'));
    await tester.pump(const Duration(milliseconds: 400));

    // Send a request first.
    await tester.tap(find.text('SOLICITAR'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('SOLICITADO'), findsOneWidget);

    // A second tap on the same button cancels the pending request → back to
    // SOLICITAR. The server is the source of truth (fake store deletes the
    // pending request row).
    await tester.tap(find.text('SOLICITADO'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('SOLICITAR'), findsOneWidget);
  });

  testWidgets('shows current user posts in the grid', (tester) async {
    await pumpMatrixApp(tester, const ProfileScreen());

    // The mock feed ships at least one post authored by leonardo (p1, p4).
    // The grid shows the neutral like COUNTER, not a liked-state heart.
    expect(find.byIcon(Icons.favorite_border_rounded), findsWidgets);
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
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
      await pumpMatrixApp(tester, const ProfileScreen(nickname: 'joao'));
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
      expect(find.text('AMIGOS DE LEONARDO'), findsOneWidget);
      expect(find.text('joao'), findsOneWidget);

      await tester.tap(find.text('joao'));
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
      await tester.tap(find.ancestor(
        of: find.textContaining('joao', findRichText: true),
        matching: find.byType(MatrixCard),
      ));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('SOLICITAR'), findsOneWidget);

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
      // Nickname field is pre-filled with the session nickname.
      expect(find.widgetWithText(TextField, 'leonardo'), findsOneWidget);
    });

    testWidgets('validates required nickname', (tester) async {
      await pumpMatrixApp(tester, const EditProfileScreen());

      // Clear the nickname field.
      await tester.enterText(find.byType(TextField).at(0), '');

      await tester.tap(find.text('SALVAR'));
      await tester.pump();

      expect(find.text('Nickname obrigatório'), findsOneWidget);
    });

    testWidgets('saves updated profile remotely', (tester) async {
      final state = await seededAppState();
      await pumpMatrixApp(tester, const EditProfileScreen(), state: state);

      await tester.enterText(find.byType(TextField).at(0), 'Neo');
      await tester.enterText(find.byType(TextField).at(1), 'The one');
      await tester.tap(find.text('SALVAR'));
      await tester.pumpAndSettle();

      expect(state.currentUser!.nickname, 'Neo');
      expect(state.currentUser!.bio, 'The one');
    });
  });

  group('profile grid like state', () {
    testWidgets(
        'grid shows a FILLED heart when the current user liked the post',
        (tester) async {
      // Seed a post authored by joao that leonardo (the session user) liked.
      final repos = FakeRepositories();
      repos.store.posts.add(Post(
        id: 'p9',
        authorId: 'u2',
        authorNickname: 'joao',
        text: 'Post curtido pelo viewer',
        createdAt: DateTime(2024, 1, 5),
        liked: true,
        likes: 1,
      ));
      repos.store.likedPostIds.add('p9');
      final state = AppState(repositories: repos);
      await pumpMatrixApp(
        tester,
        const ProfileScreen(nickname: 'joao'),
        state: state,
      );
      await tester.pump(const Duration(milliseconds: 400));

      // The heart the viewer liked is filled; the unliked one is empty.
      expect(find.byIcon(Icons.favorite_rounded), findsWidgets);
      expect(find.byIcon(Icons.favorite_border_rounded), findsWidgets);
    });
  });

  group('profile photo long press', () {
    setUp(() => resetProfileTracking());

    testWidgets('long-press on ANOTHER user avatar opens the zoom dialog',
        (tester) async {
      await pumpMatrixApp(tester, const ProfileScreen(nickname: 'joao'));
      await tester.pump(const Duration(milliseconds: 400));

      // Press and hold ~2s to trigger the zoom, then release.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(UserAvatar).first),
      );
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      await tester.pumpAndSettle();

      // The enlarged, circular view-only dialog is shown.
      expect(find.byType(ClipOval), findsWidgets);
    });

    testWidgets('long-press on OWN avatar does nothing (no zoom)',
        (tester) async {
      await pumpMatrixApp(tester, const ProfileScreen());
      await tester.pump(const Duration(milliseconds: 400));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(UserAvatar).first),
      );
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      await tester.pumpAndSettle();

      // No enlarged photo dialog opens on the own profile.
      expect(find.byType(UserAvatar), findsOneWidget);
      expect(find.byType(ClipOval), findsNothing);
    });

    testWidgets('tapping OUTSIDE the enlarged photo closes the zoom dialog',
        (tester) async {
      await pumpMatrixApp(tester, const ProfileScreen(nickname: 'joao'));
      await tester.pump(const Duration(milliseconds: 400));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(UserAvatar).first),
      );
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(ClipOval), findsWidgets);

      // Tap the barrier (outside the circle) → closes.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(ClipOval), findsNothing);
    });
  });

  group('existing friendship (AMIGOS)', () {
    // Builds an AppState where leonardo (u0) is ALREADY friends with joao
    // (u2), so the profile button renders AMIGOS. Returns both so tests can
    // inspect the fake server store (server is the source of truth).
    Future<({AppState state, FakeRepositories repos})> friendsState() async {
      final repos = FakeRepositories();
      repos.store.friendships.add('u0|u2');
      final state = AppState(repositories: repos);
      await state.restoreSession();
      await state.loadFeed();
      return (state: state, repos: repos);
    }

    testWidgets('shows AMIGOS and confirmation modal on tap',
        (tester) async {
      final seeded = await friendsState();
      await pumpMatrixApp(
          tester, const ProfileScreen(nickname: 'joao'), state: seeded.state);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('AMIGOS'), findsOneWidget);

      // Tapping AMIGOS opens the MATRIX-styled confirmation.
      await tester.tap(find.text('AMIGOS'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Deixar de ser amigo de joao'),
        findsOneWidget,
      );
      expect(find.text('NÃO'), findsOneWidget);
      expect(find.text('SIM'), findsOneWidget);
    });

    testWidgets('NÃO keeps the friendship (no server change)', (tester) async {
      final seeded = await friendsState();
      await pumpMatrixApp(
          tester, const ProfileScreen(nickname: 'joao'), state: seeded.state);
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('AMIGOS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NÃO'));
      await tester.pumpAndSettle();

      // Still AMIGOS, and the fake server still holds the friendship row.
      expect(find.text('AMIGOS'), findsOneWidget);
      expect(seeded.repos.store.friendships.contains('u0|u2'), isTrue);
    });

    testWidgets('SIM removes the friendship → back to SOLICITAR',
        (tester) async {
      final seeded = await friendsState();
      await pumpMatrixApp(
          tester, const ProfileScreen(nickname: 'joao'), state: seeded.state);
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('AMIGOS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SIM'));
      await tester.pumpAndSettle();

      // Friendship removed on the server and the button returns to SOLICITAR.
      expect(seeded.repos.store.friendships.contains('u0|u2'), isFalse);
      expect(find.text('SOLICITAR'), findsOneWidget);
    });
  });
}
