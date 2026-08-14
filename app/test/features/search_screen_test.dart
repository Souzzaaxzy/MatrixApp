import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/features/search/search_screen.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('shows the search header and hint', (tester) async {
    await pumpMatrixApp(tester, const SearchScreen());

    expect(find.text('MATRIX SEARCH'), findsOneWidget);
    expect(find.text('Pesquisar usuários...'), findsOneWidget);
  });

  testWidgets('filters users by name', (tester) async {
    await pumpMatrixApp(tester, const SearchScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Leonardo');
    await tester.pumpAndSettle();

    // Only Leonardo matches.
    expect(find.text('@leonardo'), findsOneWidget);
  });

  testWidgets('shows empty state when no user matches', (tester) async {
    await pumpMatrixApp(tester, const SearchScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzznopezzz');
    await tester.pumpAndSettle();

    expect(find.text('NO RESULTS'), findsOneWidget);
  });
}
