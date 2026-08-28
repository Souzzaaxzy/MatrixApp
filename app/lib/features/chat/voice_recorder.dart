import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// The voice-message recorder lifecycle.
///
/// ```
/// IDLE ─start()→ RECORDING ─lock()─────────→ LOCKED ─finish()→ SENDING
///                  │  └─cancel()──────────────→ CANCELLED
///                  └──────────cancel()──────────────────────→ CANCELLED
/// ```
/// The only way out of RECORDING is [lock] (drag left), [cancel] (drag
/// right / interruption) or [dispose]. [finish]/stop are only legal from
/// LOCKED (the "tap to send a locked recording" flow) — guard rails in the
/// UI prevent starting a second recording or sending while one is being
/// processed.
///
/// Capture quality: AAC-LC @44.1kHz / 128kbps (one channel), a balanced
/// voice-optimized profile — low distortion, small files, instant playback,
/// a native Android container (m4a). The server validates bytes + size.
class VoiceRecorderController extends ChangeNotifier {
  AudioRecorder? _recorder;
  StreamSubscription<Amplitude>? _ampSub;
  String? _path;
  VoiceRecorderState _state = VoiceRecorderState.idle;
  String? _lastError;
  double _amplitude = 0; // 0..1 normalized, drives the waveform bars
  final Stopwatch _stopwatch = Stopwatch();

  VoiceRecorderState get state => _state;
  String? get lastError => _lastError;

  /// Normalized capture level (0..1). Best-effort — some devices report a
  /// flat value; the waveform still renders (attenuated noise floor).
  double get amplitude => _amplitude;

  Duration get elapsed => _stopwatch.elapsed;

  bool get isRecording =>
      _state == VoiceRecorderState.recording ||
      _state == VoiceRecorderState.locked;

  @override
  void dispose() {
    _ampSub?.cancel();
    _ampSub = null;
    _stopwatch.stop();
    final recorder = _recorder;
    _recorder = null;
    if (recorder != null) {
      // Best-effort fire-and-forget release (never leaves the mic open).
      unawaited(_tryRelease(recorder));
    }
    super.dispose();
  }

  Future<void> _tryRelease(AudioRecorder recorder) async {
    try {
      if (await recorder.isRecording()) await recorder.stop();
    } catch (_) {
      // Already released / device disconnected — nothing more to do.
    }
    try {
      await recorder.dispose();
    } catch (_) {}
  }

  /// True when the platform reports the mic granted. Asks once if needed.
  Future<bool> ensurePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Starts capturing. Returns false when the permission was denied.
  Future<bool> start() async {
    if (_state == VoiceRecorderState.recording ||
        _state == VoiceRecorderState.locked ||
        _state == VoiceRecorderState.sending) {
      return false; // never two simultaneous recordings
    }
    if (!await ensurePermission()) {
      _lastError = 'Permissão do microfone necessária para gravar áudio.';
      _state = VoiceRecorderState.error;
      notifyListeners();
      return false;
    }
    final dir = await getTemporaryDirectory();
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = '${dir.path}/matrix_voice_$now.m4a';
    final recorder = AudioRecorder();
    _recorder = recorder;
    try {
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          bitRate: 128000,
          numChannels: 1,
        ),
        path: path,
      );
      _path = path;
      _amplitude = 0;
      _stopwatch
        ..reset()
        ..start();
      _ampSub = recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((a) {
        // map ~(0..N dBFS) into a display curve; floor it so idle looks like
        // a steady capture rather than full silence.
        final db = (a.current.clamp(-60.0, 0.0) + 60.0) / 60.0;
        _amplitude = (db < 0.05 ? 0.05 : db).clamp(0.0, 1.0);
        notifyListeners();
      });
      _state = VoiceRecorderState.recording;
      _lastError = null;
      notifyListeners();
      if (kDebugMode) debugPrint('[voice] recording started → $path');
      return true;
    } catch (e) {
      await _tryRelease(recorder);
      _recorder = null;
      _lastError = 'Não foi possível iniciar a gravação.';
      _state = VoiceRecorderState.error;
      notifyListeners();
      return false;
    }
  }

  /// Freeze recording so the finger can release (drag left gesture).
  void lock() {
    if (_state != VoiceRecorderState.recording) return;
    _state = VoiceRecorderState.locked;
    notifyListeners();
  }

  /// Cancels and discards the current capture (drag right / interruption).
  Future<void> cancel() async {
    if (kDebugMode) {
      debugPrint(
          '[voice] recording cancelled (${_stopwatch.elapsed.inMilliseconds}ms)');
    }
    final recorder = _recorder;
    _ampSub?.cancel();
    _ampSub = null;
    _stopwatch.stop();
    _recorder = null;
    _path = null;
    if (recorder != null) await _tryRelease(recorder);
    _state = VoiceRecorderState.idle;
    _amplitude = 0;
    notifyListeners();
  }

  /// Stops a LOCKED recording and returns the captured file. Null when the
  /// recorder was never started or already consumed (guard against double
  /// send) or production failed.
  Future<File?> finish() async {
    if (_state != VoiceRecorderState.locked) return null;
    final recorder = _recorder;
    final path = _path;
    _recorder = null;
    _path = null;
    _state = VoiceRecorderState.sending;
    notifyListeners();
    _ampSub?.cancel();
    _ampSub = null;
    _stopwatch.stop();
    if (recorder == null || path == null) {
      _state = VoiceRecorderState.idle;
      notifyListeners();
      return null;
    }
    try {
      final stopped = await recorder.stop();
      await recorder.dispose();
      final finalPath = (stopped ?? '').isNotEmpty ? stopped! : path;
      final file = File(finalPath);
      final length = await file.length();
      if (!await file.exists() || length < 1024) {
        if (kDebugMode) {
          debugPrint('[voice] finish rejected — missing or too small '
              '(exists=${await file.exists()}, bytes=$length, path=$finalPath)');
        }
        // Too tiny to be a real capture — reject.
        _state = VoiceRecorderState.idle;
        notifyListeners();
        return null;
      }
      if (kDebugMode) {
        debugPrint('[voice] recording finished → $finalPath '
            '($length bytes, ${_stopwatch.elapsed.inMilliseconds}ms)');
      }
      return file;
    } catch (_) {
      _lastError = 'Falha ao finalizar o áudio.';
      _state = VoiceRecorderState.error;
      notifyListeners();
      return null;
    }
  }

  /// Reverts from ERROR back to IDLE (retry path).
  void resetError() {
    if (_state == VoiceRecorderState.error) {
      _state = VoiceRecorderState.idle;
      _lastError = null;
      notifyListeners();
    }
  }

  /// Returns the controller to IDLE after an upload attempt finishes — the
  /// capture ended and its file was already consumed, so the lingering
  /// SENDING state must not block the next recording (the press-start
  /// guard rejects anything that is not idle/error). Safe no-op if already idle.

  void resetToIdle() {
    if (_state == VoiceRecorderState.idle) {
      return;
    }
    if (_state == VoiceRecorderState.sending ||
        _state == VoiceRecorderState.error) {
      _state = VoiceRecorderState.idle;
      _lastError = null;
      _amplitude = 0;
      notifyListeners();
    }
  }
}

enum VoiceRecorderState {
  idle,
  recording,
  locked,
  sending,
  cancelled,
  error,
}
