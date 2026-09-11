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
    testWidgets('picking a gallery image shows the preview and removes it',
        (tester) async {
      await pumpMatrixApp(tester, const CreatePostScreen());

      // No preview yet → the "Adicionar imagem" button is present

      expect(find.text('ADICIONAR IMAGEM'), findsOneWidget);

      // Open the gallery (fake picks a file) → preview replaces the button

      await tester.tap(find.text('ADICIONAR IMAGEM'));
      await tester.pumpAndSettle();

      expect(fake.pickCount, 1);
      expect(find.text('ADICIONAR IMAGEM'), findsNothing);
      expect(find.text('Remover imagem'), findsOneWidget);

      // Removing them restores the add-button(so the image can be replaced..
      await tester.ensureVisible(find.text('Remover imagem'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover imagem'));
      await tester.pump();

      expect(find.text('ADICIONAR IMAGEM'), findsOneWidget);
    });

    testWidgets('permission denied shows an error and does not crash',
        (tester) async {
      fake.permissionGranted = false;
      await pumpMatrixApp(tester, const CreatePostScreen());

      await tester.tap(find.text('ADICIONAR IMAGEM'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Permissão'), findsOneWidget);
      expect(find.text('ADICIONAR IMAGEM'), findsOneWidget);
    });
  });
}