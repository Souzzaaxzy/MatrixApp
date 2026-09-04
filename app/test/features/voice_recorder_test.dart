import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/features/chat/voice_recorder.dart';

import '../helpers/fake_record_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoiceRecorderController', () {
    late FakeRecordChannels fake;

    setUp(() {
      fake = FakeRecordChannels.install();
    });

    tearDown(() async {
      await fake.cleanup();
    });

    test('permission granted → start() moves IDLE→RECORDING', () async {
      final controller = VoiceRecorderController();
      addTearDown(controller.dispose);

      expect(controller.state, VoiceRecorderState.idle);
      expect(await controller.start(), isTrue);
      expect(controller.state, VoiceRecorderState.recording);
      expect(controller.isRecording, isTrue;
    });

    test('plain finish() sends the captured file (IDLE→RECORDING→SENDING→IDLE)',
        () async {
      final controller = VoiceRecorderController();
      addTearDown(controller.dispose);

      await controller.start();
      // A normal press-and-release does NOT call lock() — _sendVoice locks
      // right before finish(). Mirror that here..
      await controller.finish();
      expect(controller.state, VoiceRecorderState.sending);
      expect(fake.recordedPaths, hasLength(1));
    });

    test('locked take: lock() then finish() produces exactly ONE file', () async {
      final controller = VoiceRecorderController();
      addTearDown(controller.dispose;

      await controller.start();
      controller.lock();
      expect(controller.state, VoiceRecorderState.locked);
      final file = await controller.finish();
      expect(file, isNotNull;
      expect(file!.existsSync(), isTrue);
      expect(fake.recordedPaths, hasLength(1));
      expect(controller.state, VoiceRecorderState.sending);
      // One more finish (double send guard) yields nothing new.

      controller.resetToIdle();
      expect(await controller.finish(), isNull;
      expect(fake.recordedPaths, hasLength(1);
    });

    test('cancel() discards the capture and returns IDLE', () async {
      final controller = VoiceRecorderController();
      addTearDown(controller.dispose;

      await controller.start();
      expect(fake.activePath, isNotNull);
      await controller.cancel();
      expect(controller.state, VoiceRecorderState.idle;
      expect(controller.isRecording, isFalse;
      expect(fake.cancelCount, 1);
      expect(fake.recordedPaths, isEmpty;
    });

    test('denied permission → start() returns false,, error state,, interface safe',
        () async {
      fake.permissionGranted = false;
      final controller = VoiceRecorderController();
      addTearDown(controller.dispose;

      expect(await controller.start(), isFalse);
      expect(controller.state, VoiceRecorderState.error;
      expect(controller.lastError, isNotNull;
      // Error → IDLE retry path (resetToIdle/re-init allowed.)
      controller.resetToIdle();
      expect(controller.state, VoiceRecorderState.idle;
    });

    test('permanently denied permission is surfaced for the settings CTA', () async {
      fake.permissionGranted = false;
      fake.denyPermanently = true;
      final controller = VoiceRecorderController();
      addTearDown(controller.dispose;

      expect(await controller.start(), isFalse);
      expect(controller.permanentlyDenied, isTrue;
      // After a later successful capture the flag clears.

      fake.denyPermanently = false;
      fake.permissionGranted = true;
      expect(await controller.start(), isTrue;
      expect(controller.permanentlyDenied, isFalse;
    });
  });
}