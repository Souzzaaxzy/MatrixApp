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

/// A música fixada no perfil: botão ⏯️ + nome da música, com uma barra de
/// progresso fina.
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
  Duration _duration = Duration.zero;
  bool _loading = false;
  bool _playing = false;

  /// Um único player ativo no app inteiro — tocar uma música para a outra.
  static AudioPlayer? _activePlayer;

  @override
  void initState() {
    super.initState();
    // A duração conhecida (o trecho) já desenha a barra antes de tocar.
    _duration = Duration(
      milliseconds: widget.music.durationMs.clamp(0, 1 << 31),
    );
  }

  @override
  void didUpdateWidget(covariant ProfileMusicBar old) {
    super.didUpdateWidget(old);
    // Trocou a música → o player antigo não representa mais esta barra.
    if (old.music.audioUrl != widget.music.audioUrl) {
      _teardown();
      _duration = Duration(
        milliseconds: widget.music.durationMs.clamp(0, 1 << 31),
      );
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
      if (mounted) setState(() => _position = p);
    });
    _stateSub ??= player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state.playing);
      if (state.processingState == ProcessingState.completed) {
        // Fim do trecho: volta ao início e para (um trecho curto reiniciando
        // sozinho em loop seria irritante).
        player.pause();
        player.seek(Duration.zero);
        if (mounted) {
          setState(() {
            _position = Duration.zero;
            _playing = false;
          });
        }
      }
    });
    _durSub ??= player.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
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
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            // Botão ⏯️ desenhado — nunca um emoji colorido do sistema.
            InkWell(
              onTap: _toggle,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.electricBlue.withValues(alpha: 0.14),
                  border: Border.all(
                    color: AppColors.electricBlue.withValues(alpha: 0.55),
                  ),
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
        ),
        // Barra fina de progresso do trecho.
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 2,
            backgroundColor: AppColors.holographicBlue.withValues(alpha: 0.25),
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.electricBlue),
          ),
        ),
      ],
    );
  }
}
