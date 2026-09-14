import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Un archivo de imagen recibido por el compartir nativo de Android.
///
/// Ya fue copiado por `MainActivity` (Kotlin) al caché privado del app; el
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

/// Origen del lote compartido.
enum SharedBatchKind {
  /// Imágenes sueltas (ACTION_SEND / ACTION_SEND_MULTIPLE).
  images,

  /// Un paquete de figuritas (`.wastickers`/ZIP) ya extraído por el nativo.
  pack,

  /// El contenido llegó pero no se pudo procesar (MIME/URI/formato).
  error,
}

/// Un lote de contenido recibido por el compartir nativo: imágenes sueltas o
/// un paquete completo, con sus metadatos (nombre/autor/capa) cuando existen.
class SharedStickerBatch {
  const SharedStickerBatch({
    required this.kind,
    required this.stickers,
    this.title = '',
    this.author = '',
    this.coverPath,
    this.origin = '',
    this.rejected = 0,
    this.error,
    this.batchId = '',
  });

  factory SharedStickerBatch.fromMap(Map<String, dynamic> map) {
    final raw = map['stickers'];
    final stickers = <SharedStickerFile>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final file = SharedStickerFile.fromMap(Map<String, dynamic>.from(item));
          if (file.path.isNotEmpty && file.exists) stickers.add(file);
        }
      }
    }
    final kindName = (map['kind'] as String?) ?? 'images';
    return SharedStickerBatch(
      kind: switch (kindName) {
        'pack' => SharedBatchKind.pack,
        'error' => SharedBatchKind.error,
        _ => SharedBatchKind.images,
      },
      stickers: stickers,
      title: (map['title'] as String?) ?? '',
      author: (map['author'] as String?) ?? '',
      coverPath: (map['coverPath'] as String?)?.isNotEmpty == true
          ? map['coverPath'] as String
          : null,
      origin: (map['origin'] as String?) ?? '',
      rejected: ((map['rejected'] as num?) ?? 0).toInt(),
      error: (map['error'] as String?)?.isNotEmpty == true
          ? map['error'] as String
          : null,
      batchId: (map['batchId'] as String?) ?? '',
    );
  }

  final SharedBatchKind kind;
  final List<SharedStickerFile> stickers;

  /// Nombre del paquete (solo `pack`; puede venir vacío → se usa un default).
  final String title;

  /// Autor/publisher del paquete (solo `pack`, puede venir vacío).
  final String author;

  /// Ruta local de la capa/ícono del paquete (solo `pack`, opcional).
  final String? coverPath;

  /// Paquete emisor (p. ej. com.whatsapp) — solo diagnóstico.
  final String origin;

  /// Cuántos archivos se descartaron (límites de tamaño/cantidad).
  final int rejected;

  /// Mensaje amigable cuando [kind] es [SharedBatchKind.error].
  final String? error;

  /// Identificador del lote — permite deduplicar reentregas del mismo share.
  final String batchId;
}

/// Puente hacia el compartir nativo de Android (ACTION_SEND /
/// ACTION_SEND_MULTIPLE / ACTION_VIEW).
///
/// Recibe los lotes preparados por `MainActivity` (MethodChannel
/// `matrix.share/stickers`) y los expone para la UI. Dos caminos:
///  * app recién abierto por el share → consulta [initialBatch] (el nativo
///    conserva el contenido hasta que el Flutter lo pida);
///  * app ya abierto → el stream [onBatches] recibe el push del `onNewIntent`.
class ShareStickerService {
  ShareStickerService._();

  static final ShareStickerService instance = ShareStickerService._();

  static const MethodChannel _channel = MethodChannel('matrix.share/stickers');

  /// Evento emitido cuando Android entrega un nuevo lote compartido mientras
  /// el app está en ejecución.
  final StreamController<SharedStickerBatch> _controller =
      StreamController<SharedStickerBatch>.broadcast();

  Stream<SharedStickerBatch> get onBatches => _controller.stream;

  bool _listening = false;

  /// Último lote recibido (no consumido). Usado por la pantalla de
  /// importación para leer lo que abrió el app o lo que llegó por push.
  SharedStickerBatch? _current;

  /// Id del último lote entregado — evita procesar dos veces el mismo share
  /// (push + consulta inicial tras una recreación de la Activity).
  String? _lastBatchId;

  /// El lote actual listo para importar (o `null`).
  Future<SharedStickerBatch?> currentBatch() async {
    final current = _current;
    if (current != null) return current;
    final initial = await initialBatch();
    if (initial != null) _current = initial;
    return initial;
  }

  /// Marca el lote actual como consumido (tras importar/cancelar) — evita
  /// reprocesar en la próxima reconstrucción de la pantalla.
  void clearCurrent() {
    _current = null;
  }

  /// Elimina los archivos temporales copiados por el nativo para el lote
  /// [paths] (o TODOS los del compartir cuando no se indica ninguno).
  ///
  /// El nativo copia a `<cacheDir>/shared_stickers`; `getTemporaryDirectory()`
  /// apunta a ese mismo `cacheDir` en Android. Nunca toca la colección del
  /// usuario — solo el contenido externo temporal.
  Future<void> cleanupTemporaries({List<String>? paths}) async {
    try {
      final root = Directory(
        '${(await getTemporaryDirectory()).path}/shared_stickers',
      );
      if (!root.existsSync()) return;
      if (paths == null) {
        root.deleteSync(recursive: true);
        return;
      }
      final parents = <Directory>{};
      for (final path in paths) {
        if (path.isEmpty) continue;
        final file = File(path);
        if (file.parent.path != root.path) parents.add(file.parent);
        if (file.existsSync()) file.deleteSync();
      }
      // Borra los directorios de paquete que quedaron vacíos.
      for (final dir in parents) {
        try {
          if (dir.existsSync() && dir.listSync().isEmpty) {
            dir.deleteSync(recursive: true);
          }
        } catch (_) {/* best-effort */}
      }
    } catch (_) {
      // Best-effort: si no se puede limpiar ahora, el sistema purgará el
      // cache más adelante.
    }
  }

  /// Consulta el lote que abrió el app (share con proceso frío).
  Future<SharedStickerBatch?> initialBatch() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('initialSharedBatch');
      final batch = _normalize(raw);
      if (batch == null) return null;
      // Ya consumido por el stream (o entregado antes): no repetir.
      if (batch.batchId.isNotEmpty && batch.batchId == _lastBatchId) {
        return null;
      }
      _lastBatchId = batch.batchId;
      _current = batch;
      return batch;
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
      if (call.method == 'onSharedBatch') {
        final batch = _normalize(call.arguments);
        if (batch == null) return;
        if (batch.batchId.isNotEmpty && batch.batchId == _lastBatchId) {
          return; // reentrega del mismo share
        }
        _lastBatchId = batch.batchId;
        _current = batch;
        _controller.add(batch);
      }
      return null;
    });
  }

  SharedStickerBatch? _normalize(dynamic raw) {
    if (raw is! Map) return null;
    final batch = SharedStickerBatch.fromMap(Map<String, dynamic>.from(raw));
    // Un lote de error siempre se propaga (aunque no traiga archivos); los
    // demás requieren al menos un archivo utilizable.
    if (batch.kind != SharedBatchKind.error && batch.stickers.isEmpty) {
      return null;
    }
    return batch;
  }
}
