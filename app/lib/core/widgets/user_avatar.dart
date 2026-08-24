import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../data/api_config.dart';

/// User avatar. Shows the remote profile photo when [imageUrl] is set
/// (served by the API); otherwise falls back to deterministic
/// initials-on-gradient built from the seed/name.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.seed,
    this.imageUrl,
    this.size = 44,
    this.ring = false,
  });

  final String name;
  final String? seed;

  /// Remote profile photo URL (absolute or API-relative `/static/...`).
  final String? imageUrl;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      shape: BoxShape.circle,
      gradient: imageUrl == null
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _palette(seed ?? name),
            )
          : null,
      color: imageUrl != null ? AppColors.nightBlue : null,
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
    );

    if (imageUrl != null) {
      return Container(
        width: size,
        height: size,
        decoration: decoration,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: ApiConfig.resolveUrl(imageUrl!),
            fit: BoxFit.cover,
            width: size,
            height: size,
            placeholder: (_, __) => const SizedBox.shrink(),
            errorWidget: (_, __, ___) => _initialsChild(),
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: decoration,
      alignment: Alignment.center,
      child: _initialsChild(),
    );
  }

  Widget _initialsChild() => Text(
        _initials(name),
        style: TextStyle(
          color: AppColors.techWhite,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.38,
        ),
      );

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
