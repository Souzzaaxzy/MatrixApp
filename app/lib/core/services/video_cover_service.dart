import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Lazily builds a cover/thumbnail for video posts that were created
/// BEFORE the cover feature existed (no persisted `thumbnailUrl`), reusing
/// the SAME `video_thumbnail` plugin the create-post flow already uses.
///
/// Guarantees:
///  * each URL is extracted at most ONCE per session (memory cache + a
///    disk cache in the app's temp dir, so reopening a profile never
///    regenerates or re-downloads);
///  * extractions run ONE at a time (a profile grid with many old videos
///    never floods the network — no simultaneous full-video downloads);
///  * failures are cached as "no cover" for the session (no repeat attempts
///    on every tile rebuild/scroll);
///  * known-failed URLs resolve to null instantly.
///
/// New videos (with a persisted `thumbnailUrl`) NEVER pass through here —
/// the profile tile shows the server cover directly.
class VideoCoverService {
  VideoCoverService._();
  static final VideoCoverService instance = VideoCoverService._();

  static const int _maxWidth = 720;
  static const int _quality = 80;

  /// URL → last known result (Uint8List OR null=failed, forever in-session).
  final Map<String, Uint8List?> _memory = {};

  /// URL → completer of an extraction that has not finished yet (dedupe
  /// concurrent calls for the same URL).
  final Map<String, Completer<Uint8List?>> _jobs = {};

  bool _processing = false;

  /// Resolves the cover bytes for [videoUrl], or null when none is available
  /// (or the extraction fails). Safe to call from any tile; concurrent
  /// calls for the same URL share ONE extraction.
  Future<Uint8List?> coverFor(String videoUrl) async {
    if (_memory.containsKey(videoUrl)) {
      return _memory[videoUrl];
    }
    final inflight = _jobs[videoUrl];
    if (inflight != null) return inflight.future;

    final completer = Completer<Uint8List?>();
    _jobs[videoUrl] = completer;
    if (!_processing) {
      _processing = true;
      unawaited(_drain());
    }
    return completer.future;
  }

  Future<void> _drain() async {
    while (_jobs.isNotEmpty) {
      final entry = _jobs.entries.first;
      _jobs.remove(entry.key);
      final bytes = await _extractOnce(entry.key);
      _memory[entry.key] = bytes;
      if (bytes != null) {
        try {
          await _writeCache(entry.key, bytes);
        } catch (_) {}
      }
      entry.value.complete(bytes);
    }
    _processing = false;
  }

  Future<Uint8List?> _extractOnce(String videoUrl) async {
    final cached = await _readCache(videoUrl);
    if (cached != null) return cached;

    try {
      return await VideoThumbnail.thumbnailData(
        video: videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: _maxWidth,
        quality: _quality,
        timeMs: 1000,
      );
    } catch (_) {
      // Plugin/method-channel failures (offline, codec, etc.) — the
      // tile keeps its video placeholder; no crash, no retry this session.

      return null;
    }
  }

  /// ---- persistent cache (app temp dir, keyed by URL hash) ----

  Future<File> _cacheFile(String videoUrl) async {
    final dir = await getTemporaryDirectory();
    final hash = sha256.convert(utf8.encode(videoUrl)).toString().substring(0, 32);
    return File('${dir.path}/mc_cover_$hash.jpg');
  }

  Future<Uint8List?> _readCache(String videoUrl) async {
    try {
      final file = await _cacheFile(videoUrl);
      if (file.existsSync()) return file.readAsBytes();
    } catch (_) {}
    return null;
  }

  Future<void> _writeCache(String videoUrl, Uint8List bytes) async {
    final file = await _cacheFile(videoUrl);
    await file.writeAsBytes(bytes, flush: true);
  }

  /// Test hook: clears all in-memory state (disk untouched).
  @visibleForTesting
  void resetForTest() {
    _memory.clear();
    _jobs.clear();
    _processing = false;
  }
}