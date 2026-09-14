import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/video_cover_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.justsoft.xyz/video_thumbnail');
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    VideoCoverService.instance.resetForTest();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // path_provider → a writable temp dir.
    messenger.setMockMethodCallHandler(
      pathChannel,
      (call) async => call.method == 'getTemporaryDirectory'
          ? '/tmp/mc_cover_test'
          : null,
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(pathChannel, null);
  });

  group('VideoCoverService', () {
    test('resolve a URL ONCE and reuse the in-memory cache', () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls++;
        // A fake JPEG payload.
        return Uint8List.fromList([1, 2, 3, 4]);
      });

      final first =
          await VideoCoverService.instance.coverFor('http://x/v1.mp4');
      final second =
          await VideoCoverService.instance.coverFor('http://x/v1.mp4');

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(calls, 1, reason: 'duplicate URL must not re-extract');
    });

    test('distinct URLs do NOT share an extraction', () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls++;
        return Uint8List.fromList([9, 8, 7]);
      });

      await VideoCoverService.instance.coverFor('http://x/a.mp4');
      await VideoCoverService.instance.coverFor('http://x/b.mp4');

      expect(calls, 2);
    });

    test('extraction failure is cached as "no cover" (no repeat attempts)',
        () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls++;
        throw PlatformException(code: 'boom');
      });

      final a =
          await VideoCoverService.instance.coverFor('http://x/c.mp4');
      final b =
          await VideoCoverService.instance.coverFor('http://x/c.mp4');

      expect(a, isNull);
      expect(b, isNull);
      expect(calls, 1, reason: 'failed URL must not be retried in-session');
    });

    test('mock returning null (MissingPlugin-like) → null, no crash',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);

      final result = await VideoCoverService.instance.coverFor('http://x/d.mp4');
      expect(result, isNull);
    });
  });
}