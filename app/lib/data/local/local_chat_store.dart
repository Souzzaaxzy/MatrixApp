import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/conversation.dart';
import 'chat_message_codec.dart';

/// The phone's own chat history — the SOURCE OF TRUTH for messages.
///
/// WHY
/// Keeping every message on the server forever makes the server grow without
/// bound and makes the chat screen wait on the network for history that never
/// changes. Here the device owns the history: messages are written locally the
/// moment they are sent or received, so opening a conversation is instant and
/// works offline. The server keeps only an in-flight delivery queue.
///
/// The table stores the few columns needed to QUERY (ids, timestamp, flags)
/// plus the whole message as a JSON document — so no field can be dropped by a
/// schema mismatch when the message model grows.
class LocalChatStore {
  LocalChatStore._(this._db);

  final Database _db;

  /// One instance per process; SQLite handles the concurrency.
  static LocalChatStore? _instance;

  /// Opens (and migrates) the local database. Safe to call repeatedly.
  ///
  /// [path] is only used by tests (an in-memory or temp file path); in the app
  /// the file lives in the app's private data directory.
  static Future<LocalChatStore> open({String? path}) async {
    if (_instance != null) return _instance!;
    final dbPath = path ?? p.join(await getDatabasesPath(), 'matrix_chat.db');
    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE messages (
            id             TEXT PRIMARY KEY,
            conversationId TEXT,
            groupId        TEXT,
            createdAt      INTEGER NOT NULL,
            mine           INTEGER NOT NULL DEFAULT 0,
            pending        INTEGER NOT NULL DEFAULT 0,
            body           TEXT NOT NULL
          )
        ''');
        // History is always read "newest first within one chat", so the index
        // matches the real access pattern (and keeps pagination cheap).
        await db.execute(
          'CREATE INDEX idx_messages_dm ON messages (conversationId, createdAt)',
        );
        await db.execute(
          'CREATE INDEX idx_messages_group ON messages (groupId, createdAt)',
        );
      },
    );
    _instance = LocalChatStore._(db);
    return _instance!;
  }

  /// Test hook: drops the cached instance so a fresh database can be opened.
  static void resetForTests() => _instance = null;

  /// Stores (or replaces) one message. Idempotent by id: the same message
  /// arriving twice — e.g. the local echo plus the server's realtime frame —
  /// updates the single row instead of duplicating the bubble.
  Future<void> upsert(ChatMessage m, {bool pending = false}) async {
    await _db.insert(
      'messages',
      {
        'id': m.id,
        'conversationId': m.conversationId,
        'groupId': m.groupId,
        'createdAt': m.createdAt.millisecondsSinceEpoch,
        'mine': m.mine ? 1 : 0,
        'pending': pending ? 1 : 0,
        'body': ChatMessageCodec.encode(m),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Stores many messages in ONE transaction (a page from the server, or a
  /// batch of realtime frames). Cheaper than N inserts and atomic.
  Future<void> upsertAll(Iterable<ChatMessage> messages) async {
    final batch = _db.batch();
    for (final m in messages) {
      batch.insert(
        'messages',
        {
          'id': m.id,
          'conversationId': m.conversationId,
          'groupId': m.groupId,
          'createdAt': m.createdAt.millisecondsSinceEpoch,
          'mine': m.mine ? 1 : 0,
          'pending': 0,
          'body': ChatMessageCodec.encode(m),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// The newest [limit] messages of a DIRECT conversation, oldest-first
  /// (the order the chat renders). [before] pages further back.
  Future<List<ChatMessage>> messages(
    String conversationId, {
    int limit = 30,
    DateTime? before,
  }) =>
      _query(
          where: 'conversationId = ?',
          arg: conversationId,
          limit: limit,
          before: before);

  /// The newest [limit] messages of a GROUP, oldest-first.
  Future<List<ChatMessage>> groupMessages(
    String groupId, {
    int limit = 30,
    DateTime? before,
  }) =>
      _query(where: 'groupId = ?', arg: groupId, limit: limit, before: before);

  Future<List<ChatMessage>> _query({
    required String where,
    required String arg,
    required int limit,
    DateTime? before,
  }) async {
    final rows = await _db.query(
      'messages',
      columns: ['body'],
      where: before == null ? where : '$where AND createdAt < ?',
      whereArgs:
          before == null ? [arg] : [arg, before.millisecondsSinceEpoch],
      orderBy: 'createdAt DESC',
      limit: limit,
    );
    // Newest-first from SQL (cheap LIMIT), reversed for the UI.
    return rows
        .map((r) => ChatMessageCodec.decode(r['body'] as String))
        .toList()
        .reversed
        .toList();
  }

  /// Whether older messages exist before [before] (drives "load more").
  Future<bool> hasOlder({
    required bool isGroup,
    required String id,
    required DateTime before,
  }) async {
    final col = isGroup ? 'groupId' : 'conversationId';
    final rows = await _db.rawQuery(
      'SELECT 1 FROM messages WHERE $col = ? AND createdAt < ? LIMIT 1',
      [id, before.millisecondsSinceEpoch],
    );
    return rows.isNotEmpty;
  }

  /// The last stored message of a chat (drives the conversation list preview
  /// without a network round-trip).
  Future<ChatMessage?> lastMessage({
    required bool isGroup,
    required String id,
  }) async {
    final col = isGroup ? 'groupId' : 'conversationId';
    final rows = await _db.query(
      'messages',
      columns: ['body'],
      where: '$col = ?',
      whereArgs: [id],
      orderBy: 'createdAt DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ChatMessageCodec.decode(rows.first['body'] as String);
  }

  /// The stored timestamp of one message, or null when it is not in the local
  /// database. Lets a caller turn a message-id cursor into a date cursor.
  Future<DateTime?> messageCreatedAt(String messageId) async {
    final rows = await _db.query(
      'messages',
      columns: ['createdAt'],
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(rows.first['createdAt'] as int);
  }

  /// Clears the "pending" flag of a message the server has confirmed.
  Future<void> markConfirmed(String id) async {
    await _db.update(
      'messages',
      {'pending': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Messages still waiting for the server to confirm them (the app shows
  /// them with a "sending" tick). Used to retry after connectivity returns.
  Future<List<ChatMessage>> pending() async {
    final rows = await _db.query(
      'messages',
      columns: ['body'],
      where: 'pending = 1',
      orderBy: 'createdAt ASC',
    );
    return rows
        .map((r) => ChatMessageCodec.decode(r['body'] as String))
        .toList();
  }

  /// Removes ONE message locally ("excluir para mim").
  Future<void> delete(String id) async {
    await _db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  /// Removes a whole conversation's history locally. The server copy is
  /// untouched (other participants keep theirs).
  Future<void> deleteConversation(String conversationId) async {
    await _db.delete(
      'messages',
      where: 'conversationId = ?',
      whereArgs: [conversationId],
    );
  }

  /// Removes a group's history locally.
  Future<void> deleteGroup(String groupId) async {
    await _db.delete('messages', where: 'groupId = ?', whereArgs: [groupId]);
  }

  /// Number of messages held locally (diagnostics / tests).
  Future<int> count() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS c FROM messages');
    return (rows.first['c'] as num).toInt();
  }

  /// Wipes everything — used when the user logs out, so the next account on
  /// this device never sees the previous one's conversations.
  Future<void> clear() async {
    await _db.delete('messages');
  }

  Future<void> close() async {
    await _db.close();
    _instance = null;
  }
}
