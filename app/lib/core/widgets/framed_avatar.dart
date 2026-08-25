import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../data/api_config.dart';
import '../../models/cosmetic_item.dart';

/// Avatar with an optional equipped frame around it.
///
/// Structure prepared for the real cosmetic assets:
///
///   FramedAvatar            ← frame slot (AVATAR_FRAME)
///    └── child (UserAvatar) ← the avatar itself, never knows about frames
///
/// [frame] is the equipped [CosmeticItem] for the AVATAR_FRAME slot, or
/// null for the default look. Asset-based frames render as an overlay
/// image; asset-less frames (catalog entries not yet shipped with art)
/// render a neon ring placeholder so the slot already "exists" visually.
class FramedAvatar extends StatelessWidget {
  const FramedAvatar({
    super.key,
    required this.child,
    this.frame,
    this.size = 96,
  });

  /// The avatar widget (usually a [UserAvatar]) rendered under the frame.
  final Widget child;

  /// Equipped frame cosmetic, or null for the default avatar look.
  final CosmeticItem? frame;

  /// Diameter of the avatar area. The frame adds padding around it.
  final double size;

  bool get _hasRemoteAsset =>
      frame != null &&
      (frame!.assetUrl.startsWith('http') || frame!.assetUrl.startsWith('/'));

  @override
  Widget build(BuildContext context) {
    if (frame == null) {
      return SizedBox(width: size, height: size, child: child);
    }
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(padding: const EdgeInsets.all(6), child: child),
          if (_hasRemoteAsset)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: ApiConfig.resolveUrl(frame!.assetUrl),
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) => const _NeonFramePlaceholder(),
                placeholder: (_, __) => const _NeonFramePlaceholder(),
              ),
            )
          else
            const Positioned.fill(child: _NeonFramePlaceholder()),
        ],
      ),
    );
  }
}

/// Placeholder ring for frames whose art asset is not shipped yet. Keeps
/// the MATRIX neon identity while real frame sprites don't exist.
class _NeonFramePlaceholder extends StatelessWidget {
  const _NeonFramePlaceholder();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.electricBlue, width: 2),
          boxShadow: [
            BoxShadow(
              color: AppColors.glowMedium,
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}
