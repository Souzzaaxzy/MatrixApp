import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

/// Muted, short, autoplay preview of a Post video inside the feed.
///
/// Behavior (WhatsApp/Instagram-like):
///  * shows the video COVER ([thumbnailUrl]) immediately — no empty space,
///    no indefinite spinner — with a play badge;
///  * if a cover is configured, the player is NOT spun up for the preview
///    (saves data/CPU); tapping still opens the fullscreen player;
///  * without a cover, it autoplays MUTED and only while visible
///    (scroll-aware), looping a few seconds;
///  * a play overlay marks it clearly as a video;
///  * tapping opens the fullscreen player;
///  * at most ONE autoplay preview at a time — the feed passes a single
///    "active post id" via [active].
class PostVideoPreview extends StatefulWidget {
  const PostVideoPreview({
    super.key,
    required this.videoUrl,
    required this.active,
    required this.onTap,
    this.thumbnailUrl,
    this.maxHeightFraction = 0.7,
    this.minHeightFraction = 0.2,
  });

  /// Resolved absolute video URL.
  final String videoUrl;

  /// Resolved absolute cover/thumbnail URL (may be null for old videos).
  final String? thumbnailUrl;
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
    // With a cover there is no need to spin up the player for the preview
    // (saves data/CPU) — the cover is shown with a play badge instead.
    if (widget.thumbnailUrl != null) return;
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..setVolume(0) // live preview is ALWAYS muted
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
                  if (widget.thumbnailUrl != null)
                    // Video COVER — crisp image with a play badge, no player.
                    CachedNetworkImage(
                      imageUrl: widget.thumbnailUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          const _CoverFallback(),
                      errorWidget: (_, __, ___) =>
                          const _CoverFallback(),
                    )
                  else if (_initialized && _controller != null)
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

/// Neutral placeholder behind the play badge while the cover loads (or as a
/// fallback when the cover fails to load).
class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return Container(color: AppColors.cardSurface);
  }
}
