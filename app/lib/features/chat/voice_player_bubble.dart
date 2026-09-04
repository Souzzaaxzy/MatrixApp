import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../data/api_config.dart';
import '../../models/conversation.dart';

/// The inline voice-message player inside a chat bubble.
///
/// Lightweight: a single [AudioPlayer] per visible bubble, a play/pause
/// button and a linear progress + elapsed/duration clock. Only the tile
/// actually playing advances (the others stay idle), so a long thread of
/// voice messages doesn't spin a dozen timers.
class VoicePlayerBubble extends StatefulWidget {
  const VoicePlayerBubble({
    super.key,
    required this.message,
    required this.mine,
    this.compact = false,
  });

  final ChatMessage message;
  final bool mine;
  final bool compact;

  @override
  State<VoicePlayerBubble> createState() => _VoicePlayerBubbleState();
}

class _VoicePlayerBubbleState extends State<VoicePlayerBubble> {
  AudioPlayer? _player;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration?>? _durSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _loading = false;
  bool _playing = false;
  bool _completed = false;

  static AudioPlayer? _activePlayer; // only one voice message plays at once

  @override
  void initState() {
    super.initState();
    if (!widget.compact) {
      // Non-zero duration from the network payload seeds the bar.
      _duration = Duration(
          milliseconds: (widget.message.durationMs ?? 0).clamp(0, 1 << 31));
    }
  }

  @override
  void dispose() {
    // Tear down the shared audio focus ONLY when the ACTIVE bubble goes away
    // (an idle bubble that merely activated the session earlier must not mute
    // another bubble still playing — it stays until the active one disposes).
    if (_player == _activePlayer) {
      _activePlayer = null;
      if (_audioSessionActive) {
        _audioSessionActive = false;
        unawaited(_releaseAudioSession());
      }
    }
    _posSub?.cancel();
    _stateSub?.cancel();
    _durSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _releaseAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {
      // Best-effort teardown — nothing else to do..
    }
  }

  bool get _atEnd => _completed;

  Future<void> _toggle() async {
    if (widget.compact) {
      // Compact tiles (conversation-list previews) have no interactive
      // player — the whole row is a "Ver conversa" affordance already.
      return;
    }
    // The server may return a RELATIVE url (`/static/audio/x.m4a`) when no
    // public base URL is configured (the default). Never hand that to
    // just_audio directly — resolve against the API base so playback works for
    // the sender and the recipient and survives app restarts.
    final raw = widget.message.audioUrl;
    if (raw == null || raw.isEmpty) return;
    final url = ApiConfig.resolveUrl(raw);
    if (_playing) {
      await _player?.pause();
      return;
    }
    // Resume an existing player or start a fresh one.
    _player ??= AudioPlayer(
      // The remote server usually has no public base URL configured (the
      // default so we serve `UrlAudioSource`s (streaming) — that is what the
      // byte-seeking [AudioLoadConfiguration] below targets..
      handleAudioSessionActivation: false,
      audioLoadConfiguration: const AudioLoadConfiguration(
        androidLoadControl: AndroidLoadControl(
          minBufferDuration: Duration.zero,
          maxBufferDuration: Duration(seconds: 60),
          bufferForPlaybackDuration: Duration.zero,
          bufferForPlaybackAfterRebufferDuration: Duration.zero,
        ),
      ),
    );
    await _ensureSubs();
    // The audio session is owned here (none of the just_audio players may
    // fight the native focus) — activate once on first playback and keep it,
    // deactivating only on dispose..
    await _ensureAudioSession();
    try {
      if (_player!.playing) {
        await _player!.stop();
      }
      if (_player!.audioSource == null) {
        setState(() => _loading = true);
        await _player!.setUrl(url);
      }
      // Replay after completion:the just_audio position stays at the end, so
      // rewind to zero before (re)playing — otherwise the bar would start
      // full and the tint immediately show "done" instead of "playing"。
      // (A mid-play pause keeps its position — calling play() resumes it.)
      if (_completed) {
        await _player!.seek(Duration.zero);
        _position = Duration.zero;
      }
      setState(() {
        _loading = false;
        _completed = false;
      });
      // Only one tile plays at a time — stop any other active bubble..
      if (_activePlayer != null && _activePlayer != _player) {
        await _activePlayer!.pause();
      }
      _activePlayer = _player;
      await _player!.play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _playing = false;
        _duration = Duration(milliseconds: (widget.message.durationMs ?? 0));
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Não foi possível reproduzir o áudio.'),
          duration: Duration(seconds: 2),
        ));
    }
  }

  bool _audioSessionActive = false;

  Future<void> _ensureAudioSession() async {
    if (_audioSessionActive) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);
      _audioSessionActive = true;
    } catch (e) {
      // Headless tests/unsupported platforms fall back to classic behavior..
    }
  }

  Future<void> _ensureSubs() async {
    _posSub ??= _player!.positionStream.listen((d) {
      if (!mounted) return;
      // On completion the platform emits one last trailing event with the
      // position pinned at the END (the full duration), usually AFTER the
      // player-state stream already flipped us back to "play" and reset the
      // bar — so ignore it or the progress would snap back to full and the
      // button would appear "done" until the next rebuild.
      if (_atEnd) return;
      setState(() => _position = d);
    });
    _durSub ??= _player!.durationStream.listen((d) {
      if (!mounted) return;
      if (d != null) setState(() => _duration = d);
    });
    _stateSub ??= _player!.playerStateStream.listen((s) {
      if (!mounted) return;
      setState(() {
        _playing = s.playing;
        _loading = s.processingState == ProcessingState.buffering;
        if (s.processingState == ProcessingState.completed) {
          // Snap the button back to play and rewind the bar, so the next tap
          // replays from zero instead of showing a stale "paused at the end"..
          if (!_completed) {
            _position = Duration.zero;
            _completed = true;
          }
          _playing = false;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.mine;
    final fg = mine ? AppColors.techWhite : AppColors.holographicBlue;
    final fallbackSeconds = Duration(
            milliseconds:
                (widget.message.durationMs ?? _duration.inMilliseconds))
        .inSeconds;
    final width = _duration.inMilliseconds <= 0
        ? 120.0
        : 120.0 + (_duration.inSeconds.clamp(3, 60) * 1.6);
    final progress = _duration.inMilliseconds <= 0
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: widget.compact ? null : _toggle,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: mine
                  ? AppColors.absoluteBlack.withValues(alpha: 0.3)
                  : AppColors.deepBlue,
            ),
            child: Icon(
              _loading
                  ? Icons.hourglass_top_rounded
                  : _playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
              color: fg,
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: width.clamp(90, 210),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: mine
                      ? AppColors.techWhite.withValues(alpha: 0.25)
                      : AppColors.absoluteBlack.withValues(alpha: 0.35),
                  valueColor: AlwaysStoppedAnimation<Color>(
                      mine ? AppColors.techWhite : AppColors.electricBlue),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _formatDuration(_duration, fallbackSeconds),
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'JetBrainsMono',
                  color: fg.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d, int fallbackSeconds) {
    final totalSec = d.inSeconds > 0 ? d.inSeconds : fallbackSeconds;
    final m = (totalSec ~/ 60).toString().padLeft(2, '0');
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
