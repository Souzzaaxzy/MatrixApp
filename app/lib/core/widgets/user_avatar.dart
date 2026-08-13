import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

/// Deterministic avatar built from a seed string (initials on gradient).
///
/// No network dependency — fully offline for Phase 1.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.seed,
    this.size = 44,
    this.ring = false,
  });

  final String name;
  final String? seed;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    final palette = _palette(seed ?? name);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette,
        ),
        border: ring
            ? Border.all(color: AppColors.electricBlue, width: 1.5)
            : null,
        boxShadow: ring
            ? [
                BoxShadow(
                  color: AppColors.glowSmall,
                  blurRadius: AppDimensions.glowSmallBlur,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: AppColors.techWhite,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.38,
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }

  List<Color> _palette(String value) {
    final bytes = utf8.encode(value);
    var sum = 0;
    for (final b in bytes) {
      sum = (sum + b) % 360;
    }
    final hue = sum.toDouble();
    return [
      HSLColor.fromAHSL(1, hue, 0.7, 0.45).toColor(),
      HSLColor.fromAHSL(1, (hue + 40) % 360, 0.8, 0.30).toColor(),
    ];
  }
}
