import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/features/create_post/create_post_screen.dart';

import '../helpers/fake_gallery_channels.dart';
import '../helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeGalleryChannels fake;

  setUp(() {
    fake = FakeGalleryChannels.install();
  });

  tearDown(() async {
    await fake.cleanup();
  });

  group('gallery integration in create post', () {
    testWidgets('picking gallery media (photo/video) shows the preview and removes it',
        (tester) async {
      await pumpMatrixApp(tester, const CreatePostScreen());

      // One unified media button (📷 Foto/Vídeo) — no photo vs video split.

      expect(find.textContaining('FOTO/VÍDEO'), findsOneWidget);

      // Open the gallery (fake picks a file) → preview replaces the button.

      await tester.tap(find.textContaining('FOTO/VÍDEO'));
      await tester.pumpAndSettle();

      expect(fake.pickCount, 1);
      expect(find.textContaining('FOTO/VÍDEO'), findsNothing);
      expect(find.text('Remover imagem'), findsOneWidget);

      // Removing it restores the unified button (so media can be replaced).
      await tester.ensureVisible(find.text('Remover imagem'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover imagem'));
      await tester.pump();

      expect(find.textContaining('FOTO/VÍDEO'), findsOneWidget);
    });

    testWidgets('gallery opens and picking is stable (no crash on cancel)',
        (tester) async {
      fake.pickedImagePath = null; // simulate user cancelling the picker
      await pumpMatrixApp(tester, const CreatePostScreen());

      await tester.tap(find.textContaining('FOTO/VÍDEO'));
      await tester.pumpAndSettle();

      // Cancel keeps the screen intact and the unified button available.
      expect(find.text('Remover imagem'), findsNothing);
      expect(find.textContaining('FOTO/VÍDEO'), findsOneWidget);
    });
  });
}