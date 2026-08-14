import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';

import '../helpers/fake_repositories.dart';

void main() {
  late AppState state;

  setUp(() async {
    state = AppState(repositories: FakeRepositories());
    await state.restoreSession();
    await state.loadFeed();
  });

  test('initial state restores the current user and loads the feed', () {
    expect(state.posts, isNotEmpty);
    expect(state.currentUser, isNotNull);
    expect(state.currentUser!.name, isNotEmpty);
    expect(state.isAuthenticated, isTrue);
  });

  test('akame messages start seeded', () {
    expect(state.akameMessages, isNotEmpty);
  });

  group('toggleLike', () {
    test('toggles the like state and count remotely', () async {
      final first = state.posts.first;
      final initial = first.likes;
      final wasLiked = first.liked;

      await state.toggleLike(first.id);

      expect(state.posts.first.liked, !wasLiked);
      expect(state.posts.first.likes, wasLiked ? initial - 1 : initial + 1);
    });

    test('is reversible — toggling twice returns to the original count',
        () async {
      final first = state.posts.first;
      final initialLikes = first.likes;
      final initialLiked = first.liked;

      await state.toggleLike(first.id);
      await state.toggleLike(first.id);

      expect(state.posts.first.likes, initialLikes);
      expect(state.posts.first.liked, initialLiked);
    });

    test('does nothing for an unknown post id', () async {
      final length = state.posts.length;
      await state.toggleLike('does-not-exist');
      expect(state.posts.length, length);
    });
  });

  group('addComment', () {
    test('creates a comment remotely with the current user as author', () async {
      final first = state.posts.first;

      final comment = await state.addComment(first.id, 'Olá');

      expect(comment.text, 'Olá');
      expect(comment.author, state.currentUser!.name);
    });
  });

  group('loadComments', () {
    test('returns the list of comments for a post', () async {
      final first = state.posts.first;
      await state.addComment(first.id, 'Comentário 1');
      await state.addComment(first.id, 'Comentário 2');

      final comments = await state.loadComments(first.id);

      expect(comments.length, 2);
      expect(
        comments.map((c) => c.text),
        containsAll(['Comentário 1', 'Comentário 2']),
      );
    });
  });

  group('createPost', () {
    test('prepends a new post authored by the current user', () async {
      final initialLength = state.posts.length;
      final id = await state.createPost(text: 'Nova publicação');

      expect(state.posts.length, initialLength + 1);
      expect(state.posts.first.id, id);
      expect(state.posts.first.text, 'Nova publicação');
      expect(state.posts.first.authorUsername, state.currentUser!.username);
      expect(state.posts.first.likes, 0);
      expect(state.posts.first.liked, isFalse);
    });

    test('keeps imageUrl optional', () async {
      final id = await state.createPost(
        text: 'Com imagem',
        imageUrl: 'https://x/y.png',
      );
      expect(
        state.posts.firstWhere((p) => p.id == id).imageUrl,
        'https://x/y.png',
      );
    });
  });

  group('login', () {
    test('sets the current user', () async {
      await state.login(identifier: 'leonardo', password: 'whatever');
      expect(state.currentUser, isNotNull);
      expect(state.currentUser!.username, 'leonardo');
      expect(state.isAuthenticated, isTrue);
    });
  });

  group('logout', () {
    test('clears the current user and posts', () async {
      expect(state.isAuthenticated, isTrue);
      await state.logout();
      expect(state.isAuthenticated, isFalse);
      expect(state.posts, isEmpty);
    });
  });

  group('sendAkameMessage', () {
    test('adds the user message immediately', () {
      final initialLength = state.akameMessages.length;
      state.sendAkameMessage('Oi Akame');
      expect(state.akameMessages.length, initialLength + 1);
      expect(state.akameMessages.last.fromUser, isTrue);
      expect(state.akameMessages.last.text, 'Oi Akame');
    });

    test('produces an Akame reply after a delay', () async {
      final initialLength = state.akameMessages.length;
      state.sendAkameMessage('Oi');
      await Future.delayed(const Duration(milliseconds: 1100));
      expect(state.akameMessages.length, initialLength + 2);
      expect(state.akameMessages.last.fromUser, isFalse);
    });

    test('ignores empty messages', () {
      final initialLength = state.akameMessages.length;
      state.sendAkameMessage('   ');
      expect(state.akameMessages.length, initialLength);
    });
  });

  group('updateProfile', () {
    test('updates name and bio remotely', () async {
      await state.updateProfile(name: 'Neo', bio: 'The one');
      expect(state.currentUser!.name, 'Neo');
      expect(state.currentUser!.bio, 'The one');
    });

    test('preserves previous values when fields are null', () async {
      await state.updateProfile(name: 'Neo');
      expect(state.currentUser!.name, 'Neo');
      await state.updateProfile(bio: 'updated bio');
      expect(state.currentUser!.name, 'Neo');
      expect(state.currentUser!.bio, 'updated bio');
    });
  });
}
