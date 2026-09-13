import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/hud_label.dart';

/// Fullscreen video player for Post videos.
///
/// Uses the single `video_player` plugin already in the app (NO second
/// player stack): play/pause, seek bar, elapsed/total, volume/mute and an
/// immersive fullscreen layout. The controller is created here and fully
/// disposed on exit so no player keeps running in the background.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.videoUrl});

  /// Resolved absolute URL (ApiConfig.resolveUrl already applied).
  final String videoUrl;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _started = true);
      // Autoplay on open with audio (user explicitly tapped the video).
      _controller.play();
      _controller.setLooping(false);
    }).catchError((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível carregar o vídeo.')),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours > 0 ? '${d.inHours}:' : '';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final backing = VideoScaffold(
      videoUrl: widget.videoUrl,
      child: _content(),
    );
    return backing;
  }

  Widget _content() {
    if (!_started) {
      return const Center(
        child: HudLabel(text: 'CARREGANDO...', dot: true),
      );
    }
    final size = _controller.value.size;
    final aspect = size.isEmpty
        ? 16 / 9
        : (size.width / size.height).clamp(0.5, 2.0).toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: aspect,
          child: GestureDetector(
            onTap: () => setState(() {
              _controller.value.isPlaying
                  ? _controller.pause()
                  : _controller.play();
            }),
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(_controller),
                if (!_controller.value.isPlaying)
                  Icon(Icons.play_circle_fill_rounded,
                      color: AppColors.techWhite.withValues(alpha: 0.85),
                      size: 72),
              ],
            ),
          ),
        ),
        _controls(),
      ],
    );
  }

  Widget _controls() {
    if (!_started) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _controller.value.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: AppColors.holographicBlue,
            ),
            onPressed: () => setState(() {
              _controller.value.isPlaying
                  ? _controller.pause()
                  : _controller.play();
            }),
          ),
          Expanded(
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _controller,
              builder: (context, value, _) {
                final pos = value.position;
                final dur = value.duration;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Slider(
                      value: dur.inMilliseconds == 0
                          ? 0
                          : pos.inMilliseconds
                              .clamp(0, dur.inMilliseconds)
                              .toDouble(),
                      max: dur.inMilliseconds == 0
                          ? 1
                          : dur.inMilliseconds.toDouble(),
                      onChanged: (v) {
                        final d = Duration(milliseconds: v.toInt());
                        _controller.seekTo(d);
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_fmt(pos), style: _tick()),
                        Text(_fmt(dur), style: _tick()),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              final muted = value.volume == 0;
              return IconButton(
                icon: Icon(
                  muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: AppColors.holographicBlue,
                ),
                onPressed: () => _controller.setVolume(muted ? 1 : 0),
              );
            },
          ),
        ],
      ),
    );
  }

  TextStyle _tick() =>
      AppTextStyles.caption.copyWith(fontSize: 10, color: AppColors.techWhite);
}

/// Immersive black scaffold with a back affordance — used standalone so the
/// player always gets the full screen regardless of the caller's route.
class VideoScaffold extends StatelessWidget {
  const VideoScaffold({super.key, required this.videoUrl, required this.child});

  final String videoUrl;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(child: child),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                icon:
                    Icon(Icons.arrow_back_rounded, color: AppColors.techWhite),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
