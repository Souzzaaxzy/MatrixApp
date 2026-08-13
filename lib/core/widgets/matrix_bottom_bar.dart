import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import 'glow_container.dart';

/// Destination model for the bottom navigation bar.
class MatrixNavDestination {
  const MatrixNavDestination({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Persistent futuristic bottom navigation bar.
///
/// Highlights the active item with neon blue and a glow.
class MatrixBottomBar extends StatelessWidget {
  const MatrixBottomBar({
    super.key,
    required this.currentIndex,
    required this.destinations,
    required this.onTap,
  });

  final int currentIndex;
  final List<MatrixNavDestination> destinations;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.navBarBackground,
        border: Border(
          top: BorderSide(
            color: AppColors.primaryBlue,
            width: AppDimensions.borderWidthThin,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spaceSm,
            vertical: AppDimensions.spaceXs,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(destinations.length, (i) {
              final active = i == currentIndex;
              return _NavButton(
                destination: destinations[i],
                active: active,
                onTap: () => onTap(i),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.destination,
    required this.active,
    required this.onTap,
  });

  final MatrixNavDestination destination;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.electricBlue : AppColors.holographicBlue;
    return Expanded(
      child: Semantics(
        label: destination.label,
        button: true,
        selected: active,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppDimensions.spaceXs,
              horizontal: AppDimensions.spaceXs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: active
                      ? GlowContainer(
                          key: ValueKey('active-${destination.label}'),
                          glow: Glow.small,
                          color: AppColors.glowSmall,
                          background: AppColors.primaryBlue.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(AppDimensions.radiusMd),
                          padding: const EdgeInsets.all(AppDimensions.spaceSm),
                          child: Icon(destination.activeIcon, color: color, size: 22),
                        )
                      : Padding(
                          key: ValueKey('idle-${destination.label}'),
                          padding: const EdgeInsets.all(AppDimensions.spaceSm),
                          child: Icon(destination.icon, color: color, size: 22),
                        ),
                ),
                Text(
                  destination.label,
                  style: AppTextStyles.caption.copyWith(
                    color: color,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
