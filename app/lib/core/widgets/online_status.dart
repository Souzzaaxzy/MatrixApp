import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';

/// Online/offline status of a user, as reported by the SERVER.
///
/// The state is never guessed locally: the backend owns the live sockets, so
/// a user counts as online only while MATRIX is actually open in front of
/// them. Leaving the app flips them offline.
///
/// Two presentations, one source of truth:
///  * [OnlineDot] — the small dot placed next to a nickname (private chat).
///  * [OnlineStatusLabel] — the "online" / "offline" word.
class OnlineDot extends StatelessWidget {
  const OnlineDot({
    super.key,
    required this.online,
    this.size = 8,
    this.semanticLabel,
  });

  final bool online;
  final double size;

  /// Optional override for the accessibility label.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final color = online ? AppColors.success : AppColors.holographicBlue;
    return Semantics(
      label: semanticLabel ?? (online ? 'Online' : 'Offline'),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          // Online gets a soft glow so it reads at a glance on the dark
          // header; offline stays a flat, quiet dot.
          boxShadow: online
              ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)]
              : null,
        ),
      ),
    );
  }
}

/// The "online" / "offline" word, tinted to match [OnlineDot]. Used where
/// there is room for the label (private chat header).
class OnlineStatusLabel extends StatelessWidget {
  const OnlineStatusLabel({super.key, required this.online, this.fontSize = 11});

  final bool online;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      online ? 'online' : 'offline',
      style: AppTextStyles.caption.copyWith(
        fontSize: fontSize,
        color: online ? AppColors.success : AppColors.holographicBlue,
        fontWeight: online ? FontWeight.w600 : FontWeight.w500,
      ),
    );
  }
}
