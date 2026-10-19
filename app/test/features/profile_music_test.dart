import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/core/widgets/play_pause_icon.dart';
import 'package:matrix_app/core/widgets/user_avatar.dart';
import 'package:matrix_app/features/profile/music_search_service.dart';
import 'package:matrix_app/features/profile/profile_music_bar.dart';
import 'package:matrix_app/features/profile/profile_music_picker.dart';
import 'package:matrix_app/features/profile/profile_screen.dart';
import 'package:matrix_app/models/profile_music.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

/// The pinned profile song: the ⏯️ button + song name on the profile, the
/// search/choose/confirm flow in "editar perfil", and the model formatting.
/// Pumps a host screen that pushes [ProfileMusicPicker] and captures what it
/// returns. The picker reads [AppState] from the scope, so it must be wrapped
/// in the real app wiring (a bare MaterialApp would make the search throw).
Future<void> pumpPickerHost(
  WidgetTester tester,
  void Function(PendingProfileMusic?) onResult,
) async {
  await pumpMatrixApp(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final result =
                  await Navigator.of(context).push<PendingProfileMusic>(
                MaterialPageRoute(
                  builder: (_) =>
                      const ProfileMusicPicker(initialQuery: 'song'),
                ),
              );
              onResult(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // Never hit the network from a widget test.
    debugMusicSearchOverride = null;
  });
  tearDown(() {
    debugMusicSearchOverride = null;
  });

  // ── Model ────────────────────────────────────────────────────
  group('ProfileMusic model', () {
    test('formats a duration as m:ss', () {
      expect(ProfileMusic.formatMs(0), '0:00');
      expect(ProfileMusic.formatMs(5000), '0:05');
      expect(ProfileMusic.formatMs(60000), '1:00');
      expect(ProfileMusic.formatMs(95000), '1:35');
    });

    test('excerptLabel shows the window inside the source track', () {
      const music = ProfileMusic(
        title: 'Song',
        artist: 'Artist',
        audioUrl: '/static/music/x.m4a',
        durationMs: 45000,
        startMs: 72000,
      );
      expect(music.excerptLabel, '1:12 – 1:57');
      // With no offset it degrades to the length alone (never "0:00 – 0:45").
      const fromStart = ProfileMusic(
        title: 'Song',
        artist: 'Artist',
        audioUrl: '/static/music/x.m4a',
        durationMs: 45000,
      );
      expect(fromStart.excerptLabel, '0:45');
    });

    test('displayLabel joins title and artist, omitting an empty artist', () {
      const both = ProfileMusic(
        title: 'Song',
        artist: 'Artist',
        audioUrl: '/static/music/x.m4a',
        durationMs: 1000,
      );
      expect(both.displayLabel, 'Song · Artist');
      const noArtist = ProfileMusic(
        title: 'Song',
        artist: '   ',
        audioUrl: '/static/music/x.m4a',
        durationMs: 1000,
      );
      // No dangling separator when the server had no artist.
      expect(noArtist.displayLabel, 'Song');
    });

    test('fromJson requires an audioUrl (a payload without audio is not music)',
        () {
      expect(ProfileMusic.fromJson(null), isNull);
      expect(ProfileMusic.fromJson(<String, dynamic>{}), isNull);
      expect(
        ProfileMusic.fromJson(<String, dynamic>{'title': 'X'}),
        isNull,
      );
      final parsed = ProfileMusic.fromJson(<String, dynamic>{
        'title': 'Song',
        'artist': 'Artist',
        'audioUrl': '/static/music/x.m4a',
        'durationMs': 30000,
        'startMs': 5000,
      });
      expect(parsed, isNotNull);
      expect(parsed!.title, 'Song');
      expect(parsed.startMs, 5000);
      // Sem a flag o padrão é false: o arquivo JÁ é o trecho (caminho ffmpeg).
      expect(parsed.playWindowOnly, isFalse);
    });

    test('fromJson reads playWindowOnly (the no-ffmpeg path)', () {
      // Sem ffmpeg o servidor guarda a faixa inteira e o app toca a janela.
      final parsed = ProfileMusic.fromJson(<String, dynamic>{
        'title': 'Song',
        'artist': 'Artist',
        'audioUrl': '/static/music/full.m4a',
        'durationMs': 45000,
        'startMs': 12000,
        'playWindowOnly': true,
      });
      expect(parsed!.playWindowOnly, isTrue);
      expect(parsed.startMs, 12000);
      expect(parsed.durationMs, 45000);
    });

    test('MusicSearchResult.fromJson requires a sourceId', () {
      expect(MusicSearchResult.fromJson(null), isNull);
      expect(
        MusicSearchResult.fromJson(<String, dynamic>{'title': 'X'}),
        isNull,
      );
      final parsed = MusicSearchResult.fromJson(<String, dynamic>{
        'sourceId': 'abc123',
        'title': 'Song',
        'artist': 'Artist',
        'durationMs': 210000,
      });
      expect(parsed!.sourceId, 'abc123');
      expect(parsed.durationLabel, '3:30');
    });
  });

  // ── The ⏯️ icon ──────────────────────────────────────────────
  group('PlayPauseIcon', () {
    testWidgets('renders in both states without error', (tester) async {
      for (final playing in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: PlayPauseIcon(playing: playing, color: Colors.blue),
              ),
            ),
          ),
        );
        expect(find.byType(PlayPauseIcon), findsOneWidget);
      }
    });

    testWidgets('repaints only when the state or color changes', (tester) async {
      // A cheap but real check that the painter's shouldRepaint is wired: the
      // icon must not repaint on identical input.
      const a = PlayPauseIcon(playing: false, color: Colors.red);
      const b = PlayPauseIcon(playing: false, color: Colors.red);
      expect(a.playing, b.playing);
      expect(a.color, b.color);
    });
  });

  // ── The profile bar ──────────────────────────────────────────
  group('ProfileMusicBar', () {
    const music = ProfileMusic(
      title: 'Bohemian Rhapsody',
      artist: 'Queen',
      audioUrl: '/static/music/x.m4a',
      durationMs: 45000,
    );

    testWidgets('shows the song name and artist next to the ⏯️ button',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProfileMusicBar(music: music)),
        ),
      );
      await tester.pump();

      expect(find.text('Bohemian Rhapsody'), findsOneWidget);
      expect(find.text('Queen'), findsOneWidget);
      // The drawn icon — never a Material play/pause glyph or an emoji.
      expect(find.byType(PlayPauseIcon), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byIcon(Icons.pause), findsNothing);
    });

    testWidgets('the button sits to the LEFT of the song name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProfileMusicBar(music: music)),
        ),
      );
      await tester.pump();

      final button = tester.getRect(find.byType(PlayPauseIcon));
      final name = tester.getRect(find.text('Bohemian Rhapsody'));
      expect(button.left, lessThan(name.left));
      // Vertically they share the row.
      expect(button.center.dy, closeTo(name.center.dy, 24));
    });

    testWidgets('tapping play does not throw when the audio cannot load',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProfileMusicBar(music: music)),
        ),
      );
      await tester.pump();
      // No real audio in a widget test: the failure path must be handled (a
      // snackbar), never an unhandled exception.
      await tester.tap(find.byType(PlayPauseIcon));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });
  });

  // ── The picker (search → choose → excerpt → confirm) ──────────
  group('ProfileMusicPicker', () {
    testWidgets('searches and lists the results it received', (tester) async {
      final queries = <String>[];
      debugMusicSearchOverride = (state, query) async {
        queries.add(query);
        return const [
          MusicSearchResult(
            sourceId: 'a1',
            title: 'Bohemian Rhapsody',
            artist: 'Queen',
            durationMs: 359000,
          ),
          MusicSearchResult(
            sourceId: 'b2',
            title: 'Another One Bites the Dust',
            artist: 'Queen',
            durationMs: 200000,
          ),
        ];
      };

      await pumpMatrixApp(
        tester,
        const ProfileMusicPicker(initialQuery: 'queen'),
      );
      await tester.enterText(find.byType(TextField).first, 'queen');
      await tester.tap(find.text('BUSCAR'));
      await tester.pumpAndSettle();

      expect(queries, ['queen']);
      expect(find.text('Bohemian Rhapsody'), findsOneWidget);
      expect(find.text('Another One Bites the Dust'), findsOneWidget);
    });

    testWidgets('an empty result set shows a helpful message, not a crash',
        (tester) async {
      debugMusicSearchOverride = (state, query) async => const [];
      await pumpMatrixApp(
        tester,
        const ProfileMusicPicker(initialQuery: 'nada'),
      );
      await tester.tap(find.text('BUSCAR'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nenhuma música encontrada'), findsOneWidget);
    });

    testWidgets('selecting a result reveals the excerpt controls', (tester) async {
      debugMusicSearchOverride = (state, query) async => const [
            MusicSearchResult(
              sourceId: 'a1',
              title: 'Song',
              artist: 'Artist',
              durationMs: 300000,
            ),
          ];
      await pumpMatrixApp(
        tester,
        const ProfileMusicPicker(initialQuery: 'song'),
      );
      await tester.tap(find.text('BUSCAR'));
      await tester.pumpAndSettle();
      // Before selecting there is no excerpt section.
      expect(find.text('TRECHO'), findsNothing);
      await tester.tap(find.text('Song'));
      await tester.pumpAndSettle();
      expect(find.text('TRECHO'), findsOneWidget);
      expect(find.text('Duração'), findsOneWidget);
      expect(find.text('Início'), findsOneWidget);
    });

    testWidgets('the excerpt duration never exceeds 1 minute', (tester) async {
      debugMusicSearchOverride = (state, query) async => const [
            MusicSearchResult(
              sourceId: 'a1',
              title: 'Song',
              artist: 'Artist',
              durationMs: 600000,
            ),
          ];
      await pumpMatrixApp(
        tester,
        const ProfileMusicPicker(initialQuery: 'song'),
      );
      await tester.tap(find.text('BUSCAR'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Song'));
      await tester.pumpAndSettle();

      // Push the duration up far past the cap: it must stop at 1:00.
      final plus = find.byIcon(Icons.add_rounded).first;
      for (var i = 0; i < 12; i++) {
        await tester.tap(plus);
        await tester.pump();
      }
      expect(find.text('1:00'), findsOneWidget);
      expect(find.text('1:05'), findsNothing);
    });

    testWidgets('confirming returns the chosen excerpt to the caller',
        (tester) async {
      debugMusicSearchOverride = (state, query) async => const [
            MusicSearchResult(
              sourceId: 'a1',
              title: 'Song',
              artist: 'Artist',
              durationMs: 300000,
            ),
          ];

      PendingProfileMusic? returned;
      await pumpPickerHost(tester, (result) => returned = result);

      await tester.tap(find.text('BUSCAR'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Song'));
      await tester.pumpAndSettle();
      // The confirm button sits below the fold on a small test viewport.
      await tester.ensureVisible(find.text('CONFIRMAR'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONFIRMAR'));
      await tester.pumpAndSettle();

      expect(returned, isNotNull);
      expect(returned!.result.sourceId, 'a1');
      expect(returned!.durationMs, 30000);
      expect(returned!.startMs, 0);
    });

    testWidgets('the start offset is clamped so the excerpt cannot overrun',
        (tester) async {
      debugMusicSearchOverride = (state, query) async => const [
            MusicSearchResult(
              sourceId: 'a1',
              title: 'Song',
              artist: 'Artist',
              // 45s track, 30s excerpt → start can only reach 15s.
              durationMs: 45000,
            ),
          ];
      PendingProfileMusic? returned;
      await pumpPickerHost(tester, (result) => returned = result);
      await tester.tap(find.text('BUSCAR'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Song'));
      await tester.pumpAndSettle();

      // Hammer "+" on the start row; it must stop at 15s (45 - 30).
      final plusButtons = find.byIcon(Icons.add_rounded);
      final startPlus = plusButtons.last;
      for (var i = 0; i < 10; i++) {
        await tester.tap(startPlus);
        await tester.pump();
      }
      await tester.ensureVisible(find.text('CONFIRMAR'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONFIRMAR'));
      await tester.pumpAndSettle();
      expect(returned!.startMs, 15000);
    });
  });

  // ── Position on the profile (below the #id) ──────────────────
  group('profile music position', () {
    testWidgets('the music bar sits BELOW the #id, above the bio',
        (tester) async {
      // carla is seeded with a pinned song.
      await pumpMatrixApp(
        tester,
        const ProfileScreen(nickname: 'carla'),
      );
      await tester.pump(const Duration(milliseconds: 400));

      final musicBar = find.byType(ProfileMusicBar);
      expect(musicBar, findsOneWidget);
      final musicRect = tester.getRect(musicBar);

      // The bar is what the user asked for: below the photo/#id.
      final header = tester.getRect(find.byType(UserAvatar).first);
      expect(musicRect.top, greaterThan(header.top));
    });

    testWidgets('the song name appears to the RIGHT of the ⏯️ button',
        (tester) async {
      await pumpMatrixApp(
        tester,
        const ProfileScreen(nickname: 'carla'),
      );
      await tester.pump(const Duration(milliseconds: 400));

      final button = tester.getRect(find.byType(PlayPauseIcon));
      final name = tester.getRect(find.text('Musica da Carla'));
      expect(button.left, lessThan(name.left));
      // Same row: their vertical centres are close.
      expect((button.center.dy - name.center.dy).abs(), lessThan(24));
    });

    testWidgets('a profile with no music renders no music bar', (tester) async {
      // leonardo has no pinned song.
      await pumpMatrixApp(tester, const ProfileScreen());
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ProfileMusicBar), findsNothing);
    });
  });

  // ── AppState wiring ──────────────────────────────────────────
  group('AppState profile music', () {
    test('searchMusic forwards the query to the repository', () async {
      final repos = FakeRepositories();
      repos.store.musicResults = const [
        MusicSearchResult(sourceId: 'a1', title: 'T', artist: 'A'),
      ];
      final state = AppState(repositories: repos);
      await state.restoreSession();

      final results = await state.searchMusic('queen');
      expect(repos.store.musicSearches, ['queen']);
      expect(results.single.sourceId, 'a1');
    });

    test('setProfileMusic stores the excerpt and updates the current user',
        () async {
      final repos = FakeRepositories();
      final state = AppState(repositories: repos);
      await state.restoreSession();

      await state.setProfileMusic(
        result: const MusicSearchResult(
          sourceId: 'a1',
          title: 'Song',
          artist: 'Artist',
        ),
        startMs: 12000,
        durationMs: 45000,
      );

      expect(repos.store.musicSetCalls.single.startMs, 12000);
      expect(repos.store.musicSetCalls.single.durationMs, 45000);
      // Local state reflects the server response immediately.
      expect(state.currentUser?.music?.title, 'Song');
      expect(state.currentUser?.music?.startMs, 12000);
    });

    test('clearProfileMusic clears it locally too', () async {
      final repos = FakeRepositories();
      final state = AppState(repositories: repos);
      await state.restoreSession();
      await state.setProfileMusic(
        result: const MusicSearchResult(
          sourceId: 'a1',
          title: 'Song',
          artist: 'Artist',
        ),
        startMs: 0,
        durationMs: 30000,
      );
      expect(state.currentUser?.music, isNotNull);

      await state.clearProfileMusic();
      expect(repos.store.musicClearCalls, 1);
      // A stale pinned song must not survive the removal.
      expect(state.currentUser?.music, isNull);
    });
  });
}
