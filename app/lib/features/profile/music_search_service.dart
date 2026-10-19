import 'package:flutter/widgets.dart';

import '../../core/services/app_state.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../models/profile_music.dart';

/// The excerpt the user chose but has not confirmed yet.
///
/// Returned by [ProfileMusicPicker] so the caller performs the save — the
/// picker never writes to the server itself. That keeps the network call (and
/// its progress/error handling) next to the profile screen that owns it.
class PendingProfileMusic {
  const PendingProfileMusic({
    required this.result,
    required this.startMs,
    required this.durationMs,
  });

  final MusicSearchResult result;
  final int startMs;
  final int durationMs;
}

/// Indirection so widget tests can drive the picker without HTTP.
///
/// Production never overrides this; a test sets it to a fake and restores it
/// afterwards, which lets the picker's real state machine (search → select →
/// excerpt → confirm) be exercised end to end.
typedef MusicSearchFn = Future<List<MusicSearchResult>> Function(
  AppState state,
  String query,
);

MusicSearchFn? debugMusicSearchOverride;

/// Runs a music search through [AppState] (or the test override).
Future<List<MusicSearchResult>> searchProfileMusic(
  AppState state,
  String query,
) {
  final override = debugMusicSearchOverride;
  if (override != null) return override(state, query);
  return state.searchMusic(query);
}

/// Convenience: resolves [AppState] from the widget tree and searches.
Future<List<MusicSearchResult>> searchProfileMusicIn(
  BuildContext context,
  String query,
) {
  return searchProfileMusic(AppStateScope.of(context), query);
}
