import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/data/local/chat_history_service.dart';
import 'package:matrix_app/data/local/local_chat_store.dart';
import 'package:matrix_app/models/conversation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A fake server that records what was asked and can be made to fail, so the
/// "read local first, refresh in background" policy is verified for real.
class FakeChatApi implements ChatApi {
  FakeChatApi({this.dmPage = const [], this.groupPage = const []});

  List<ChatMessage> dmPage;
  List<ChatMessage> groupPage;
  bool fail = false;
  int dmCalls = 0;
  int groupCalls = 0;

  @override
  Future<({List<ChatMessage> messages, bool hasMore})> messages(
    String conversationId, {
    String? before,
    int limit = 30,
  }) async {
    dmCalls++;
    if (fail) throw Exception('offline');
    return (messages: dmPage, hasMore: false);
  }

  @override
  Future<({List<ChatMessage> messages, bool hasMore})> groupMessages(
    String groupId, {
    String? before,
    int limit = 30,
  }) async {
    groupCalls++;
    if (fail) throw Exception('offline');
    return (messages: groupPage, hasMore: false);
  }
}

ChatMessage m(String id, {String? conv, String? group, DateTime? at}) =>
    ChatMessage(
      id: id,
      conversationId: conv,
      groupId: group,
      senderId: 'peer',
      content: 'msg $id',
      createdAt: at ?? DateTime(2026, 1, 1, 12),
      mine: false,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalChatStore store;
  late FakeChatApi api;
  late ChatHistoryService svc;
  var notified = 0;

  setUp(() async {
    LocalChatStore.resetForTests();
    store = await LocalChatStore.open(path: inMemoryDatabasePath);
    api = FakeChatApi();
    notified = 0;
    svc = ChatHistoryService(store: store, api: api, onChanged: () => notified++);
  });

  tearDown(() async {
    await store.close();
    LocalChatStore.resetForTests();
  });

  group('leitura local-first', () {
    test('a primeira abertura busca no servidor e grava localmente', () async {
      api.dmPage = [m('a', conv: 'c1'), m('b', conv: 'c1')];
      final page = await svc.loadConversation('c1');
      // Nothing stored yet → the first load can only come from the server…
      expect(page.messages, isEmpty);
      // …and the background sync writes it locally.
      await Future<void>.delayed(Duration.zero);
      expect(await store.count(), 2);
    });

    test('a segunda abertura lê do DISCO', () async {
      await store.upsertAll([m('a', conv: 'c1'), m('b', conv: 'c1')]);
      final before = api.dmCalls;
      final page = await svc.loadConversation('c1');
      expect(page.messages.map((x) => x.id).toList(), ['a', 'b']);
      await Future<void>.delayed(Duration.zero);
      // The newest page still refreshes in the background (cheap).
      expect(api.dmCalls, before + 1);
    });

    test('funciona OFFLINE: com o servidor fora, o histórico local responde',
        () async {
      await store.upsertAll([m('a', conv: 'c1'), m('b', conv: 'c1')]);
      api.fail = true;
      final page = await svc.loadConversation('c1');
      expect(page.messages.map((x) => x.id).toList(), ['a', 'b']);
      // A falha da atualização de fundo não pode estourar na UI.
      await Future<void>.delayed(Duration.zero);
    });

    test('páginas ANTIGAS não vão ao servidor (histórico não muda)', () async {
      for (var i = 1; i <= 6; i++) {
        await store.upsert(m('m$i', conv: 'c1', at: DateTime(2026, 1, i)));
      }
      final newest = await svc.loadConversation('c1', limit: 3);
      final callsAfterNewest = api.dmCalls;
      final older = await svc.loadConversation('c1',
          limit: 3, before: newest.messages.first.id);
      expect(older.messages.map((x) => x.id).toList(), ['m1', 'm2', 'm3']);
      expect(api.dmCalls, callsAfterNewest);
    });

    test('hasMore indica se ainda há histórico mais antigo', () async {
      for (var i = 1; i <= 5; i++) {
        await store.upsert(m('m$i', conv: 'c1', at: DateTime(2026, 1, i)));
      }
      expect((await svc.loadConversation('c1', limit: 3)).hasMore, isTrue);
      expect((await svc.loadConversation('c1', limit: 50)).hasMore, isFalse);
    });

    test('grupos seguem a mesma política', () async {
      api.groupPage = [m('g1', group: 'grp')];
      await svc.loadGroup('grp');
      await Future<void>.delayed(Duration.zero);
      expect(await store.count(), 1);
      expect((await svc.loadGroup('grp')).messages.single.id, 'g1');
    });
  });

  group('escrita', () {
    test('mensagem enviada é gravada como PENDENTE e depois confirmada',
        () async {
      final mine = ChatMessage(
        id: 'local1',
        conversationId: 'c1',
        senderId: 'me',
        content: 'oi',
        createdAt: DateTime(2026, 1, 1, 13),
        mine: true,
      );
      await svc.recordPending(mine);
      expect((await svc.pending()).single.id, 'local1');
      expect((await svc.loadConversation('c1')).messages.single.id, 'local1');
      await svc.recordConfirmed(mine);
      expect(await svc.pending(), isEmpty);
      expect(await store.count(), 1);
    });

    test('mensagem realtime é gravada e aparece no histórico', () async {
      await svc.recordConfirmed(m('rt', conv: 'c1'));
      expect((await svc.loadConversation('c1')).messages.single.id, 'rt');
    });

    test('recordConfirmedAll grava um lote de uma vez', () async {
      await svc.recordConfirmedAll([m('a', conv: 'c1'), m('b', conv: 'c1')]);
      expect(await store.count(), 2);
    });

    test('excluir para mim remove só localmente', () async {
      await svc.recordConfirmedAll([m('a', conv: 'c1'), m('b', conv: 'c1')]);
      await svc.removeLocal('a');
      expect((await svc.loadConversation('c1')).messages.map((x) => x.id).toList(),
          ['b']);
    });

    test('clearAll limpa tudo (logout)', () async {
      await svc.recordConfirmedAll([m('a', conv: 'c1'), m('g', group: 'grp')]);
      await svc.clearAll();
      expect(await store.count(), 0);
    });

    test('lastMessage vem do disco (preview da lista)', () async {
      await svc.recordConfirmedAll([
        m('old', conv: 'c1', at: DateTime(2026, 1, 1)),
        m('new', conv: 'c1', at: DateTime(2026, 1, 9)),
      ]);
      expect((await svc.lastMessage(isGroup: false, id: 'c1'))?.id, 'new');
    });
  });

  group('notificação de mudança', () {
    test('avisa a UI quando algo é gravado', () async {
      final before = notified;
      await svc.recordConfirmed(m('x', conv: 'c1'));
      expect(notified, greaterThan(before));
    });
  });
}
