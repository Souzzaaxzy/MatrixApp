import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/data/search_history_store.dart';
import 'package:matrix_app/features/search/search_screen.dart';

import '../helpers/fake_search_history_store.dart';
import '../helpers/test_app.dart';

void main() {
  const userId = 'u0';

  FakeSearchHistoryStore seededStore() {
    final store = FakeSearchHistoryStore();
    store.seed(userId, const [
      SearchHistoryEntry(
        id: 'u2',
        nickname: 'joao',
        avatarUrl: null,
      ),
      SearchHistoryEntry(
        id: 'u9',
        nickname: 'ana',
        avatarUrl: null,
      ),
    ]);
    return store;
  }

  group('SearchScreen history', () {
    testWidgets('shows the visited profiles section with each entry',
        (tester) async {
      await pumpMatrixApp(
        tester,
        SearchScreen(historyStore: seededStore()),
      );
      await tester.pumpAndSettle();

      expect(find.text('HISTÓRICO'), findsOneWidget);
      expect(find.text('joao'), findsOneWidget);
      expect(find.text('ana'), findsOneWidget);
    });

    testWidgets('tapping a history row opens that profile', (tester) async {
      await pumpMatrixApp(
        tester,
        SearchScreen(historyStore: seededStore()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('joao'));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.text('PERFIL'), findsOneWidget);
      expect(find.text('SOLICITAR'), findsOneWidget);
    });

    testWidgets('X removes only that entry and keeps the others', (tester) async {
      final store = seededStore();
      await pumpMatrixApp(
        tester,
        SearchScreen(historyStore: store),
      );
      await tester.pumpAndSettle();

      // Tap the X of the FIRST row (joao) — the IconButton inside its card.

      final joaoRow = find.ancestor(
        of: find.text('joao'),
        matching: find.byType(IconButton),
      );
      await tester.tap(joaoRow);
      await tester.pumpAndSettle();

      expect(find.text('joao'), findsNothing);
      expect(find.text('ana'), findsOneWidget);
      final stored = store.raw(userId)!;
      expect(stored.map((e) => e.id), ['u9']));
    });

    testWidgets('visits move to the top and do not duplicate', (tester) async {
      final store = FakeSearchHistoryStore();
      store.seed(userId, [
        const SearchHistoryEntry(id: 'u2', nickname: 'joao'),
        const SearchHistoryEntry(id: 'u9', nickname: 'ana'),
      ]);
      await pumpMatrixApp(
        tester,
        SearchScreen(historyStore: store),
      );
      await tester.pumpAndSettle();

      // Visit joao again —â re-ordering happens in the store (dedupe +
      // move-to-top); a fresh screen reads the new order.

      await store.add(userId, const SearchHistoryEntry(id: 'u2', nickname: 'joao'));
      final stored = store.raw(userId)!;
      expect(stored.map((e) => e.id), ['u2', 'u9']));
      expect(stored, hasLength(2));
    });

    testWidgets('history is isolated per user (no cross-account mixing)',
        (tester) async {
      final store = FakeSearchHistoryStore();
      store.seed('u0', [const SearchHistoryEntry(id: 'u2', nickname: 'joao')]);
      store.seed('u99', [const SearchHistoryEntry(id: 'u9', nickname: 'ana')]);

      await pumpMatrixApp(
        tester,
        SearchScreen(historyStore: store),
      );
      await tester.pumpAndSettle();

      expect(find.text('joao'), findsOneWidget);
      expect(find.text('ana'), findsNothing);
    });
  });
}