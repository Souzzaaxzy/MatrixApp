import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/app/routes.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/core/widgets/app_state_scope.dart';
import 'package:matrix_app/core/widgets/matrix_card.dart';
import 'package:matrix_app/features/search/search_screen.dart';
import 'package:matrix_app/models/matrix_user.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/in_memory_search_history_store.dart';

void main() {
  testWidgets('searching alone does not add entries to the history', (tester) async {
    final repos = FakeRepositories();
    final store = InMemorySearchHistoryStore();
    final state = AppState(repositories: repos, searchHistoryStore: store);
    await state.restoreSession();
    await state.loadFeed();
    await tester.pumpWidget(AppStateScope(
      state: state,
      child: MaterialApp(home: const SearchScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'joao');
    await tester.pumpAndSettle();

    // Result shows — but nothing recorded yet.

    expect(find.ancestor(of: find.textContaining('joao', findRichText: true), matching: find.byType(MatrixCard)), findsOneWidget);
    expect(state.searchHistory, isEmpty);
  });

  testWidgets('opening a profile adds it to the recent history section', (tester) async {
    final repos = FakeRepositories();
    final store = InMemorySearchHistoryStore();
    final state = AppState(repositories: repos, searchHistoryStore: store);
    await state.restoreSession();
    await state.loadFeed();
    await tester.pumpWidget(AppStateScope(
      state: state,
      child: MaterialApp(
        home: const SearchScreen(),
        routes: {
          AppRoutes.profile: (context) => ProfileScreenStub(nickname: 'joao'),
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'joao');
    await tester.pumpAndSettle();

    final result = find.ancestor(
      of: find.textContaining('joao', findRichText: true),
      matching: find.byType(MatrixCard),
    );
    await tester.tap(result);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));

    // Back to the search screen:the history section shows the visited profile.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pumpAndSettle();

    // Clear the query:the history section only renders when the field is empty.

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    expect(find.text('PESQUISAS RECENTES'), findsOneWidget);
    expect(state.searchHistory, hasLength(1));
    expect(state.searchHistory.first.nickname, 'joao');
  });

  testWidgets('X removes the entry immediately and persistently', (tester) async {
    final repos = FakeRepositories();
    final store = InMemorySearchHistoryStore();
    final state = AppState(repositories: repos, searchHistoryStore: store);
    await state.restoreSession();
    await state.loadFeed();
    state.recordProfileVisit(MatrixUser(id: 'u2', nickname: 'joao'));
    await tester.pumpWidget(AppStateScope(
      state: state,
      child: MaterialApp(home: const SearchScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('PESQUISAS RECENTES'), findsOneWidget);
expect(find.ancestor(of: find.textContaining('joao', findRichText: true), matching: find.byType(MatrixCard)), findsOneWidget);

     await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(find.text('PESQUISAS RECENTES'), findsNothing);
    expect(state.searchHistory, isEmpty);
  });

  testWidgets('history persists when the screen is re-opened', (tester) async {
    final repos = FakeRepositories();
    final store = InMemorySearchHistoryStore();
    final state = AppState(repositories: repos, searchHistoryStore: store);
    await state.restoreSession();
    await state.loadFeed();
    state.recordProfileVisit(MatrixUser(id: 'u2', nickname: 'joao'));
    // Flush the unawaited persist microtask so the store now has the entry.

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    // Re-open the screen from scratch:the store reloads the history on restore.


    final reloaded = AppState(repositories: repos, searchHistoryStore: store);
    await reloaded.restoreSession();
    await tester.pumpWidget(AppStateScope(
      state: reloaded,
      child: MaterialApp(home: const SearchScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('PESQUISAS RECENTES'), findsOneWidget);
expect(find.ancestor(of: find.textContaining('joao', findRichText: true), matching: find.byType(MatrixCard)), findsOneWidget);
   });
}

/// A minimal profile placeholder that records the visit then pops — enough for
/// the search-screen integration test without building the whole real profile
/// (network-free;the real ProfileScreen also records visits, which is
/// covered by profile_screen_test).
class ProfileScreenStub extends StatefulWidget {
  const ProfileScreenStub({super.key, required this.nickname});

  final String? nickname;

  @override
  State<ProfileScreenStub> createState() => _ProfileScreenStubState();
}

class _ProfileScreenStubState extends State<ProfileScreenStub> {
  @override
  void initState() {
    super.initState();
    // Record AFTER the first build so [AppState.notifyListeners] does not fire
    // during the framework's build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = AppStateScope.of(context);
      if (widget.nickname != null) {
        state.recordProfileVisit(MatrixUser(
          id: 'u2',
          nickname: widget.nickname!,
          avatarSeed: widget.nickname,
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text('PERFIL STUB')));
  }
}