import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';

/// Limite de bytes aceitado para un sticker importado (mismo cap del servidor:
/// MAX_UPLOAD_BYTES = 5 MB).
const int kMaxStickerImportBytes = 5 * 1024 * 1024;

/// Formatos de imagen aceptados por el sistema de stickers (PNG/WebP/JPEG).
enum StickerImageKind { png, webp, jpeg }

/// Resultado de la validación de un archivo compartido como figurita.
class ValidatedStickerFile {
  const ValidatedStickerFile({
    required this.file,
    required this.kind,
    required this.width,
    required this.height,
    required this.sha256,
  });

  /// Archivo local ya copiado al caché del app.
  final File file;

  final StickerImageKind kind;
  final int width;
  final int height;

  /// SHA-256 (hex) de los bytes — usado por el servidor para deduplicar.
  final String sha256;

  int get size => file.lengthSync();
}

/// Valida el contenido de un archivo compartido. NUNCA confía en el MIME
/// declarado por el origen ni en la extensión: analiza los magic bytes reales
/// y las dimensiones de la imagen.
class StickerImportValidator {
  StickerImportValidator._();

  static bool isPng(Uint8List bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E &&
      bytes[3] == 0x47 && bytes[4] == 0x0D && bytes[5] == 0x0A &&
      bytes[6] == 0x1A && bytes[7] == 0x0A;

  static bool isJpeg(Uint8List bytes) =>
      bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;

  static bool isWebp(Uint8List bytes) =>
      bytes.length >= 12 &&
      bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 &&
      bytes[3] == 0x46 && bytes[8] == 0x57 && bytes[9] == 0x45 &&
      bytes[10] == 0x42 && bytes[11] == 0x50;

  static StickerImageKind? _detectKind(Uint8List bytes) {
    if (isPng(bytes)) return StickerImageKind.png;
    if (isWebp(bytes)) return StickerImageKind.webp;
    if (isJpeg(bytes)) return StickerImageKind.jpeg;
    return null;
  }

  /// Valida [file] como figurita. Retorna el objeto validado o `null`
  /// (inválido). Archivos sobre el límite, vacíos o no-imagen son rechazados.
  static Future<ValidatedStickerFile?> validate(
    File file, {
    Map<String, String>? invalidReasons,
  }) async {
    final reason = _rejectReason(file);
    if (reason != null) {
      invalidReasons?[file.path] = reason;
      return null;
    }
    try {
      final bytes = await file.readAsBytes();
      final kind = _detectKind(bytes);
      if (kind == null) {
        invalidReasons?[file.path] =
            'Formato no soportado. Envía PNG, WebP o JPEG.';
        return null;
      }
      final size = await decodeImageFromList(bytes);
      final width = size.width;
      final height = size.height;
      size.dispose();
      if (width <= 0 || height <= 0) {
        invalidReasons?[file.path] = 'Imagen corrupta o sin dimensiones válidas.';
        return null;
      }
      final sha = sha256.convert(bytes).toString();
      return ValidatedStickerFile(
        file: file,
        kind: kind,
        width: width,
        height: height,
        sha256: sha,
      );
    } catch (_) {
      invalidReasons?[file.path] = 'No se pudo leer esta imagen.';
      return null;
    }
  }

  static String? _rejectReason(File file) {
    if (!file.existsSync()) {
      return 'Archivo no encontrado.';
    }
    final size = file.lengthSync();
    if (size <= 0) {
      return 'Archivo vacío.';
    }
    if (size > kMaxStickerImportBytes) {
      return 'Imagen con más de 5 MB — rechazada.';
    }
    return null;
  }
}