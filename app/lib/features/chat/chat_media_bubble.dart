import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../data/api_config.dart';
import '../feed/post_video_preview.dart';
import '../post/video_player_screen.dart';
import '../../models/conversation.dart';

/// Compact chat media bubble — used by BOTH private conversations and groups.
///
/// * [ChatMessage.isImage]: renders a responsive, crisp image (fills width,
///   preserves aspect, bounded height) and opens an enlarged viewer on tap.
/// * [ChatMessage.isVideo]: renders a muted short autoplay preview (reusing
///   the post Video preview) with a play overlay; tapping opens the fullscreen
///   player (same player used by posts — no second player stack).
class ChatMediaBubble extends StatelessWidget {
  const ChatMediaBubble(
      {super.key, required this.message, this.maxWidth = 260});

  final ChatMessage message;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final constrained = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: _content(context),
    );
    return constrained;
  }

  Widget _content(BuildContext context) {
    if (message.isSticker && message.stickerUrl != null) {
      return _StickerBubble(url: ApiConfig.resolveUrl(message.stickerUrl!));
    }
    if (message.isImage && message.imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        child: GestureDetector(
          onTap: () => _openImageViewer(context),
          child: _ResponsiveChatImage(
              url: ApiConfig.resolveUrl(message.imageUrl!)),
        ),
      );
    }
    if (message.isVideo && message.videoUrl != null) {
      return PostVideoPreview(
        videoUrl: ApiConfig.resolveUrl(message.videoUrl!),
        active: true,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VideoPlayerScreen(
              videoUrl: ApiConfig.resolveUrl(message.videoUrl!),
            ),
          ),
        ),
        maxHeightFraction: 0.5,
      );
    }
    return const SizedBox.shrink();
  }

  void _openImageViewer(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _ImageViewer(url: ApiConfig.resolveUrl(message.imageUrl!)),
      ),
    );
  }
}

/// Fills available width, keeps the natural aspect ratio, bounded height —
/// the SAME responsive logic used for post photos so chat images look sharp.
class _ResponsiveChatImage extends StatefulWidget {
  const _ResponsiveChatImage({required this.url});

  final String url;

  @override
  State<_ResponsiveChatImage> createState() => _ResponsiveChatImageState();
}

class _ResponsiveChatImageState extends State<_ResponsiveChatImage> {
  double? _aspectRatio;

  @override
  Widget build(BuildContext context) {
    final safeArea = MediaQuery.paddingOf(context);
    final availableHeight =
        MediaQuery.sizeOf(context).height - safeArea.top - safeArea.bottom;
    final minHeight = availableHeight * 0.15;
    final maxHeight = availableHeight * 0.5;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final ratio = _aspectRatio ?? (4 / 3);
        final height = (width / ratio).clamp(minHeight, maxHeight);
        return SizedBox(
          width: width,
          height: height,
          child: CachedNetworkImage(
            imageUrl: widget.url,
            fit: BoxFit.cover,
            placeholder: (_, __) => _placeholder(),
            errorWidget: (_, __, ___) => _placeholder(),
          ),
        );
      },
    );
  }

  Widget _placeholder() =>
      Container(color: AppColors.nightBlue, alignment: Alignment.center);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read the intrinsic ratio once via a side listener (like posts).
    final provider = CachedNetworkImageProvider(widget.url);
    final stream = provider.resolve(ImageConfiguration.empty);
    ImageStreamListener? listener;
    listener = ImageStreamListener((ImageInfo info, bool sync) {
      final img = info.image;
      final r = img.width > 0 && img.height > 0
          ? (img.width / img.height).clamp(0.5, 3.0).toDouble()
          : null;
      info.dispose();
      if (r != null && mounted && _aspectRatio != r) {
        setState(() => _aspectRatio = r);
      }
      stream.removeListener(listener!);
    }, onError: (Object _, StackTrace? __) {
      stream.removeListener(listener!);
    });
    stream.addListener(listener);
  }
}

/// A sticker message — rendered DIRECTLY as the image, no text bubble.
/// Sized like modern messaging apps: large but bounded to the chat width.
class _StickerBubble extends StatelessWidget {
  const _StickerBubble({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final mediaWidth = MediaQuery.sizeOf(context).width;
    final maxW =
        (mediaWidth * 0.5).clamp(140.0, 240.0).toDouble();
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxW,
        maxHeight: maxW * 1.1,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          placeholder: (_, __) => Container(
            width: maxW,
            height: maxW,
            color: AppColors.nightBlue,
            child: const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0xFF008CFF),
                ),
              ),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            width: maxW,
            height: maxW * 0.8,
            color: AppColors.nightBlue,
            child: const Icon(
              Icons.broken_image_outlined,
              color: Color(0xFF008CFF),
              size: 34,
            ),
          ),
        ),
      ),
    );
  }
}

/// Enlarged image viewer (tap media → full image with zoom via InteractiveViewer).
class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 4,
                child: CachedNetworkImage(
                  imageUrl: url,
                  placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(color: Color(0xFF008CFF)),
                  ),
                  errorWidget: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: Colors.white, size: 48),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
