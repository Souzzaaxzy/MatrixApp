import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/widgets/matrix_button.dart';
import 'package:matrix_app/features/auth/register/register_screen.dart';

import '../helpers/test_app.dart';

void main() {
  // Helper that locates the MatrixButton labelled CRIAR CONTA (there is also
  // a screen title with the same text).
  Finder createButton() => find.descendant(
        of: find.byType(MatrixButton),
        matching: find.text('CRIAR CONTA'),
      );

  testWidgets('renders all fields and the create account button', (tester) async {
    await pumpMatrixApp(tester, const RegisterScreen());

    expect(find.text('CRIAR CONTA'), findsWidgets);
    expect(find.text('NOME'), findsOneWidget);
    expect(find.text('E-MAIL'), findsOneWidget);
    expect(find.text('SENHA'), findsOneWidget);
    expect(find.text('CONFIRMAR SENHA'), findsOneWidget);
    expect(createButton(), findsOneWidget);
  });

  testWidgets('validates empty submission', (tester) async {
    await pumpMatrixApp(tester, const RegisterScreen());

    await tester.tap(createButton());
    await tester.pump();

    expect(find.text('Informe seu nome'), findsOneWidget);
    expect(find.text('Informe seu e-mail'), findsOneWidget);
  });

  testWidgets('rejects password shorter than 6 chars', (tester) async {
    await pumpMatrixApp(tester, const RegisterScreen());

    await tester.enterText(find.byType(TextField).at(0), 'Leonardo');
    await tester.enterText(find.byType(TextField).at(1), 'leo@example.com');
    await tester.enterText(find.byType(TextField).at(2), '123');
    await tester.enterText(find.byType(TextField).at(3), '123');
    await tester.tap(createButton());
    await tester.pump();

    expect(find.text('Mínimo de 6 caracteres'), findsWidgets);
  });

  testWidgets('rejects mismatched passwords', (tester) async {
    await pumpMatrixApp(tester, const RegisterScreen());

    await tester.enterText(find.byType(TextField).at(0), 'Leonardo');
    await tester.enterText(find.byType(TextField).at(1), 'leo@example.com');
    await tester.enterText(find.byType(TextField).at(2), '123456');
    await tester.enterText(find.byType(TextField).at(3), '654321');
    await tester.tap(createButton());
    await tester.pump();

    expect(find.text('As senhas não coincidem'), findsOneWidget);
  });

  testWidgets('accepts a valid form and navigates to home', (tester) async {
    await pumpMatrixApp(tester, const RegisterScreen());

    await tester.enterText(find.byType(TextField).at(0), 'Leonardo');
    await tester.enterText(find.byType(TextField).at(1), 'leo@example.com');
    await tester.enterText(find.byType(TextField).at(2), '123456');
    await tester.enterText(find.byType(TextField).at(3), '123456');
    await tester.tap(createButton());
    // Advance the simulated registration delay.
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Informe seu nome'), findsNothing);
    expect(find.text('As senhas não coincidem'), findsNothing);
  });
}
