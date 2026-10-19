import 'dart:async';

import '../../models/conversation.dart';
import 'local_chat_store.dart';

/// Local-first chat history with background sync.
///
/// WHY
/// The phone owns the chat history: the screen reads from the local database
/// (instant, works offline) and the server is asked only to fill gaps. Every
/// message that arrives — sent by me, pushed in realtime, or fetched in a page
/// — is written to the local database first, so the history only ever grows
/// locally and the server never needs to be the archive.
///
/// This service keeps that policy in ONE place instead of scattering
/// "read local, then maybe fetch" across the chat screens.
class ChatHistoryService {
  ChatHistoryService({
    required LocalChatStore store,
    required ChatApi api,
    void Function()? onChanged,
  })  : _store = store,
        _api = api,
        _onChanged = onChanged;

  final LocalChatStore _store;
  final ChatApi _api;

  /// Called after the local store changed, so the UI can repaint.
  final void Function()? _onChanged;

  void _notify() => _onChanged?.call();

  // ── Reads (local-first) ───────────────────────────────────────

  /// Newest page of a DIRECT conversation, oldest-first.
  Future<({List<ChatMessage> messages, bool hasMore})> loadConversation(
    String conversationId, {
    String? before,
    int limit = 30,
  }) =>
      _load(isGroup: false, id: conversationId, before: before, limit: limit);

  /// Newest page of a GROUP, oldest-first.
  Future<({List<ChatMessage> messages, bool hasMore})> loadGroup(
    String groupId, {
    String? before,
    int limit = 30,
  }) =>
      _load(isGroup: true, id: groupId, before: before, limit: limit);

  Future<({List<ChatMessage> messages, bool hasMore})> _load({
    required bool isGroup,
    required String id,
    String? before,
    required int limit,
  }) async {
    // `before` arrives as a message ID (the screens page by the first visible
    // bubble). The local store pages by timestamp, so resolve it once here.
    final beforeDate =
        before == null ? null : await _store.messageCreatedAt(before);

    final local = isGroup
        ? await _store.groupMessages(id, limit: limit, before: beforeDate)
        : await _store.messages(id, limit: limit, before: beforeDate);

    // The FIRST page (no cursor) is the one that can be stale: refresh it from
    // the server in the background. Paging further back is served purely from
    // what is already stored — older pages never change, so hitting the network
    // for them would be pure waste.
    if (before == null) {
      unawaited(_syncNewest(isGroup: isGroup, id: id, limit: limit));
    }

    final hasMore = local.isEmpty
        ? false
        : await _store.hasOlder(
            isGroup: isGroup,
            id: id,
            before: local.first.createdAt,
          );
    return (messages: local, hasMore: hasMore);
  }

  /// Fetches the newest page from the server and merges it into the local
  /// database. Failures are swallowed: the local history is what matters and
  /// the UI must never break because a background refresh failed.
  Future<void> _syncNewest({
    required bool isGroup,
    required String id,
    required int limit,
  }) async {
    try {
      final page = isGroup
          ? await _api.groupMessages(id, limit: limit)
          : await _api.messages(id, limit: limit);
      if (page.messages.isEmpty) return;
      await _store.upsertAll(page.messages);
      _notify();
    } catch (_) {
      // Offline / server hiccup: keep serving the local history.
    }
  }

  // ── Writes ────────────────────────────────────────────────────

  /// Records a message the user just sent, BEFORE the server confirms it.
  /// Marked pending so it can be retried; the local echo makes the bubble
  /// appear instantly and survive a restart while offline.
  Future<void> recordPending(ChatMessage message) async {
    await _store.upsert(message, pending: true);
    _notify();
  }

  /// Records the server's authoritative version of a message (after a send is
  /// confirmed, or when a page/realtime frame carries it). Replaces the pending
  /// local echo — same id, so the bubble is updated, never duplicated.
  Future<void> recordConfirmed(ChatMessage message) async {
    await _store.upsert(message);
    _notify();
  }

  /// Records several confirmed messages at once (a realtime burst or a page).
  Future<void> recordConfirmedAll(Iterable<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    await _store.upsertAll(messages);
    _notify();
  }

  // ── Local removals ────────────────────────────────────────────

  /// "Excluir para mim": drops the message from THIS device only.
  Future<void> removeLocal(String messageId) async {
    await _store.delete(messageId);
    _notify();
  }

  /// Clears a whole conversation's local history.
  Future<void> clearConversation(String conversationId) async {
    await _store.deleteConversation(conversationId);
    _notify();
  }

  /// Clears a group's local history.
  Future<void> clearGroup(String groupId) async {
    await _store.deleteGroup(groupId);
    _notify();
  }

  /// Wipes everything (logout) so the next account starts clean.
  Future<void> clearAll() async {
    await _store.clear();
    _notify();
  }

  // ── Local reads used by the conversation list ──────────────────

  /// The newest stored message of a chat (preview without a network call).
  Future<ChatMessage?> lastMessage({
    required bool isGroup,
    required String id,
  }) =>
      _store.lastMessage(isGroup: isGroup, id: id);

  /// Messages still waiting for the server (used to retry after reconnect).
  Future<List<ChatMessage>> pending() => _store.pending();
}

/// The subset of the chat API the history service needs.
///
/// Declared as an interface so the service can be unit-tested with a fake and
/// so it does not depend on the whole repository surface.
abstract class ChatApi {
  Future<({List<ChatMessage> messages, bool hasMore})> messages(
    String conversationId, {
    String? before,
    int limit,
  });

  Future<({List<ChatMessage> messages, bool hasMore})> groupMessages(
    String groupId, {
    String? before,
    int limit,
  });
}
