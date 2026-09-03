import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

/// The [FakeJustAudio] registered by [installFakeJustAudio] — tests grab
/// players from it (e.g. `fakeJustAudio.players[0]`).
FakeJustAudio get fakeJustAudio => JustAudioPlatform.instance as FakeJustAudio;

/// A gate held by the stubbed `requestAudioFocus` platform call inside
/// [installFakeJustAudio]'s audio-session stub. just_audio's public
/// `play()` awaits this channel call before handing control to the next event-
/// loop task — so while the gate is pending, every synchronous state
/// transition (stub events, playCompleters, etc.) lands first. Tests call
/// [unlockAudioFocus] after the first tap so the player remains fully
/// deterministic..
final audioFocusGate = Completer<void>();

/// Releases [audioFocusGate] so any blocked audio-session activation can
/// finish. Safe to call multiple times (only the first unlock wins).
void unlockAudioFocus() {
  if (!audioFocusGate.isCompleted) audioFocusGate.complete();
}

/// Registers a fresh [FakeJustAudio] as the just_audio platformand stubs
/// the `com.ryanheise.audio_session` method channel, so a widget tree
/// can actually create an [AudioPlayer] in tests. Call this at the start of
/// each test (before pumping a screen that plays voice notes) — the enclosed
/// players list is per-test, so tests never bleed player state into each
/// other. The native audio-focus channel is gated via [audioFocusGate];the
/// test decides when real platform work starts (see [unlockAudioFocus])
/// so timers and channel traffic never stall pump loops prematurely.
void installFakeJustAudio() {
  final fake = FakeJustAudio();

  JustAudioPlatform.instance = fake;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel(
            'com.ryanheise.audio_session',
          ),
          _handleAudioSessionCall);
}

/// Stubbed handler for just_audio's audio-session channel (owned by the
/// `audio_session` package): returns a default config, gates the real
/// `requestAudioFocus` behind [audioFocusGate] (see its doc) and no-ops
/// every other method.
Future<Object?> _handleAudioSessionCall(MethodCall call) async {
  switch (call.method) {
    case 'getConfiguration':
      return <String, dynamic>{};
    case 'requestAudioFocus':
      // Stall until [unlockAudioFocus] so just_audio's per-player
      // `play()` synchronous state (playing=true) always lands before
      // any platform call that could observe the player mid-load..
      await audioFocusGate.future;
      return null;
    // Remaining calls are no-ops in tests (setConfiguration, setActive,
    // getConfiguration_changed, abandonAudioFocus, unknown methods...
    default:
      return null;
  }
}

/// In-memory [JustAudioPlatform]that hands out [FakeAudioPlayer]s — the
/// test drives playback completion deterministically via
/// [FakeAudioPlayer.complete] (no real timers/network).
class FakeJustAudio extends JustAudioPlatform {
  /// Every player handed out by [init], in creation order — lets tests
  /// address each bubble's player directly (multiple voice tiles).
  final List<FakeAudioPlayer> players = [];

  final _players = <String, FakeAudioPlayer>{};

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) {
    final player = FakeAudioPlayer(request.id);
    _players[request.id] = player;
    players.add(player);
    return Future.value(player);
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    _players[request.id]?.dispose(DisposeRequest());
    _players.remove(request.id);
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
      DisposeAllPlayersRequest request) async {
    for (final player in _players.values) {
      player.dispose(DisposeRequest());
    }
    _players.clear();
    return DisposeAllPlayersResponse();
  }
}

/// A barebones in-memory [AudioPlayerPlatform]that never touches timers or
/// assets:the test (rather than real time) decides when playback
/// completes/advances, so completion-to-idle UI resets are deterministic..
class FakeAudioPlayer extends AudioPlayerPlatform {
  static const fakeDuration = Duration(seconds: 30);

  final eventController = StreamController<PlaybackEventMessage>();
  final dataMessageController = StreamController<PlayerDataMessage>();

  AudioSourceMessage? _audioSource;

  ProcessingStateMessage _processingState = ProcessingStateMessage.idle;
  Duration _updatePosition = Duration.zero;
  Duration? _duration;
  bool _playing = false;

  /// Mirror of `_playing` for test assertions (avoids the fake needing
  /// change-notification machinery):
  bool get playing => _playing;

  /// How many times [seek] was called — lets tests assert a replay after
  /// completion rewinds (seek) while a pause/resume never does..
  int seekCount = 0;

  /// Set synchronously when [dispose] is called — lets tests assert the
  /// player was released when the conversation closed (no leak).
  bool disposed = false;

  FakeAudioPlayer(super.id);

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream =>
      dataMessageController.stream;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      eventController.stream;

  void _emitData({bool? playing}) {
    final playingValue = playing ?? _playing;
    dataMessageController.add(PlayerDataMessage(playing: playingValue));
  }

  void _broadcast() {
    eventController.add(PlaybackEventMessage(
      processingState: _processingState,
      updateTime: DateTime.now(),
      updatePosition: _updatePosition,
      bufferedPosition: _updatePosition,
      duration: _duration,
      icyMetadata: null,
      currentIndex: _audioSource == null ? null : 0,
      androidAudioSessionId: null,
    ));
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final playlist =
        request.audioSourceMessage as ConcatenatingAudioSourceMessage;
    if (playlist.children.isEmpty) return LoadResponse(duration: null);
    final audioSource = playlist.children.first;
    _audioSource = audioSource;

    _processingState = ProcessingStateMessage.loading;
    _broadcast();
    _duration = fakeDuration;
    _updatePosition = request.initialPosition ?? Duration.zero;
    // Skip loading simulation — become ready immediately so setUrl returns.
    _processingState = ProcessingStateMessage.ready;
    _broadcast();
    if (_playing) _emitData();
    return LoadResponse(duration: _duration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    if (_playing) return PlayResponse();
    _playing = true;
    _emitData(playing: true);
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    if (!_playing) return PauseResponse();
    _playing = false;
    _emitData(playing: false);
    _broadcast();
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    seekCount++;
    _updatePosition = request.position ?? Duration.zero;
    // A seek from the completed state returns the player to a playable state..
    if (_processingState == ProcessingStateMessage.completed) {
      _processingState = ProcessingStateMessage.ready;
    }
    _broadcast();
    return SeekResponse();
  }

  /// Simulates playback reaching the end of the source — completes the
  /// current source without waiting real wall-clock time.
  Future<void> complete() async {
    if (!_playing) return;
    _playing = false;
    _updatePosition = _duration ?? fakeDuration;
    _processingState = ProcessingStateMessage.completed;
    _emitData(playing: false);
    _broadcast();
  }

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    disposed = true;
    _processingState = ProcessingStateMessage.idle;
    _broadcast();
    eventController.close();
    dataMessageController.close();
    return DisposeResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async =>
      SetPitchResponse();

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
          SetSkipSilenceRequest request) async =>
      SetSkipSilenceResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
          SetShuffleModeRequest request) async =>
      SetShuffleModeResponse();

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
              SetAutomaticallyWaitsToMinimizeStallingRequest request) async =>
          SetAutomaticallyWaitsToMinimizeStallingResponse();

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
          SetShuffleOrderRequest request) async =>
      SetShuffleOrderResponse();

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
          ConcatenatingInsertAllRequest request) async =>
      ConcatenatingInsertAllResponse();
}
