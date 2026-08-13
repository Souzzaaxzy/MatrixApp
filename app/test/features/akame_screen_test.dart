import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/features/akame/akame_screen.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('renders AKAME header and the initial greeting message',
      (tester) async {
    await pumpMatrixApp(tester, const AkameScreen());

    expect(find.text('AKAME'), findsWidgets);
    expect(find.text('ONLINE'), findsOneWidget);
    // The mock ships an initial Akame greeting.
    expect(find.textContaining('Olá'), findsOneWidget);
  });

  testWidgets('sends a user message and shows it in the chat', (tester) async {
    await pumpMatrixApp(tester, const AkameScreen());

    await tester.enterText(find.byType(TextField), 'Oi Akame');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(find.text('Oi Akame'), findsOneWidget);

    // Advance past the simulated typing delay so the pending reply timer
    // completes before the widget tree is disposed.
    await tester.pump(const Duration(milliseconds: 1000));
  });
}
