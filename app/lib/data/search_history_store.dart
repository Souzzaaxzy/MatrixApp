import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A lightweight, persisted snapshot of a visited profile — enough
/// for the search history row to render avatar + nickname without a network
/// round-trip. Mirrors the peer payload used by chat realtime.
class SearchHistoryEntry {
  const SearchHistoryEntry({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    this.nameColor,
    this.frameId,
    this.frameAsset,
  });

  final String id;
  final String nickname;
  final String? avatarUrl;
  final String? nameColor;
  final String? frameId;
  final String? frameAsset;

  Map<String, dynamic> toJson() => {
        'id': id,
        'nickname': nickname,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (nameColor != null) 'nameColor': nameColor,
        if (frameId != null) 'frameId': frameId,
        if (frameAsset != null) 'frameAsset': frameAsset,
      };

  factory SearchHistoryEntry.fromJson(Map<String, dynamic> json) => SearchHistoryEntry(
        id: json['id'] as String? ?? '',
        nickname: json['nickname'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String?,
        nameColor: json['nameColor'] as String?,
        frameId: json['frameId'] as String?,
        frameAsset: json['frameAsset'] as String?,
      );
}

/// Persists the per-user history of visited profiles on the device (secure
/// storage, one key per authenticated userId — histories are NEVER mixed
/// between accounts). New visits move to the top, duplicates are removed,
/// and the list is capped so it never grows unbounded.
class SearchHistoryStore {
  SearchHistoryStore({
    FlutterSecureStorage? storage,
    this.maxEntries = 10,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final int maxEntries;

  static String _keyFor(String userId) => 'matrix.search_history.$userId';

  /// Full list, newest first. Empty when nothing visited yet.
 Future<List<SearchHistoryEntry>> load(String userId) async {
    if (userId.isEmpty) return const [];
    try {
      final raw = await _storage.read(key: _keyFor(userId));
      if (raw == null || raw.isEmpty) return const [];
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.map(SearchHistoryEntry.fromJson).toList();
    } catch (_) {
      // Corrupted / unreadable payload: treat as empty (never crash).
      return const [];
    }
  }

  /// Records a visit: dedup by real id, moves to the top. Idempotent.

  Future<void> add(String userId, SearchHistoryEntry entry) async {
    if (userId.isEmpty || entry.id.isEmpty || entry.nickname.isEmpty) return;
    final current = await load(userId);
    final updated = <SearchHistoryEntry>[
      entry,
      ...current.where((e) => e.id != entry.id),
    ];
    final capped = updated.take(maxEntries).toList();
    await _save(userId, updated);
  }

  /// Removes a single entry by real user id. Other entries untouched.


  Future<void> remove(String userId, String entryId) async {
    if (userId.isEmpty || entryId.isEmpty) return;
final updated = (await load(userId)).where((e) => e.id != entryId)).toList();
    await _save(userId, updated);
  }

  /// Clears the history of one user (called on logout so the next account
  /// never sees the previous one's traces even from the same device).
  Future<void> clear(String userId) async {
    if (userId.isEmpty) return;
    await _storage.delete(key: _keyFor(userId));
  }

  Future<void> _save(String userId, List<SearchHistoryEntry> entries) async {
    await _storage.write(
      key: _keyFor(userId),
      value: jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }
}