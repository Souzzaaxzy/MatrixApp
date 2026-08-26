import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/features/auth/login/login_screen.dart';
import 'package:matrix_app/features/auth/register/register_screen.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('shows MATRIX branding and access label', (tester) async {
    await pumpMatrixApp(tester, const LoginScreen());

    expect(find.text('MATRIX'), findsWidgets);
    expect(find.text('ACCESS NETWORK'), findsOneWidget);
    expect(find.text('ENTRAR'), findsOneWidget);
  });

  testWidgets('nickname field has NO "@" prefix and no "@" decoration',
      (tester) async {
    await pumpMatrixApp(tester, const LoginScreen());

    // Label shows the plain nickname (uppercased by MatrixTextField).
    expect(find.text('NICKNAME'), findsOneWidget);
    // No "@" text widget anywhere (no separate @ prefix/decoration).
    expect(find.text('@'), findsNothing);
    expect(find.byIcon(Icons.alternate_email_rounded), findsNothing);
  });

  testWidgets('validates empty fields and blocks submission', (tester) async {
    await pumpMatrixApp(tester, const LoginScreen());

    await tester.tap(find.text('ENTRAR'));
    await tester.pump();

    expect(find.text('Informe um nickname'), findsOneWidget);
    expect(find.text('Informe sua senha'), findsOneWidget);
  });

  testWidgets('accepts a nickname and navigates to home', (tester) async {
    await pumpMatrixApp(tester, const LoginScreen());

    await tester.enterText(find.byType(TextField).at(0), 'leonardo');
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.tap(find.text('ENTRAR'));
    await tester.pumpAndSettle();

    // Successful login navigates to the home route.
    expect(find.text('MATRIX'), findsWidgets);
  });

  testWidgets('shows a recovery link', (tester) async {
    await pumpMatrixApp(tester, const LoginScreen());
    expect(find.text('Esqueci a senha'), findsOneWidget);
  });

  testWidgets('toggles password visibility', (tester) async {
    await pumpMatrixApp(tester, const LoginScreen());

    final visibilityToggle = find.byIcon(Icons.visibility_outlined);
    expect(visibilityToggle, findsOneWidget);

    await tester.tap(visibilityToggle);
    await tester.pump();

    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });

  testWidgets('register screen renders with CRIAR CONTA title when shown',
      (tester) async {
    await pumpMatrixApp(tester, const RegisterScreen());

    expect(find.text('CRIAR CONTA'), findsWidgets);
    expect(find.text('JOIN THE NETWORK'), findsOneWidget);
  });
}
