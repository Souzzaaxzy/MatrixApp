import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/utils/gallery_picker.dart';

import '../helpers/fake_gallery_channels.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeGalleryChannels fake;

  setUp(() {
    fake = FakeGalleryChannels.install();
  });

  tearDown(() async {
    await fake.cleanup();
  });

  group('pickGalleryImage permission handling', () {
    testWidgets('returns success with the picked path when permission is granted',
        (tester) async {
      final result = await pickGalleryImage();
      expect(result.isSuccess, isTrue);
      expect(result.file!.path, '/tmp/fake_gallery_pick.jpg');
      expect(fake.pickCount, 1);
    });

    testWidgets('returns cancelled when the picker is dismissed', (tester) async {
      fake.pickedImagePath = null;
      final result = await pickGalleryImage();
      expect(result.isSuccess, isFalse);
      expect(result.cancelled, isTrue);
      expect(fake.pickCount, 1);
    });

    testWidgets('returns a clear error when photo permission is denied',
        (tester) async {
      fake.permissionGranted = false;
      final result = await pickGalleryImage();
      expect(result.isSuccess, isFalse);
      expect(result.cancelled, isFalse);
      expect(result.error, isNotNull);
      expect(result.error!, contains('Permissão'));
      expect(fake.pickCount, 0);
    });

    testWidgets('returns a clear error when permission is permanently denied',
        (tester) async {
      fake.denyPermanently = true;
      final result = await pickGalleryImage();
      expect(result.isSuccess, isFalse);
      expect(result.error!, contains('Permissão'));
      expect(fake.pickCount, 0);
    });
  });
}
