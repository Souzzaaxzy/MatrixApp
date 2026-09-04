import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stubs the `record` + `permission_handler` + `path_provider` platform
/// channels so the full hold→record→release→send gesture can run in widget
/// tests with no real mic/filesystem. Tests configure behavior via
/// [permissionGranted] / [denyPermanently]and drive assertions via
/// [recordedPaths] / [cancelCount].
class FakeRecordChannels {
  bool permissionGranted = true;

  /// When true, the OS reports the mic PERMANENTLY denied (so it can't be
  /// re-requested; a settings CTA is expected in the UI..
  bool denyPermanently = false;

  /// Paths handed back by `stop` (one per finished capture).
  final List<String> recordedPaths = [];

  /// How many times `cancel` was called (drag-left discard).
  int cancelCount = 0;

  /// Path handed to `start` for the current capture (null when none).
  String? activePath;

  final List<String> _invalidatedPaths = [];

  factory FakeRecordChannels.install() {
    final fake = FakeRecordChannels._();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.record/messages'),
        fake._handleRecord);
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        fake._handlePermission);
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        fake._handlePathProvider);
    // The per-recorder event channels (state + amplitude) only exist once the
    // recorder id is known (it arrives as the `recorderId` arg of `create`),
    // so they are mocked dynamically in [FakeRecordChannels._installEventMocks].
    return fake;
  }

  /// Registers the per-recorder event channels (state + amplitude) when the
  /// recorder id is known. Swallows everything — tests never emit.


  void _installEventMocks(String recorderId) {

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;



    for (final name in <String>[
      'com.llfbandit.record/events/$recorderId',
      'com.llfbandit.record/eventsRecord/$recorderId',
    ]) {
      messenger.setMockStreamHandler(
        EventChannel(name),
        MockStreamHandler.inline(
          onListen: (args, events) => events.endOfStream(),
          onCancel: (args) {},
        ),
      );
    }
  }

  FakeRecordChannels._();

  Future<Object?> _handlePermission(MethodCall call) async {
    debugPrint('[FAKE-PERM] ${call.method}');
    switch (call.method) {
      case 'checkPermissionStatus':
        if (denyPermanently) return 4;
        return permissionGranted ? 1 : 0;
      case 'requestPermissions':
        final value = denyPermanently ? 4 : (permissionGranted ? 1 : 0);
        final List<dynamic>? args =
            call.arguments is List ? (call.arguments as List) : null;
        final permissionId =
            (args != null && args.isNotEmpty) ? args.first as int : 7;
        return <int, int>{permissionId: value};
      case 'shouldShowRequestPermissionRationale':
        return false;
      case 'openAppSettings':
        return true;
      default:
        debugPrint('[FAKE-UNKNOWN-PERM] ${call.method}');
        return null;
    }
  }

  Future<Object?> _handleRecord(MethodCall call) async {
    debugPrint('[FAKE-REC] >> ${call.method}');
    final r = await _handleRecordInner(call);
    debugPrint('[FAKE-REC] << ${call.method} -> ${r.runtimeType}');
    return r;
  }

  Future<Object?> _handleRecordInner(MethodCall call) async {
    debugPrint('[FAKE-REC] -- ${call.method}');
    final args = call.arguments is Map
        ? Map<String,dynamic>.from(call.arguments as Map)
        : <String,dynamic>{};
    switch (call.method) {
      case 'create':
      final recorderId = args['recorderId'] as String?;
        if (recorderId != null && recorderId.isNotEmpty) {
          _installEventMocks(recorderId);
        }
        return null;
      case 'hasPermission':
        return permissionGranted;
      case 'start':
        activePath = args['path'] as String?;
        final path = activePath;
        if (path != null && path.isNotEmpty) {
          _invalidatedPaths.remove(path);
          final f = File(path);
          f.parent.createSync(recursive: true);
          f.writeAsBytesSync(List<int>.filled(2048, 1));
        }
        return null;
      case 'isRecording':
        return activePath != null;
      case 'getAmplitude':
        return <String, double>{'current': -30.0, 'max': -30.0};
      case 'stop':
        final stoppedPath = activePath;
        activePath = null;
        if (stoppedPath != null && !_invalidatedPaths.contains(stoppedPath)) {
          recordedPaths.add(stoppedPath);
        }
        return stoppedPath;
      case 'cancel':
        if (activePath != null) _invalidatedPaths.add(activePath!);
        activePath = null;
        cancelCount++;
        return null;
      case 'dispose':
        return null;
      default:
        debugPrint('[FAKE-UNKNOWN-REC] ${call.method}');
        return null;
    }
  }

  Future<Object?> _handlePathProvider(MethodCall call) async {
    debugPrint('[FAKE-PATH] ${call.method}');
    switch (call.method) {
      case 'getTemporaryDirectory':
        return '/tmp';
      default:
        debugPrint('[FAKE-UNKNOWN-PATH] ${call.method}');
        return null;
    }
  }

  Future<void> cleanup() async {
    for (final p in [...recordedPaths, ..._invalidatedPaths]) {
      final f = File(p);
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {
        // Already gone — fine..
      }
    }
    recordedPaths.clear();
    _invalidatedPaths.clear();
  }
}
