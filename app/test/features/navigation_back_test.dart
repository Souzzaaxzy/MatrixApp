import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/app/routes.dart';
import 'package:matrix_app/app/theme/app_theme.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/core/widgets/app_state_scope.dart';
import 'package:matrix_app/features/home/home_screen.dart';
import 'package:matrix_app/features/profile/profile_screen.dart';

import '../helpers/fake_repositories.dart';

/// Widget-level verification of the REAL route generator + initial-route
/// logic used by `MaterialApp` in app.dart. These tests guard against the
/// historic "Rota não encontrada" bug: a phantom '/' route used to sit at
/// the bottom of the stack and be revealed by the Android back button.
Future<void> pumpRealApp(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(
    AppStateScope(
      state: state,
      child: MaterialApp(
        theme: AppTheme.dark,
        initialRoute: AppRoutes.splash,
        onGenerateRoute: buildAppRoute,
        onGenerateInitialRoutes: appInitialRoutes,
      ),
    ),
  );
  // Splash delay (1800ms) + fade transition (250ms).
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('initial route resolves to ONE route (no phantom 404 below)',
      (tester) async {
    final state = AppState(repositories: FakeRepositories());
    addTearDown(state.dispose);
    await pumpRealApp(tester, state);

    // Fake repos authenticate instantly -> HomeScreen, never the fallback.
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Rota não encontrada'), findsNothing);
  });

  testWidgets('unknown route falls back to HomeScreen, never the 404 screen',
      (tester) async {
    final state = AppState(repositories: FakeRepositories());
    addTearDown(state.dispose);
    await pumpRealApp(tester, state);

    Navigator.of(tester.element(find.byType(HomeScreen)))
        .pushNamed('/rota-inexistente');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Rota não encontrada'), findsNothing);
  });

  testWidgets(
      'system back on a pushed profile pops it and returns to the feed '
      '(never reveals a 404)', (tester) async {
    final state = AppState(repositories: FakeRepositories());
    addTearDown(state.dispose);
    await pumpRealApp(tester, state);

    Navigator.of(tester.element(find.byType(HomeScreen)))
        .pushNamed(AppRoutes.profile, arguments: 'joao');
    // Route transition + async profile load.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ProfileScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ProfileScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Rota não encontrada'), findsNothing);
  });

  testWidgets(
      'root back: first press shows the exit hint, second press exits, '
      'state resets after 2s', (tester) async {
    final state = AppState(repositories: FakeRepositories());
    addTearDown(state.dispose);
    await pumpRealApp(tester, state);
    expect(find.byType(HomeScreen), findsOneWidget);

    // 1st press -> hint; the app stays.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Pressione voltar novamente para sair'), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);

    // >2s without a second press -> pending state resets. The next press
    // behaves as a FIRST press again (the exit hint pops back up).
    // Total SnackBar lifetime ~= enter(250) + show(2000) + exit(150) -> 2400.
    // SnackBar lifetime (enter 250 + show 2000 + exit ~150 + disposal)
    // completes within 3s of fake time; step the clock so the display
    // timer is scheduled right after the enter animation completes.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('Pressione voltar novamente para sair'), findsNothing);

    // After the reset, the next press is a FIRST press again (hint shows).
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Pressione voltar novamente para sair'), findsOneWidget);

    // 2nd press inside the window -> requests app exit (swallowed here).
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Rota não encontrada'), findsNothing);
  });

  testWidgets('root back from another tab returns to the feed tab first',
      (tester) async {
    final state = AppState(repositories: FakeRepositories());
    addTearDown(state.dispose);
    await pumpRealApp(tester, state);

    // Jump to the Perfil tab (index 4).
    await tester.tap(find.text('Perfil'));
    await tester.pump();
    expect(find.text('PERFIL'), findsWidgets);

    // Back press -> returns to tab 0 (feed) instead of exiting.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Rota não encontrada'), findsNothing);
  });
}
