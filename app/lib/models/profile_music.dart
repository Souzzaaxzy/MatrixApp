/// A song pinned to a profile (Instagram-style).
///
/// The audio is a SHORT excerpt (at most 1 minute) hosted by the API; the
/// server owns the download, so the app only plays what it is given. `startMs`
/// is where the excerpt begins in the original track, which lets the UI show
/// "trecho de 1:12 a 2:12" honestly instead of implying the whole song.
class ProfileMusic {
  const ProfileMusic({
    required this.title,
    required this.artist,
    this.coverUrl,
    required this.audioUrl,
    required this.durationMs,
    this.startMs = 0,
    this.playWindowOnly = false,
    this.sourceUrl = '',
    this.sourceId = '',
  });

  final String title;
  final String artist;
  final String? coverUrl;
  final String audioUrl;

  /// Length of the stored excerpt in milliseconds (<= 60000).
  final int durationMs;

  /// Offset of the excerpt inside the source track, in milliseconds.
  final int startMs;

  /// True when the stored FILE is the WHOLE track and the player must play
  /// only the [startMs, startMs+durationMs) window.
  ///
  /// This happens on the server's no-ffmpeg path: cutting audio requires
  /// ffmpeg (the most fragile package on Termux), so instead of cutting the
  /// server keeps the full m4a and the APP starts at the offset and stops at
  /// the end of the excerpt — the listener hears exactly the same excerpt.
  final bool playWindowOnly;

  /// Public page of the source track, used to credit the author.
  final String sourceUrl;
  final String sourceId;

  /// Human label for the excerpt length, e.g. `0:45`.
  String get durationLabel => formatMs(durationMs);

  /// The excerpt window inside the source track, e.g. `1:12 – 1:57`.
  /// Falls back to the length alone when the offset is unknown.
  String get excerptLabel =>
      startMs > 0 ? '${formatMs(startMs)} – ${formatMs(startMs + durationMs)}' : durationLabel;

  /// `mm:ss` for a duration in milliseconds.
  static String formatMs(int ms) {
    final totalSeconds = (ms / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// The display line for the profile: `Música · Artista` (artist omitted
  /// when the server had none — never a dangling separator).
  String get displayLabel =>
      artist.trim().isEmpty ? title : '$title · $artist';

  static ProfileMusic? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final audioUrl = raw['audioUrl'];
    if (audioUrl is! String || audioUrl.isEmpty) return null;
    return ProfileMusic(
      title: (raw['title'] as String?) ?? '',
      artist: (raw['artist'] as String?) ?? '',
      coverUrl: raw['coverUrl'] as String?,
      audioUrl: audioUrl,
      durationMs: (raw['durationMs'] as num?)?.toInt() ?? 0,
      startMs: (raw['startMs'] as num?)?.toInt() ?? 0,
      playWindowOnly: raw['playWindowOnly'] == true,
      sourceUrl: (raw['sourceUrl'] as String?) ?? '',
      sourceId: (raw['sourceId'] as String?) ?? '',
    );
  }
}

/// A search result from the server's music search (not yet pinned).
///
/// This is metadata only — nothing is downloaded until the user picks one and
/// confirms the excerpt, which is why the search is cheap.
class MusicSearchResult {
  const MusicSearchResult({
    required this.sourceId,
    required this.title,
    required this.artist,
    this.coverUrl,
    this.durationMs = 0,
  });

  final String sourceId;
  final String title;
  final String artist;
  final String? coverUrl;
  final int durationMs;

  String get durationLabel => ProfileMusic.formatMs(durationMs);

  String get displayLabel =>
      artist.trim().isEmpty ? title : '$title · $artist';

  static MusicSearchResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final sourceId = raw['sourceId'];
    if (sourceId is! String || sourceId.isEmpty) return null;
    return MusicSearchResult(
      sourceId: sourceId,
      title: (raw['title'] as String?) ?? '',
      artist: (raw['artist'] as String?) ?? '',
      coverUrl: raw['coverUrl'] as String?,
      durationMs: (raw['durationMs'] as num?)?.toInt() ?? 0,
    );
  }
}
