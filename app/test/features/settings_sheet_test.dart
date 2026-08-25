import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/app/routes.dart';
import 'package:matrix_app/app/theme/app_theme.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/core/services/theme_controller.dart';
import 'package:matrix_app/core/widgets/app_state_scope.dart';
import 'package:matrix_app/features/auth/login/login_screen.dart';
import 'package:matrix_app/features/profile/profile_screen.dart';

import '../helpers/fake_repositories.dart';

/// Settings bottom sheet (☰) accessible ONLY on the session user's own
/// profile: theme trio, logout with confirmation, and the destructive
/// account delete with nickname re-entry.
Future<void> pumpProfile(
  WidgetTester tester,
  AppState state, {
  String? username,
}) async {
  // Restore the session so screens relying on currentUser render content.
  await state.restoreSession();
  await state.loadFeed();
  await tester.pumpWidget(
    AppStateScope(
      state: state,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: ProfileScreen(username: username),
        onGenerateRoute: buildAppRoute,
      ),
    ),
  );
  // Route render + async profile load.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Finder settingsButton() =>
    find.widgetWithIcon(IconButton, Icons.menu_rounded);

void main() {
  testWidgets('☰ button exists ONLY on the own profile', (tester) async {
    final state = AppState(repositories: FakeRepositories());
    addTearDown(state.dispose);
    await pumpProfile(tester, state);
    expect(settingsButton(), findsOneWidget);

    // Another user's profile -> no settings entry.
    await pumpProfile(tester, state, username: 'joao');
    expect(settingsButton(), findsNothing);
  });

  testWidgets('opens the sheet with theme trio + logout + delete entries',
      (tester) async {
    final state = AppState(repositories: FakeRepositories());
    addTearDown(state.dispose);
    await pumpProfile(tester, state);

    await tester.tap(settingsButton());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('CONFIGURAÇÕES'), findsOneWidget);
    expect(find.text('Escuro'), findsOneWidget);
    expect(find.text('Claro'), findsOneWidget);
    expect(find.text('Sistema'), findsOneWidget);
    expect(find.text('Sair da conta'), findsOneWidget);
    expect(find.text('Excluir conta'), findsOneWidget);

    // Closing the sheet keeps the profile.
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('CONFIGURAÇÕES'), findsNothing);
  });

  testWidgets('selecting a theme updates the shared controller',
      (tester) async {
    final state = AppState(repositories: FakeRepositories());
    addTearDown(state.dispose);
    final controller = ThemeController.instance;
    addTearDown(() => controller.setMode(MatrixThemeMode.dark));
    await pumpProfile(tester, state);
    await tester.tap(settingsButton());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Claro'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.mode, MatrixThemeMode.light);

    await tester.tap(find.text('Sistema'));
    await tester.pump();
    expect(controller.mode, MatrixThemeMode.system);
  });

  testWidgets('logout asks for confirmation and then lands on login',
      (tester) async {
    final state = AppState(repositories: FakeRepositories());
    addTearDown(state.dispose);
    await pumpProfile(tester, state);
    await tester.tap(settingsButton());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Sair da conta'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sair da conta?'), findsOneWidget);

    // Cancel keeps the session.
    await tester.tap(find.text('Cancelar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.isAuthenticated, isTrue);

    // Confirm logs out and lands on the login screen.
    await tester.tap(find.text('Sair da conta'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Sair'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.isAuthenticated, isFalse);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('delete requires a strong confirmation + nickname re-entry',
      (tester) async {
    final state = AppState(repositories: FakeRepositories());
    addTearDown(state.dispose);
    await pumpProfile(tester, state);
    await tester.tap(settingsButton());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Excluir conta'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Excluir conta?'), findsOneWidget);
    expect(find.textContaining('permanente'), findsOneWidget);

    // Cancel on the FIRST dialog keeps the account.
    await tester.tap(find.text('Cancelar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.isAuthenticated, isTrue);

    await tester.tap(find.text('Excluir conta'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Excluir minha conta'));
    await tester.pump(const Duration(milliseconds: 300));

    // Second dialog: nickname re-entry. A WRONG nickname can't delete.
    expect(find.text('Digite seu nickname para confirmar'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'outra-pessoa');
    await tester.tap(find.text('Excluir'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.isAuthenticated, isTrue);

    // Correct nickname -> hard delete + back to login.
    await tester.tap(find.text('Excluir conta'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Excluir minha conta'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField).last, 'leonardo');
    await tester.tap(find.text('Excluir'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.isAuthenticated, isFalse);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
