import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/features/home/home_screen.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('renders the five navigation destinations', (tester) async {
    await pumpMatrixApp(tester, const HomeScreen());

    expect(find.text('Início'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Buscar'), findsOneWidget);
    expect(find.text('Atividades'), findsOneWidget);
    expect(find.text('Perfil'), findsOneWidget);
  });

  testWidgets('starts on the feed and opens Akame from the Chat tab',
      (tester) async {
    await pumpMatrixApp(tester, const HomeScreen());

    // Feed is the initial tab.
    expect(find.text('MATRIX'), findsOneWidget);

    // Akame is no longer a bottom-bar entry — open the Chat tab, then the
    // fixed Akame card that leads the conversations row.
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(find.text('Akame'), findsOneWidget);

    await tester.tap(find.text('Akame'));
    await tester.pumpAndSettle();

    // Akame chat header is shown.
    expect(find.text('ONLINE'), findsOneWidget);
  });

  testWidgets('switches to notifications tab on tap', (tester) async {
    await pumpMatrixApp(tester, const HomeScreen());

    await tester.tap(find.text('Atividades'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('ATIVIDADES'), findsOneWidget);
  });

  testWidgets('switches to profile tab on tap', (tester) async {
    await pumpMatrixApp(tester, const HomeScreen());

    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();

    expect(find.text('PERFIL'), findsOneWidget);
    expect(find.text('PUBLICAÇÕES'), findsOneWidget);
  });
}
