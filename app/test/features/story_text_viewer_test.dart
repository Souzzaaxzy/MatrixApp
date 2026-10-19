import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/features/feed/story_viewer.dart';
import 'package:matrix_app/models/story.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/test_app.dart';

/// A TEXT story (no media) must render its TEXT in the viewer — never a
/// broken-image placeholder, and never an empty screen.
Future<AppState> seededTextStory() async {
  final repos = FakeRepositories();
  final now = DateTime.now();
  repos.store.storyGroups.add(
    StoryGroup(
      authorId: 'u2',
      authorNickname: 'joao',
      authorAvatarUrl: null,
      stories: [
        Story(
          id: 's_text',
          authorId: 'u2',
          authorNickname: 'joao',
          authorAvatarUrl: null,
          mediaUrl: null,
          mediaType: 'image',
          type: 'text',
          text: 'Bom dia, galera!',
          createdAt: now,
          expiresAt: now.add(const Duration(hours: 24)),
        ),
      ],
      allViewed: false,
    ),
  );
  final state = AppState(repositories: repos);
  await state.restoreSession();
  await state.loadStories();
  return state;
}

Future<void> openViewer(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await pumpMatrixApp(
    tester,
    Builder(
      builder: (ctx) => ElevatedButton(
        onPressed: () => StoryViewer.open(ctx, state, startGroup: 0),
        child: const Text('abrir'),
      ),
    ),
    state: state,
  );
  await tester.tap(find.text('abrir'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('Story de TEXTO no viewer', () {
    testWidgets('mostra o TEXTO e nunca o ícone de imagem quebrada',
        (tester) async {
      final state = await seededTextStory();
      await openViewer(tester, state);

      // O texto do Story aparece…
      expect(find.text('Bom dia, galera!'), findsOneWidget);
      // …e NENHUM placeholder de imagem quebrada é renderizado.
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
    });

    testWidgets('não tenta carregar mídia para um Story de texto',
        (tester) async {
      final state = await seededTextStory();
      await openViewer(tester, state);

      // Sem mídia não há CachedNetworkImage/Image para o Story em si
      // (o avatar do autor é o único Image possível, e ele usa iniciais).
      final storyMediaImages = find.descendant(
        of: find.byType(StoryViewer),
        matching: find.byType(Image),
      );
      expect(storyMediaImages, findsNothing);
    });
  });
}
