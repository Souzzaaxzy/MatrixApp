import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

/// Responsive post photo (Instagram-like preview).
///
/// Fills the available width (the post's width), preserves the image's
/// natural aspect ratio, and constrains the height to a sane band so a very
/// tall photo never swallows the whole feed:
///   * min height: a small square-ish thumbnail floor;
///   * max height: ~70% of the viewport height (photos can still be seen
///     in full on the detail screen).
///
/// While the real image decodes, a placeholder keeps the layout stable. The
/// image is cached by [CachedNetworkImage] (the app's existing cache) so the
/// bytes are never re-downloaded.
class ResponsivePostImage extends StatefulWidget {
  const ResponsivePostImage({
    super.key,
    required this.imageUrl,
    this.borderRadius = AppDimensions.radiusMd,
    this.maxHeightFraction = 0.7,
    this.minHeightFraction = 0.2,
  });

  final String imageUrl;
  final double borderRadius;
  final double maxHeightFraction;
  final double minHeightFraction;

  @override
  State<ResponsivePostImage> createState() => _ResponsivePostImageState();
}

class _ResponsivePostImageState extends State<ResponsivePostImage> {
  double? _aspectRatio;

  @override
  Widget build(BuildContext context) {
    final safeArea = MediaQuery.paddingOf(context);
    final availableHeight =
        MediaQuery.sizeOf(context).height - safeArea.top - safeArea.bottom;
    final minHeight = availableHeight * widget.minHeightFraction;
    final maxHeight = availableHeight * widget.maxHeightFraction;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          // Compute the display height from the natural aspect ratio (when
          // known); fall back to a 4:3 placeholder while decoding.
          final ratio = _aspectRatio ?? (4 / 3);
          final naturalHeight = (maxWidth / ratio).clamp(minHeight, maxHeight);
          return SizedBox(
            width: maxWidth,
            height: naturalHeight,
            child: CachedNetworkImage(
              imageUrl: widget.imageUrl,
              fit: BoxFit.fill,
              // Decode once to learn the true proportions; the cache serves
              // the bytes so this never re-downloads.
              imageBuilder: (context, imageProvider) {
                return _ResolvedImage(
                  imageProvider: imageProvider,
                  onResolved: (r) {
                    if (mounted && r != 0 && _aspectRatio != r) {
                      setState(() => _aspectRatio = r);
                    }
                  },
                );
              },
              placeholder: (context, _) => const _ImagePlaceholder(
                icon: Icons.broken_image_outlined,
              ),
              errorWidget: (context, _, __) => const _ImagePlaceholder(
                icon: Icons.image_not_supported_outlined,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Renders the image with the app's existing cache (via the [Image] widget)
/// AND reads its intrinsic dimensions on a SIDE listener so the parent can
/// size the box to the real proportion. The listener disposes its own
/// decoded copy (each stream receives an owned image clone), never the one
/// the renderer is using.
class _ResolvedImage extends StatefulWidget {
  const _ResolvedImage({required this.imageProvider, required this.onResolved});

  final ImageProvider imageProvider;
  final ValueChanged<double> onResolved;

  @override
  State<_ResolvedImage> createState() => _ResolvedImageState();
}

class _ResolvedImageState extends State<_ResolvedImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant _ResolvedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) {
      _stop();
      _listen();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The parent re-runs `imageBuilder` on every setState (aspect ratio
    // change). The provider instance is stable per cache entry, so re-resolve
    // is harmless, but skip duplicate listeners for the SAME provider.
    if (_stream == null) _listen();
  }

  void _listen() {
    final stream = widget.imageProvider.resolve(ImageConfiguration.empty);
    _stream = stream;
    final listener = ImageStreamListener(
      (ImageInfo imageInfo, bool synchronousCall) {
        final img = imageInfo.image;
        final w = img.width.toDouble();
        final h = img.height.toDouble();
        // The info owns its own decoded copy (the renderer uses a separate
        // one); disposing it here is required to avoid leaking the frame.
        imageInfo.dispose();
        if (mounted && w > 0 && h > 0) widget.onResolved(w / h);
      },
      onError: (Object error, StackTrace? stackTrace) {
        // Ignore: the parent falls back to the placeholder ratio.
      },
    );
    stream.addListener(listener);
    _listener = listener;
  }

  void _stop() {
    _stream?.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Image(
      image: widget.imageProvider,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
      // The surrounding SizedBox matches the natural proportion, so fill
      // stretches exactly onto that box without deformation.
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.cardSurface,
      alignment: Alignment.center,
      child: Icon(icon, color: AppColors.deepBlue, size: 40),
    );
  }
}
