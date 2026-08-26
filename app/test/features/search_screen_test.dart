import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/widgets/matrix_card.dart';
import 'package:matrix_app/features/search/search_screen.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('shows the search header and hint', (tester) async {
    await pumpMatrixApp(tester, const SearchScreen());

    expect(find.text('MATRIX SEARCH'), findsOneWidget);
    expect(find.text('Pesquisar usuários...'), findsOneWidget);
  });

  testWidgets('filters users by nickname', (tester) async {
    await pumpMatrixApp(tester, const SearchScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Leonardo');
    await tester.pumpAndSettle();

    // Only Leonardo matches — rendered WITHOUT the '@' prefix.
    expect(find.text('leonardo'), findsOneWidget);
  });

  testWidgets('tapping a result opens that user profile', (tester) async {
    await pumpMatrixApp(tester, const SearchScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'joao');
    await tester.pumpAndSettle();

    // The RichText result (NOT the EditableText query field) is the target.
    final result = find.ancestor(
      of: find.textContaining('joao', findRichText: true),
      matching: find.byType(MatrixCard),
    );
    expect(result, findsOneWidget);
    await tester.tap(result);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));

    // The profile screen loads with the searched user and the Adicionar button.
    expect(find.text('PERFIL'), findsOneWidget);
    expect(find.text('ADICIONAR'), findsOneWidget);
  });

  testWidgets('shows empty state when no user matches', (tester) async {
    await pumpMatrixApp(tester, const SearchScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzznopezzz');
    await tester.pumpAndSettle();

    expect(find.text('NO RESULTS'), findsOneWidget);
  });
}
