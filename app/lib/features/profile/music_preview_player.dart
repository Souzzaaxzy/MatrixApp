import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/widgets/play_pause_icon.dart';
import '../../core/widgets/progress_ring.dart';
import '../../data/api_config.dart';
import '../../data/repositories/music_repository.dart';

/// Prévia da janela escolhida, usada na tela de escolher a música.
///
/// Por que existe: o download definitivo só acontece na confirmação (para não
/// baixar enquanto o usuário ainda arrasta as alças), então sem isto ele
/// escolheria a parte da música NO ESCURO — "será que é esse refrão?".
///
/// Como funciona: o servidor entrega a FAIXA INTEIRA (baixada uma vez e
/// mantida em cache lá) e o player toca só a JANELA via `setClip`. Assim
/// arrastar as alças não baixa nada de novo — só o recorte muda.
///
/// Semântica igual à do player do perfil: apertar play roda, apertar pause
/// volta para o começo, e play de novo recomeça (um ciclo, não um "retomar").
class MusicPreviewPlayer extends StatefulWidget {
  const MusicPreviewPlayer({
    super.key,
    required this.sourceId,
    required this.startMs,
    required this.durationMs,
    this.size = 44,
  });

  final String sourceId;

  /// Janela escolhida (ms) — muda a cada arrasto das alças.
  final int startMs;
  final int durationMs;

  final double size;

  @override
  State<MusicPreviewPlayer> createState() => MusicPreviewPlayerState();
}

class MusicPreviewPlayerState extends State<MusicPreviewPlayer> {
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSub;
  bool _loading = false;
  bool _playing = false;
  String? _url;

  /// Um único player de prévia no app inteiro.
  static AudioPlayer? _activePlayer;

  @override
  void didUpdateWidget(covariant MusicPreviewPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Mudou a seleção (arrastou a alça) ou a música: a reprodução antiga não
    // representa mais o que está na tela. Para e volta ao começo — o usuário
    // aperta play para ouvir a seleção atual.
    final changed = oldWidget.sourceId != widget.sourceId ||
        oldWidget.startMs != widget.startMs ||
        oldWidget.durationMs != widget.durationMs;
    if (changed) {
      stopAndReset();
    }
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }

  void _teardown() {
    final player = _player;
    _player = null;
    _stateSub?.cancel();
    _stateSub = null;
    _playing = false;
    if (player != null) {
      if (_activePlayer == player) _activePlayer = null;
      player.stop().catchError((_) {});
      player.dispose();
    }
  }

  /// Para e volta ao começo da janela (pausar = resetar).
  Future<void> stopAndReset() async {
    final player = _player;
    if (player != null) {
      await player.pause().catchError((_) {});
      await player.seek(_clipStart).catchError((_) {});
    }
    if (!mounted) return;
    setState(() => _playing = false);
  }

  Duration get _clipStart =>
      Duration(milliseconds: widget.startMs.clamp(0, 1 << 31));

  Duration get _clipEnd => Duration(
        milliseconds: (widget.startMs + widget.durationMs).clamp(0, 1 << 31),
      );

  Future<void> _toggle() async {
    if (_playing) {
      await stopAndReset();
      return;
    }

    _player ??= AudioPlayer(handleAudioSessionActivation: false);
    _stateSub ??= _player!.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state.playing);
      if (state.processingState == ProcessingState.completed) {
        // Fim da janela: volta ao começo e para (sem loop automático).
        _player!.pause();
        _player!.seek(_clipStart);
        if (mounted) setState(() => _playing = false);
      }
    });

    try {
      await AudioSession.instance
          .then((s) => s.configure(const AudioSessionConfiguration.music()));
    } catch (_) {
      // Sem sessão configurada, o player ainda toca.
    }

    try {
      setState(() => _loading = true);
      // A URL da faixa é buscada uma vez; o RECORTE é aplicado a cada play,
      // então arrastar a alça não exige nova requisição de áudio.
      _url ??= await MusicRepository.previewUrl(widget.sourceId);
      if (_player!.audioSource == null) {
        await _player!.setUrl(ApiConfig.resolveUrl(_url!));
      }
      // setClip toca SÓ a janela escolhida (o arquivo é a faixa inteira).
      await _player!.setClip(start: _clipStart, end: _clipEnd);
      await _player!.seek(_clipStart);
      if (_activePlayer != null && _activePlayer != _player) {
        await _activePlayer!.pause();
      }
      _activePlayer = _player;
      setState(() => _loading = false);
      await _player!.play();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível ouvir a prévia.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: _toggle,
      borderRadius: BorderRadius.circular(999),
      child: ProgressRing(
        // A prévia não tem progresso próprio na régua (a régua JÁ mostra a
        // janela); o anel aqui só dá o acabamento circular do botão.
        progress: 0,
        size: widget.size,
        strokeWidth: 2,
        color: accent,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : PlayPauseIcon(playing: _playing, color: accent),
      ),
    );
  }
}
