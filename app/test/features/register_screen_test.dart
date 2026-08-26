import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/widgets/matrix_button.dart';
import 'package:matrix_app/features/auth/register/register_screen.dart';

import '../helpers/test_app.dart';

void main() {
  // Locates the MatrixButton labelled CRIAR CONTA. The button is a
  // GestureDetector wrapping the label text.
  Finder createButton() => find.ancestor(
        of: find.text('CRIAR CONTA'),
        matching: find.byType(MatrixButton),
      );

  testWidgets('renders all fields and the create account button', (tester) async {
    await pumpMatrixApp(tester, const RegisterScreen());

    expect(find.text('CRIAR CONTA'), findsWidgets);
    // ONE identity field — nickname only. No "NOME"/"USERNAME" anymore.
    expect(find.text('NOME'), findsNothing);
    expect(find.text('USERNAME'), findsNothing);
    expect(find.text('NICKNAME'), findsOneWidget);
    expect(find.text('SENHA'), findsOneWidget);
    expect(find.text('CONFIRMAR SENHA'), findsOneWidget);
    expect(createButton(), findsOneWidget);
    // No "@" prefix widget on the nickname field anymore.
    expect(find.widgetWithText(TextField, '@'), findsNothing);
  });

  testWidgets('validates empty submission', (tester) async {
    await pumpMatrixApp(tester, const RegisterScreen());
    await tester.pumpAndSettle();

    await tester.ensureVisible(createButton());
    await tester.tap(createButton());
    await tester.pump();

    expect(find.text('Informe um nickname'), findsOneWidget);
  });

  testWidgets('rejects password shorter than 8 chars', (tester) async {
    await pumpMatrixApp(tester, const RegisterScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'leo');
    await tester.enterText(find.byType(TextField).at(1), '123');
    await tester.enterText(find.byType(TextField).at(2), '123');
    await tester.ensureVisible(createButton());
    await tester.tap(createButton());
    await tester.pump();

    expect(find.text('Mínimo de 8 caracteres'), findsWidgets);
  });

  testWidgets('rejects mismatched passwords', (tester) async {
    await pumpMatrixApp(tester, const RegisterScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'leo');
    await tester.enterText(find.byType(TextField).at(1), 'Matrix123');
    await tester.enterText(find.byType(TextField).at(2), 'Matrix321');
    await tester.ensureVisible(createButton());
    await tester.tap(createButton());
    await tester.pump();

    expect(find.text('As senhas não coincidem'), findsOneWidget);
  });

  testWidgets('shows the recovery code after a valid registration', (tester) async {
    await pumpMatrixApp(tester, const RegisterScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'leo');
    await tester.enterText(find.byType(TextField).at(1), 'Matrix123');
    await tester.enterText(find.byType(TextField).at(2), 'Matrix123');
    await tester.ensureVisible(createButton());
    await tester.tap(createButton());
    // The register flow uses simulated async; advance the fake clock so the
    // recovery code dialog appears.
    await tester.pump(const Duration(milliseconds: 200));

    // The recovery code dialog is shown.
    expect(find.text('CÓDIGO DE RECUPERAÇÃO'), findsOneWidget);
    expect(find.text('829147206153'), findsOneWidget);
    // Dismiss it.
    await tester.tap(find.text('ENTENDI'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Informe um nickname'), findsNothing);
    expect(find.text('As senhas não coincidem'), findsNothing);
  });
}
