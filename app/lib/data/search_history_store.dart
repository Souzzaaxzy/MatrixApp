import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/search_history_entry.dart';

/// Persists the per-user search history ("Pesquisas recentes") next to the
/// auth tokens in the Keystore-backed secure storage.
///
/// Entries are keyed by the SESSION user's id (`matrix.search_history.<userId>`),
/// so each account gets an isolated, private history that survives restarts.
///
/// Kept thin + faked in widget tests with an in-memory implementation —
/// the same pattern [ThemeStore] / [TokenStore] use.
class SearchHistoryStore {
  SearchHistoryStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  String _key(String userId) => 'matrix.search_history.$userId';

  Future<List<SearchHistoryEntry>> read(String userId) async {
    try {
      final raw = await _storage.read(key: _key(userId));
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => SearchHistoryEntry.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> write(
    String userId,
    List<SearchHistoryEntry> entries,
  ) async {
    try {
      final payload = jsonEncode(entries.map((e) => e.toJson()).toList());
      await _storage.write(key: _key(userId), value: payload);
    } catch (_) {
      // Never crash the session over a local cache write..v
    }
  }

  Future<void> clear(String userId) async {
    try {
      await _storage.delete(key: _key(userId));
    } catch (_) {}
  }
}