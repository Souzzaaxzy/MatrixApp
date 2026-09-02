import 'dart:convert';

import 'package:matrix_app/data/search_history_store.dart';
import 'package:matrix_app/models/search_history_entry.dart';

/// In-memory [SearchHistoryStore] for widget/unit tests — fails never touches
/// the platform secure-storage channel. Mirrors the real store's per-user
/// keying (one isolated list per user id).
class InMemorySearchHistoryStore extends SearchHistoryStore {
  InMemorySearchHistoryStore() : super(storage: null);

  final Map<String, List<SearchHistoryEntry>> _byUser = {};

  @override
  Future<List<SearchHistoryEntry>> read(String userId) async =>
      List.of(_byUser[userId] ?? const []);

  @override
  Future<void> write(String userId, List<SearchHistoryEntry> entries) async {
    _byUser[userId] = List.of(entries);
  }

  @override
  Future<void> clear(String userId) async {
    _byUser.remove(userId);
  }

  /// Test probe: the raw persisted payload for [userId] (deep copy).
  List<SearchHistoryEntry> persisted(String userId) =>
      List.of(_byUser[userId] ?? const []);

  /// Test probe: JSON round-trip of what the real store would persist.so
  String jsonPayload(String userId) => jsonEncode(
      (_byUser[userId] ?? const []).map((e) => e.toJson()).toList(),
    );
}