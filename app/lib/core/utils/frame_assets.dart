import 'package:flutter/painting.dart' show AssetImage;

/// Resolves a server-owned frame asset key into the path of the matching
/// sprite bundled with the APK.
///
/// The server sends `frameAsset` as `frames/<name>` (e.g. `frames/coroa`) —
/// the SAME key the catalog row was seeded with. The sprite lives at
/// `assets/frames/<name>.png` in this project, so that key maps straight to
/// the bundled file. Rendering a frame therefore NEVER requires the network
/// or the Google Drive: everything is local and works offline.
///
/// Returns null for any key the APK does not bundle a sprite for (safe
/// fallback → "Nenhuma").
String? frameAssetPath(String? frameAsset) {
  if (frameAsset == null) return null;
  final trimmed = frameAsset.trim();
  if (trimmed.isEmpty) return null;

  // Accept both `frames/coroa` and a bare `coroa`; ignore anything that is a
  // full URL or path traversal — only the local bundle key is ever rendered.
  final name = trimmed.startsWith('frames/')
      ? trimmed.substring('frames/'.length)
      : trimmed;
  if (name.contains('/') || name.contains('..') || name.contains(':')) {
    return null;
  }

  final key = name.replaceAll(RegExp(r'\.png$'), '');
  // Guard against empty/invalid keys.
  if (key.isEmpty) return null;

  return 'assets/frames/$key.png';
}

/// An [AssetImage] for a bundled frame sprite, or null when the key does
/// not map to a local asset.
AssetImage? frameAssetImage(String? frameAsset) {
  final path = frameAssetPath(frameAsset);
  return path == null ? null : AssetImage(path);
}