import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/features/create_post/create_post_screen.dart';
import 'package:matrix_app/features/home/home_screen.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('renders title, field and publish button', (tester) async {
    await pumpMatrixApp(tester, const CreatePostScreen());

    expect(find.text('NOVA PUBLICAÇÃO'), findsOneWidget);
    expect(find.text('O que você está pensando?'), findsOneWidget);
    expect(find.text('ADICIONAR IMAGEM'), findsOneWidget);
    expect(find.text('PUBLICAR'), findsOneWidget);
  });

  testWidgets('validates empty text on publish', (tester) async {
    await pumpMatrixApp(tester, const CreatePostScreen());

    await tester.tap(find.text('PUBLICAR'));
    await tester.pump();

    expect(find.text('Escreva algo'), findsOneWidget);
  });

  testWidgets('creates a post locally when valid text is published',
      (tester) async {
    final state = AppState();
    final initialCount = state.posts.length;
    // Open create-post from the home shell so the navigator has a proper
    // route stack (the screen pops back on publish).
    await pumpMatrixApp(tester, const HomeScreen(), state: state);

    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Post de teste');
    await tester.tap(find.text('PUBLICAR'));

    // Advance past the simulated publish delay.
    await tester.pump(const Duration(milliseconds: 500));

    expect(state.posts.length, initialCount + 1);
    expect(state.posts.first.text, 'Post de teste');
  });
}
