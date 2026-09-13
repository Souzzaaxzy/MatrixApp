import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/app/routes.dart';
import 'package:matrix_app/app/theme/app_theme.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/core/widgets/app_state_scope.dart';
import 'package:matrix_app/features/auth/login/login_screen.dart';
import 'package:matrix_app/features/home/home_screen.dart';
import 'package:matrix_app/features/splash/splash_screen.dart';

import '../helpers/fake_repositories.dart';

/// Pumps the REAL splash with a MaterialApp (routes wired like the app).
Future<void> pumpSplash(WidgetTester tester,
    {required bool authenticated}) async {
  final repos = FakeRepositories();
  if (!authenticated) repos.store.currentUserId = null;
  final state = AppState(repositories: repos);
  addTearDown(state.dispose);
  await tester.pumpWidget(
    AppStateScope(
      state: state,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const SplashScreen(),
        routes: {
          AppRoutes.home: (_) => const HomeScreen(),
          AppRoutes.login: (_) => const LoginScreen(),
        },
      ),
    ),
  );
  await tester.pump();
  return;
}

void main() {
  testWidgets('splash shows ONLY the MATRIX text (no secondary labels)',
      (tester) async {
    await pumpSplash(tester, authenticated: true);
    await tester.pump(const Duration(milliseconds: 300));

    // The neon "MATRIX" title is PAINTED on the CustomPaint canvas (not a
    // Text widget), which keeps the scene light. Assert it structurally:
    // the only real widget text in the tree MUST NOT include any of the
    // forbidden labels.
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.textContaining('MATRIX NETWORK'), findsNothing);
    expect(find.textContaining('SYSTEM INITIALIZING'), findsNothing);
    expect(find.textContaining('LOADING'), findsNothing);
    expect(find.textContaining('INITIAL'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('WELCOME'), findsNothing);
  });

  testWidgets('splash is capped at 9s max (V2 cinematográfica)',
      (tester) async {
    await pumpSplash(tester, authenticated: true);
    expect(splashDurationMs, lessThanOrEqualTo(9000));
  });

  testWidgets('authenticated session lands on Home after the splash',
      (tester) async {
    await pumpSplash(tester, authenticated: true);

    // Advance past the full animation cap → navigation fires; the route
    // replacement completes once the controller stops ticking, so settle.
    await tester.pump(const Duration(milliseconds: splashDurationMs));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('no session lands on Login after the splash', (tester) async {
    await pumpSplash(tester, authenticated: false);

    await tester.pump(const Duration(milliseconds: splashDurationMs));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('splash screen renders without layout errors at small size',
      (tester) async {
    tester.view.physicalSize = const Size(320 * 2, 568 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpSplash(tester, authenticated: true);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'V2: the scene is a layered CustomPaint — NO box/panel behind '
      'the logo and no progress/ui widgets', (tester) async {
    await pumpSplash(tester, authenticated: true);
    await tester.pump(const Duration(milliseconds: 300));

    // The whole scene is drawn on a single CustomPaint (Canvas compositing);
    // there is no decorative Container / Card / Panel behind the title.
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byType(Container), findsNothing);
    expect(find.byType(Card), findsNothing);
    expect(find.byType(Row), findsNothing);
    expect(find.byType(Column), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(Icon), findsNothing);
    expect(find.byType(ButtonStyleButton), findsNothing);
  });

  testWidgets(
      'V2: title is painted on the canvas (effects through the letters) '
      '— there is no Text widget to put inside a box', (tester) async {
    await pumpSplash(tester, authenticated: true);
    await tester.pump(const Duration(milliseconds: 300));

    // "MATRIX" is rasterized by the CustomPainter (masked layers), so the
    // widget tree contains no Text node — the strongest guarantee that the
    // letters are NOT wrapped in a container/panel.
    expect(find.byType(Text), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
