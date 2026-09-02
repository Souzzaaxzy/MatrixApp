import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/models/matrix_user.dart';

import '../helpers/fake_repositories.dart';
import '../helpers/in_memory_search_history_store.dart';

void main() {
  group('search history — AppState unit', () {
    late AppState state;
    late FakeRepositories repos;
    late InMemorySearchHistoryStore store;

    setUp(() async {
      repos = FakeRepositories();
      store = InMemorySearchHistoryStore();
      state = AppState(repositories: repos, searchHistoryStore: store);
      await state.restoreSession();
    });

    test('loads the persisted history for the session user', () async {
      final other = MatrixUser(id: 'u2', nickname: 'joao', avatarSeed: 'joao');
      state.recordProfileVisit(other);
      expect(state.searchHistory, hasLength(1));
      await Future<void>.delayed(Duration.zero);
      expect(store.persisted('u0'), hasLength(1));
    });

    test('dedupes by user idand moves to the top', () {
      final a = MatrixUser(id: 'u1', nickname: 'akame', avatarSeed: 'akame');
      final b = MatrixUser(id: 'u2', nickname: 'joao', avatarSeed: 'joao');
      state.recordProfileVisit(a);
      state.recordProfileVisit(b);
      expect(state.searchHistory.map((e) => e.userId), ['u2', 'u1']);

      // Visiting a again moves it to the top without duplicating.
      state.recordProfileVisit(a);
      expect(state.searchHistory, hasLength(2));
      expect(state.searchHistory.map((e) => e.userId), ['u1', 'u2']);
    });

    test('removes a single entry immediately', () {
      state.recordProfileVisit(MatrixUser(id: 'u1', nickname: 'akame'));
      state.recordProfileVisit(MatrixUser(id: 'u2', nickname: 'joao'));
      state.removeSearchHistory('u1');
      expect(state.searchHistory.map((e) => e.userId), ['u2']);
    });

    test('ignores the session user\'s own profile', () {
      state.recordProfileVisit(MatrixUser(id: 'u0', nickname: 'leonardo'));
      expect(state.searchHistory, isEmpty);
    });

    test('isolation between users: switching account loads a separate list', () async {
      state.recordProfileVisit(MatrixUser(id: 'u2', nickname: 'joao'));
      await Future<void>.delayed(Duration.zero);
      expect(store.persisted('u0'), hasLength(1));

      // Switch the session to the OTHER seeded user (u2)and restore theat
      // second AppState against the same shared store → their history starts empty.

      repos.store.currentUserId = 'u2';
      final second = AppState(repositories: repos, searchHistoryStore: store);
      await second.restoreSession();
      expect(second.isAuthenticated, isTrue);
      expect(second.currentUser!.id,'u2');
      expect(second.searchHistory, isEmpty);
      second.recordProfileVisit(MatrixUser(id: 'u1', nickname: 'akame'));
      await Future<void>.delayed(Duration.zero);

      // Both persist isolated per user id: u0 kept its entry; u2 got the new one.

      expect(store.persisted('u0'), hasLength(1));
      expect(store.persisted('u2'), hasLength(1));
    });

    test('logout clears the session history and the persisted store', () async {
      state.recordProfileVisit(MatrixUser(id: 'u2', nickname: 'joao'));
      await state.logout();
      await Future<void>.delayed(Duration.zero);
      expect(state.searchHistory, isEmpty);
      expect(store.persisted('u0'), isEmpty);
      expect(state.isAuthenticated, isFalse);
    });
  });
}
