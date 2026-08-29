import 'package:matrix_app/data/search_history_store.dart';

/// In-memory [SearchHistoryStore] — stands in for secure storage so the
/// search-history persistence logic is exercised through the real
/// [SearchScreen] code path against in-memory data (no platform channels).
class FakeSearchHistoryStore implements SearchHistoryStore {
  final Map<String, List<SearchHistoryEntry>> _byUser = {};

  @override
  final int maxEntries = 10;

  @override
  Future<List<SearchHistoryEntry>> load(String userId) async =>
      List.of(_byUser[userId] ?? const []);

  @override
  Future<void> add(String userId, SearchHistoryEntry entry) async {
    final current = List.of(_byUser[userId] ?? const []);
    _byUser[userId] = <SearchHistoryEntry>[
      entry,
      ...current.where((e) => e.id != entry.id),
    ].take(maxEntries).toList();
  }

  @override
  Future<void> remove(String userId, String entryId) async {
    _byUser[userId] = List.of((_byUser[userId] ?? const [])
        .where((e) => e.id != entryId));
  }

  @override
  Future<void> clear(String userId) async {
    _byUser.remove(userId);
  }

  /// Test helper: seeds the history of a user (server-simulated write)
  /// as if it had been persisted before the screen opened.

  void seed(String userId, List<SearchHistoryEntry> entries) {
    _byUser[userId] = List.of(entries);
  }

  /// Test helper: the raw stored history of a user. Null when never written.
 
  List<SearchHistoryEntry>? raw(String userId) => _byUser[userId];
}