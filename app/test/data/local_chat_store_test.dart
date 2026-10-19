import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/data/local/chat_message_codec.dart';
import 'package:matrix_app/data/local/local_chat_store.dart';
import 'package:matrix_app/models/conversation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The local message store is the phone's SOURCE OF TRUTH for chat history.
/// These tests run it against a real SQLite database (ffi) so the SQL, the
/// JSON round-trip and the pagination are exercised for real.
ChatMessage msg({
  required String id,
  String? conversationId,
  String? groupId,
  String content = 'oi',
  DateTime? createdAt,
  bool mine = false,
  String type = 'text',
  String? imageUrl,
  ChatUser? sender,
  ReplyInfo? replyTo,
  StoryReference? story,
  List<ChatMention> mentions = const [],
  DateTime? readAt,
}) =>
    ChatMessage(
      id: id,
      conversationId: conversationId,
      groupId: groupId,
      senderId: mine ? 'me' : 'peer',
      sender: sender,
      content: content,
      createdAt: createdAt ?? DateTime(2026, 1, 1, 12),
      mine: mine,
      type: type,
      imageUrl: imageUrl,
      replyTo: replyTo,
      story: story,
      mentions: mentions,
      readAt: readAt,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalChatStore store;

  setUp(() async {
    LocalChatStore.resetForTests();
    store = await LocalChatStore.open(path: inMemoryDatabasePath);
  });

  tearDown(() async {
    await store.close();
    LocalChatStore.resetForTests();
  });

  group('armazenamento', () {
    test('grava e lê uma mensagem sem perder campo nenhum', () async {
      await store.upsert(msg(
        id: 'm1',
        conversationId: 'c1',
        content: 'texto com emoji 🚀 e acento ção',
        mine: true,
        readAt: DateTime(2026, 1, 2),
        type: 'image',
        imageUrl: '/static/a.png',
      ));

      final got = (await store.messages('c1')).single;
      expect(got.id, 'm1');
      expect(got.content, 'texto com emoji 🚀 e acento ção');
      expect(got.mine, isTrue);
      expect(got.type, 'image');
      expect(got.imageUrl, '/static/a.png');
      expect(got.readAt, DateTime(2026, 1, 2));
    });

    test('preserva os aninhados (sender, reply, story, mentions)', () async {
      await store.upsert(msg(
        id: 'm2',
        groupId: 'g1',
        sender: const ChatUser(id: 'u2', nickname: 'joao', avatarUrl: '/a.png'),
        replyTo: const ReplyInfo(
          id: 'orig',
          senderId: 'u2',
          senderNickname: 'joao',
          content: 'mensagem original',
          exists: true,
        ),
        story: const StoryReference(
            storyId: 's1', type: 'text', preview: 'bom dia'),
        mentions: const [
          ChatMention(userId: 'u2', nickname: 'joao', start: 0, end: 5),
        ],
      ));

      final got = (await store.groupMessages('g1')).single;
      expect(got.sender?.nickname, 'joao');
      expect(got.sender?.avatarUrl, '/a.png');
      expect(got.replyTo?.content, 'mensagem original');
      expect(got.replyTo?.senderNickname, 'joao');
      expect(got.story?.storyId, 's1');
      expect(got.story?.preview, 'bom dia');
      expect(got.mentions.single.userId, 'u2');
      expect(got.mentions.single.start, 0);
    });

    test('é idempotente: a mesma mensagem não duplica o balão', () async {
      final m = msg(id: 'm3', conversationId: 'c1');
      await store.upsert(m);
      await store.upsert(m); // local echo + realtime frame
      expect(await store.count(), 1);
    });

    test('upsertAll grava um lote', () async {
      await store.upsertAll([
        msg(id: 'a', conversationId: 'c1', createdAt: DateTime(2026, 1, 1)),
        msg(id: 'b', conversationId: 'c1', createdAt: DateTime(2026, 1, 2)),
      ]);
      expect(await store.count(), 2);
    });
  });

  group('ordenação e paginação', () {
    test('devolve do mais antigo ao mais novo (ordem de leitura)', () async {
      await store.upsertAll([
        msg(id: '2', conversationId: 'c1', content: 'segunda', createdAt: DateTime(2026, 1, 2)),
        msg(id: '1', conversationId: 'c1', content: 'primeira', createdAt: DateTime(2026, 1, 1)),
        msg(id: '3', conversationId: 'c1', content: 'terceira', createdAt: DateTime(2026, 1, 3)),
      ]);
      expect((await store.messages('c1')).map((m) => m.content).toList(),
          ['primeira', 'segunda', 'terceira']);
    });

    test('pagina para trás com `before` e informa se há mais antigas', () async {
      for (var i = 1; i <= 10; i++) {
        await store.upsert(
          msg(id: 'm$i', conversationId: 'c1', createdAt: DateTime(2026, 1, i)),
        );
      }
      final newest = await store.messages('c1', limit: 4);
      expect(newest.map((m) => m.id).toList(), ['m7', 'm8', 'm9', 'm10']);
      expect(
        await store.hasOlder(isGroup: false, id: 'c1', before: newest.first.createdAt),
        isTrue,
      );
      final older = await store.messages('c1', limit: 4, before: newest.first.createdAt);
      expect(older.map((m) => m.id).toList(), ['m3', 'm4', 'm5', 'm6']);
      expect(
        await store.hasOlder(isGroup: false, id: 'c1', before: DateTime(2026, 1, 1)),
        isFalse,
      );
    });

    test('separa DMs de grupos', () async {
      await store.upsert(msg(id: 'dm', conversationId: 'c1'));
      await store.upsert(msg(id: 'grp', groupId: 'g1'));
      expect((await store.messages('c1')).single.id, 'dm');
      expect((await store.groupMessages('g1')).single.id, 'grp');
      expect(await store.messages('g1'), isEmpty);
      expect(await store.groupMessages('c1'), isEmpty);
    });
  });

  group('última mensagem, pendentes e exclusão', () {
    test('lastMessage devolve a mais recente do chat', () async {
      await store.upsertAll([
        msg(id: 'x', conversationId: 'c1', content: 'antiga', createdAt: DateTime(2026, 1, 1)),
        msg(id: 'y', conversationId: 'c1', content: 'nova', createdAt: DateTime(2026, 1, 5)),
      ]);
      expect((await store.lastMessage(isGroup: false, id: 'c1'))?.content, 'nova');
      expect(await store.lastMessage(isGroup: false, id: 'outra'), isNull);
    });

    test('marca e lista mensagens ainda não confirmadas pelo servidor', () async {
      await store.upsert(msg(id: 'p1', conversationId: 'c1'), pending: true);
      await store.upsert(msg(id: 'p2', conversationId: 'c1'));
      expect((await store.pending()).map((m) => m.id).toList(), ['p1']);
      await store.markConfirmed('p1');
      expect(await store.pending(), isEmpty);
    });

    test('messageCreatedAt converte o cursor por id em data', () async {
      await store.upsert(
        msg(id: 'k', conversationId: 'c1', createdAt: DateTime(2026, 3, 4, 5)),
      );
      expect(await store.messageCreatedAt('k'), DateTime(2026, 3, 4, 5));
      expect(await store.messageCreatedAt('nao-existe'), isNull);
    });

    test('apaga UMA mensagem (excluir para mim)', () async {
      await store.upsertAll([
        msg(id: 'a', conversationId: 'c1'),
        msg(id: 'b', conversationId: 'c1'),
      ]);
      await store.delete('a');
      expect((await store.messages('c1')).map((m) => m.id).toList(), ['b']);
    });

    test('apaga a conversa inteira sem tocar em outros chats', () async {
      await store.upsert(msg(id: 'dm', conversationId: 'c1'));
      await store.upsert(msg(id: 'grp', groupId: 'g1'));
      await store.deleteConversation('c1');
      expect(await store.messages('c1'), isEmpty);
      expect((await store.groupMessages('g1')).single.id, 'grp');
    });

    test('clear apaga tudo (logout)', () async {
      await store.upsertAll([
        msg(id: 'dm', conversationId: 'c1'),
        msg(id: 'grp', groupId: 'g1'),
      ]);
      await store.clear();
      expect(await store.count(), 0);
    });
  });

  group('codec', () {
    test('round-trip preserva uma mensagem de voz completa', () {
      final m = msg(
        id: 'v1',
        conversationId: 'c1',
        type: 'voice',
        content: '🎤 Áudio',
      ).copyWith(audioUrl: '/static/v.m4a', durationMs: 2500);

      final back = ChatMessageCodec.decode(ChatMessageCodec.encode(m));
      expect(back.type, 'voice');
      expect(back.audioUrl, '/static/v.m4a');
      expect(back.durationMs, 2500);
      expect(back.content, '🎤 Áudio');
    });
  });
}
