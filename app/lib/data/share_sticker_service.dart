import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Un archivo de imagen recibido por el compartir nativo de Android.
///
/// Ya fue copiado por [MainActivity] (Kotlin) al caché privado del app; el
/// Flutter solo lee el archivo local, valida y decide la importación.
class SharedStickerFile {
  const SharedStickerFile({
    required this.path,
    required this.name,
    required this.mime,
    required this.size,
  });

  factory SharedStickerFile.fromMap(Map<String, dynamic> map) {
    final path = (map['path'] as String?) ?? '';
    return SharedStickerFile(
      path: path,
      name: (map['name'] as String?)?.isNotEmpty == true
          ? map['name'] as String
          : path.split('/').last,
      mime: (map['mime'] as String?) ?? '',
      size: ((map['size'] as num?) ?? 0).toInt(),
    );
  }

  final String path;
  final String name;

  /// MIME declarado por el origen (p. ej. image/png). Es solo una pista — la
  /// validación real ocurre sobre los bytes del archivo.
  final String mime;
  final int size;

  bool get exists => File(path).existsSync();
}

/// Puente hacia el compartir nativo de Android (ACTION_SEND /
/// ACTION_SEND_MULTIPLE).
///
/// Recibe los archivos copiados por [MainActivity] (MethodChannel
/// `matrix.share/stickers`) y los expone para la UI. Dos caminos:
///  * app recién abierto por el share → consulta [initialFiles] (el nativo
///    conserva el contenido hasta que el Flutter lo pida);
///  * app ya abierto → el stream [onFiles] recibe el push del `onNewIntent`.
class ShareStickerService {
  ShareStickerService._();

  static final ShareStickerService instance = ShareStickerService._();

  static const MethodChannel _channel = MethodChannel('matrix.share/stickers');

  /// Evento emitido cuando Android entrega nuevos archivos compartidos
  /// mientras el app está en ejecución.
  final StreamController<List<SharedStickerFile>> _controller =
      StreamController<List<SharedStickerFile>>.broadcast();

  Stream<List<SharedStickerFile>> get onFiles => _controller.stream;

  bool _listening = false;

  /// Último lote recibido (no consumido). Usado por la pantalla de
  /// importación para leer lo que abrió el app o lo que llegó por push.
  List<SharedStickerFile>? _current;

  /// Los archivos actuales listos para importar (o `null`).
  Future<List<SharedStickerFile>?> currentFiles() async {
    final current = _current;
    if (current != null) return current;
    final initial = await initialFiles();
    if (initial != null) _current = initial;
    return initial;
  }

  /// Marca el lote actual como consumido (tras importar/cancelar) — evita
  /// reprocesar en la próxima reconstrucción de la pantalla.
  void clearCurrent() {
    _current = null;
  }

  /// Consulta los archivos que abrieron el app (share con proceso frío).
  Future<List<SharedStickerFile>?> initialFiles() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'initialSharedFiles',
      );
      final files = _normalize(raw);
      if (files != null) _current = files;
      return files;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // Entorno sin el canal nativo (p. ej. pruebas) — sin compartir.
      return null;
    }
  }

  /// Empieza a escuchar pushes de compartir (app ya abierto).
  void listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedStickers') {
        final raw = call.arguments as List<dynamic>?;
        final files = _normalize(raw);
        if (files != null && files.isNotEmpty) {
          _current = files;
          _controller.add(files);
        }
      }
      return null;
    });
  }

  List<SharedStickerFile>? _normalize(List<dynamic>? raw) {
    if (raw == null || raw.isEmpty) return null;
    final files = <SharedStickerFile>[];
    for (final item in raw) {
      if (item is Map<dynamic, dynamic>) {
        final map = Map<String, dynamic>.from(item);
        final file = SharedStickerFile.fromMap(map);
        if (file.path.isNotEmpty && file.exists) {
          files.add(file);
        }
      }
    }
    return files.isEmpty ? null : files;
  }
}