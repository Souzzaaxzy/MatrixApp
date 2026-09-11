import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// Result of an attempted gallery pick. Success carries the picked file
/// (already resized/compressed by [ImagePicker]); failure carries a
/// user-facing message so callers never hang or crash on a denial.

class GalleryPickResult {
  const GalleryPickResult._({this.file, this.error, this.cancelled = false});

  const GalleryPickResult.success(XFile file) : this._(file: file);
  const GalleryPickResult.cancelled() : this._(cancelled: true);
  const GalleryPickResult.failure(String error) : this._(error: error);

  /// The picked image (non-null only on success).
  final XFile? file;

  /// A ready-to-show error message (non-null only on failure).
  final String? error;

  /// True when the user simply cancelled the picker (no message needed).
  final bool cancelled;

  bool get isSuccess => file != null;
}

/// Unified device-gallery image picker.

/// Handles the runtime permission for the device photo library (Android 13+
/// uses the granular `READ_MEDIA_IMAGES`;older versions fall back to the
/// legacy READ_EXTERNAL_STORAGE via permission_handler)and then picks a
/// single image with mild compression so MEMORY stays bounded. Denials
/// return a typed [GalleryPickResult.failure] — the caller reacts without
/// blocking the screen.
///
/// The returned [XFile] is already scaled down (max 1600px) and JPEG
/// compressed (quality ~85) by image_picker, which avoids shipping giant
/// original photos around the app.
Future<GalleryPickResult> pickGalleryImage({
  int imageQuality = 85,
  double maxWidth = 1600,
  double maxHeight = 1600,
}) async {
  if (kIsWeb) {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: imageQuality,
      );
      return file == null
          ? const GalleryPickResult.cancelled()
          : GalleryPickResult.success(file);
    } catch (_) {
      return const GalleryPickResult.failure('Não foi possível abrir a galeria.');
    }
  }

  if (!kIsWeb && !Platform.isIOS) {
    // permission_handler maps the right OS permission: it requests
    // READ_MEDIA_IMAGES (Android 13+ an no-op on 12-) ORthe
    // legacy READ_EXTERNAL_STORAGE (<=12) automatically. On a
    // denial we still check the other media permission before giving up —
    // on some OEM builds one of them is granted while the other reports
    // denied.
    final photos = await Permission.photos.request();
    final storage = await Permission.storage.request();
    final photosOk = photos.isGranted || photos.isLimited;
    final storageOk = storage.isGranted || storage.isLimited;
    if (!photosOk && !storageOk) {
      return GalleryPickResult.failure(
        'Permissão para acessar a galeria negada. '
        'Conceda acesso nas configurações para escolher imagens.',
      );
    }
  }

  try {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: imageQuality,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
    if (file == null) {
      return const GalleryPickResult.cancelled();
    }
    return GalleryPickResult.success(file);
  } catch (_) {
    return const GalleryPickResult.failure('Não foi possível abrir a galeria.');
  }
}
