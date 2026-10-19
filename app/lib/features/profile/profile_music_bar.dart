import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../data/api_config.dart';
import '../../models/profile_music.dart';
import '../../core/widgets/play_pause_icon.dart';
import '../../core/widgets/progress_ring.dart';

/// A música fixada no perfil: botão ⏯️ com ANEL DE PROGRESSO em volta e o
/// nome da música ao lado (o padrão do Instagram).
///
/// Fica logo abaixo do `#id` no cabeçalho do perfil. Só UM player toca por
/// vez (o mesmo cuidado do player de mensagem de voz): abrir outro perfil, ou
/// sair da tela, para o anterior.
///
/// O áudio é um TRECHO servido pela própria API (`/static/music/...`), então
/// a URL é resolvida contra a base da API — nunca entregue crua ao
/// just_audio, que não saberia resolver um caminho relativo.
class ProfileMusicBar extends StatefulWidget {
  const ProfileMusicBar({super.key, required this.music});

  final ProfileMusic music;

  @override
  State<ProfileMusicBar> createState() => _ProfileMusicBarState();
}

class _ProfileMusicBarState extends State<ProfileMusicBar> {
  AudioPlayer? _player;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration?>? _durSub;
  Duration _position = Duration.zero;
  bool _loading = false;
  bool _playing = false;

  /// Início da janela tocada dentro do arquivo. É o offset escolhido quando o
  /// arquivo é a faixa inteira (sem ffmpeg) e ZERO quando o arquivo já é o
  /// trecho (com ffmpeg).
  Duration get _windowStart => widget.music.playWindowOnly
      ? Duration(milliseconds: widget.music.startMs.clamp(0, 1 << 31))
      : Duration.zero;

  /// Fim da janela: quanto do ARQUIVO deve tocar. Com o trecho já cortado, é
  /// a duração do trecho; com a faixa inteira, é o offset + a duração.
  Duration get _windowEnd => widget.music.playWindowOnly
      ? Duration(
          milliseconds: (widget.music.startMs + widget.music.durationMs)
              .clamp(0, 1 << 31),
        )
      : Duration(milliseconds: widget.music.durationMs.clamp(0, 1 << 31));

  /// Quanto tempo a música toca de fato (a barra mede ISTO, não o arquivo).
  Duration get _windowLength =>
      _windowEnd - _windowStart > Duration.zero
          ? _windowEnd - _windowStart
          : Duration(milliseconds: widget.music.durationMs.clamp(0, 1 << 31));

  /// Um único player ativo no app inteiro — tocar uma música para a outra.
  static AudioPlayer? _activePlayer;

  @override
  void initState() {
    super.initState();
    // A janela já vem do modelo (startMs/durationMs), então a barra desenha
    // certo antes mesmo de o áudio carregar.
  }

  @override
  void didUpdateWidget(covariant ProfileMusicBar old) {
    super.didUpdateWidget(old);
    // Trocou a música → o player antigo não representa mais esta barra.
    if (old.music.audioUrl != widget.music.audioUrl) {
      _teardown();
      _position = Duration.zero;
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
    _posSub?.cancel();
    _stateSub?.cancel();
    _durSub?.cancel();
    _posSub = null;
    _stateSub = null;
    _durSub = null;
    _playing = false;
    if (player != null) {
      if (_activePlayer == player) _activePlayer = null;
      // Sair da tela para o áudio: uma música de perfil não deve continuar
      // tocando depois que o perfil fechou.
      player.stop().catchError((_) {});
      player.dispose();
    }
  }

  Future<void> _ensureSubs() async {
    final player = _player!;
    _posSub ??= player.positionStream.listen((p) {
      if (!mounted) return;
      // Sem ffmpeg o arquivo é a faixa inteira: ao chegar no fim da JANELA,
      // para (senão tocaria o resto da música, que não é o que foi escolhido).
      if (widget.music.playWindowOnly && p >= _windowEnd) {
        player.pause();
        player.seek(_windowStart);
        setState(() {
          _position = _windowStart;
          _playing = false;
        });
        return;
      }
      setState(() => _position = p);
    });
    _stateSub ??= player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state.playing);
      if (state.processingState == ProcessingState.completed) {
        // Fim do arquivo: volta ao início da JANELA e para (um trecho curto
        // reiniciando sozinho em loop seria irritante).
        player.pause();
        player.seek(_windowStart);
        if (mounted) {
          setState(() {
            _position = _windowStart;
            _playing = false;
          });
        }
      }
    });
  }

  Future<void> _toggle() async {
    final url = ApiConfig.resolveUrl(widget.music.audioUrl);
    if (url.isEmpty) return;

    if (_playing) {
      await _player?.pause();
      return;
    }

    _player ??= AudioPlayer(
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
    try {
      await AudioSession.instance.then((s) => s.configure(const AudioSessionConfiguration.music()));
    } catch (_) {
      // Sem sessão de áudio configurada, o player ainda toca.
    }

    try {
      if (_player!.audioSource == null) {
        setState(() => _loading = true);
        await _player!.setUrl(url);
        // Sem ffmpeg no servidor, o arquivo é a FAIXA INTEIRA: começa no
        // offset escolhido. Com ffmpeg, o arquivo já É o trecho (start 0).
        if (_windowStart > Duration.zero) {
          await _player!.seek(_windowStart);
        }
      }
      // Outro player ativo cede o lugar.
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
        const SnackBar(content: Text('Não foi possível tocar a música.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // A barra mede a JANELA tocada, não o arquivo: com o trecho já cortado os
    // dois coincidem; com a faixa inteira (sem ffmpeg) usar o arquivo faria a
    // barra parecer quase vazia durante o trecho.
    final windowMs = _windowLength.inMilliseconds;
    final elapsed = (_position - _windowStart).inMilliseconds.clamp(0, windowMs);
    final progress = windowMs > 0 ? elapsed / windowMs : 0.0;

    return Row(
      children: [
        // Botão ⏯️ desenhado, com o ANEL DE PROGRESSO em volta (o padrão do
        // Instagram): a trilha mostra o quanto falta e o arco cresce do topo
        // enquanto o trecho toca.
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(999),
          child: ProgressRing(
            progress: progress,
            size: 46,
            strokeWidth: 2.5,
            color: AppColors.electricBlue,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.electricBlue.withValues(alpha: 0.14),
              ),
              child: Center(
                child: _loading
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.electricBlue,
                          ),
                        ),
                      )
                    : PlayPauseIcon(
                        playing: _playing,
                        color: AppColors.electricBlue,
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppDimensions.spaceSm),
        // Nome da música à direita do botão, com ellipsis (nunca estoura
        // a largura do cabeçalho).
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.music.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(fontSize: 13),
              ),
              if (widget.music.artist.trim().isNotEmpty)
                Text(
                  widget.music.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.hud.copyWith(
                    fontSize: 10,
                    color: AppColors.holographicBlue,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
