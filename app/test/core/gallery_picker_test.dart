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
      // DUAS chamadas para uma FOTO: a primeira sem reencode (para detectar
      // o tipo e não destruir um GIF) e a segunda comprimindo a foto.
      expect(fake.pickCount, 2);
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

  // ── GIF: a animação NÃO pode ser destruída ───────────────────
  // O image_picker RECODIFICA quando pedimos imageQuality/dimensão, e
  // recodificar um GIF animado o transforma num quadro estático. Estes testes
  // travam esse comportamento: o GIF é escolhido sem reencode.
  group('GIF preservation', () {
    testWidgets('a GIF is picked WITHOUT re-encoding', (tester) async {
      fake.pickedImagePath = '/tmp/fake_gallery_pick.gif';
      final result = await pickGalleryImage();
      expect(result.isSuccess, isTrue);
      expect(result.file!.path.toLowerCase(), endsWith('.gif'));
      // UMA chamada só: um GIF não passa pelo segundo pick (o reencode).
      expect(fake.pickCount, 1);
      expect(fake.lastImageQuality, isNull);
      expect(fake.lastMaxWidth, isNull);
      expect(fake.lastMaxHeight, isNull);
    });

    testWidgets('a photo still goes through the optimizing pick',
        (tester) async {
      fake.pickedImagePath = '/tmp/fake_gallery_pick.jpg';
      final result = await pickGalleryImage(imageQuality: 85);
      expect(result.isSuccess, isTrue);
      // DUAS chamadas: a primeira sem reencode (para detectar o tipo) e a
      // segunda comprimindo a foto.
      expect(fake.pickCount, 2);
      expect(fake.lastImageQuality, 85);
      expect(fake.lastMaxWidth, 1600);
    });
  });

  group('image type helpers', () {
    test('accepts GIF and the other image types', () {
      for (final p in [
        'a.png',
        'a.jpg',
        'a.JPEG',
        'a.webp',
        'a.gif',
        'a.GIF',
      ]) {
        expect(isSupportedImagePath(p), isTrue, reason: p);
      }
    });

    test('rejects video and unknown types', () {
      for (final p in ['a.mp4', 'a.mov', 'a.mkv', 'a.txt', 'a']) {
        expect(isSupportedImagePath(p), isFalse, reason: p);
      }
    });

    test('isGifPath only matches GIFs', () {
      expect(isGifPath('/tmp/x.gif'), isTrue);
      expect(isGifPath('/tmp/x.GIF'), isTrue);
      expect(isGifPath('/tmp/x.jpg'), isFalse);
    });
  });
}
