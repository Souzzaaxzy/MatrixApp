import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

/// Muted, short, autoplay preview of a Post video inside the feed.
///
/// Behavior (WhatsApp/Instagram-like):
///  * autoplays MUTED and only while the widget is visible (scroll-aware);
///  * plays just a few seconds (loops the short clip, no audio);
///  * a play overlay marks it clearly as a video;
///  * tapping opens the fullscreen player;
///  * at most ONE preview plays at a time — the feed passes a single
///    "active post id" via [active]; when this post is not the active one
///    (or is off-screen), the controller pauses.
///
/// The feed owns the [VideoPlayerController] lifecycle through an optional
/// [controller]: pass it to keep a shared registry so scrolling pauses the
/// previous preview exactly like modern feeds.
class PostVideoPreview extends StatefulWidget {
  const PostVideoPreview({
    super.key,
    required this.videoUrl,
    required this.active,
    required this.onTap,
    this.maxHeightFraction = 0.7,
    this.minHeightFraction = 0.2,
  });

  /// Resolved absolute video URL.
  final String videoUrl;
  final bool active;
  final VoidCallback onTap;
  final double maxHeightFraction;
  final double minHeightFraction;

  @override
  State<PostVideoPreview> createState() => _PostVideoPreviewState();
}

class _PostVideoPreviewState extends State<PostVideoPreview> {
  VideoPlayerController? _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  void _createController() {
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..setVolume(0) // preview is ALWAYS muted
      ..setLooping(true);
    _controller!.initialize().then((_) {
      if (!mounted) return;
      setState(() => _initialized = true);
      _updatePlayback();
    }).catchError((_) {
      // Video failed to load — keep the play overlay; tapping still opens
      // the full player (which shows its own error).
    });
  }

  @override
  void didUpdateWidget(covariant PostVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _controller?.dispose();
      _initialized = false;
      _createController();
    } else {
      _updatePlayback();
    }
  }

  /// Pause when not visible/active; play (muted) when visible+active.
  void _updatePlayback() {
    if (!mounted || !_initialized) return;
    final controller = _controller;
    if (controller == null) return;
    if (widget.active && controller.value.isInitialized) {
      if (!controller.value.isPlaying) controller.play();
    } else {
      if (controller.value.isPlaying) controller.pause();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeArea = MediaQuery.paddingOf(context);
    final availableHeight =
        MediaQuery.sizeOf(context).height - safeArea.top - safeArea.bottom;
    final minHeight = availableHeight * widget.minHeightFraction;
    final maxHeight = availableHeight * widget.maxHeightFraction;
    final isActive = widget.active;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final ratio =
              _initialized ? _aspectOf(_controller?.value.size) : (16 / 9);
          final height = (maxWidth / ratio).clamp(minHeight, maxHeight);
          return SizedBox(
            width: maxWidth,
            height: height,
            child: GestureDetector(
              onTap: widget.onTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_initialized && _controller != null)
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _controller!.value.size.width,
                        height: _controller!.value.size.height,
                        child: VideoPlayer(_controller!),
                      ),
                    )
                  else
                    Container(color: AppColors.cardSurface),
                  // Play badge (video indicator) always visible.
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isActive
                            ? Icons.video_library_rounded
                            : Icons.play_arrow_rounded,
                        color: AppColors.techWhite,
                        size: 30,
                      ),
                    ),
                  ),
                  // Muted badge (subtle) to signal autoplay is silent.
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Icon(Icons.volume_off_rounded,
                        color: AppColors.techWhite.withValues(alpha: 0.7),
                        size: 16),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  double _aspectOf(Size? size) {
    if (size == null || size.isEmpty) return 16 / 9;
    return (size.width / size.height).clamp(0.5, 2.0).toDouble();
  }
}
