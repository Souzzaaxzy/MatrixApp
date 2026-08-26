import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/utils/frame_assets.dart';
import '../../models/cosmetic_item.dart';

/// Avatar with an optional equipped frame around it.
///
///   FramedAvatar            ← frame slot (AVATAR_FRAME)
///    └── child (UserAvatar) ← the avatar itself, never knows about frames
///
/// [frame] is the equipped [CosmeticItem] for the AVATAR_FRAME slot, or
/// null for the default look. The frame sprite is BUNDLED with the APK — the
/// server sends a key (`frames/coroa`) and [frameAssetPath] resolves it to
/// the local `assets/frames/coroa.png`. Rendering is fully offline: no
/// network, no Google Drive dependency.
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

  @override
  Widget build(BuildContext context) {
    final path = frameAssetPath(frame?.assetUrl);
    if (frame == null) {
      return SizedBox(width: size, height: size, child: child);
    }
    final padding = size * 0.08;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(padding: EdgeInsets.all(padding), child: child),
          if (path != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Image.asset(
                  path,
                  fit: BoxFit.contain,
                  // A missing/malformed sprite must never hide the avatar or
                  // crash — fall back to the default look.
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
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
