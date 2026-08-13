import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';

void main() {
  late AppState state;

  setUp(() {
    state = AppState();
  });

  test('initial state loads mocked posts and akame messages', () {
    expect(state.posts, isNotEmpty);
    expect(state.akameMessages, isNotEmpty);
    expect(state.currentUser.name, isNotEmpty);
  });

  group('toggleLike', () {
    test('increments likes and sets liked when toggled on', () {
      final first = state.posts.first;
      final initial = first.likes;
      final wasLiked = first.liked;

      state.toggleLike(first.id);

      expect(state.posts.first.liked, !wasLiked);
      expect(state.posts.first.likes, wasLiked ? initial - 1 : initial + 1);
    });

    test('is reversible — toggling twice returns to the original count', () {
      final first = state.posts.first;
      final initialLikes = first.likes;
      final initialLiked = first.liked;

      state.toggleLike(first.id);
      state.toggleLike(first.id);

      expect(state.posts.first.likes, initialLikes);
      expect(state.posts.first.liked, initialLiked);
    });

    test('does nothing for an unknown post id', () {
      final length = state.posts.length;
      state.toggleLike('does-not-exist');
      expect(state.posts.length, length);
    });
  });

  group('addComment', () {
    test('appends a comment from the current user', () {
      final first = state.posts.first;
      final initialCount = first.comments.length;

      state.addComment(first.id, 'Olá');

      expect(state.posts.first.comments.length, initialCount + 1);
      expect(state.posts.first.comments.last.text, 'Olá');
      expect(state.posts.first.comments.last.author, state.currentUser.name);
    });

    test('ignores empty comments', () {
      final first = state.posts.first;
      final initialCount = first.comments.length;

      state.addComment(first.id, '   ');

      expect(state.posts.first.comments.length, initialCount);
    });
  });

  group('createPost', () {
    test('prepends a new post authored by the current user', () {
      final initialLength = state.posts.length;
      final id = state.createPost(text: 'Nova publicação');

      expect(state.posts.length, initialLength + 1);
      expect(state.posts.first.id, id);
      expect(state.posts.first.text, 'Nova publicação');
      expect(state.posts.first.authorUsername, state.currentUser.username);
      expect(state.posts.first.likes, 0);
      expect(state.posts.first.liked, isFalse);
    });

    test('keeps imageUrl optional', () {
      final id = state.createPost(text: 'Com imagem', imageUrl: 'file://x');
      expect(state.posts.firstWhere((p) => p.id == id).imageUrl, 'file://x');
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
    test('updates name, username and bio locally', () {
      state.updateProfile(name: 'Neo', username: 'neo', bio: 'The one');
      expect(state.currentUser.name, 'Neo');
      expect(state.currentUser.username, 'neo');
      expect(state.currentUser.bio, 'The one');
    });

    test('preserves previous values when fields are null', () {
      state.updateProfile(name: 'Neo');
      expect(state.currentUser.name, 'Neo');
      state.updateProfile(bio: 'updated bio');
      expect(state.currentUser.name, 'Neo');
      expect(state.currentUser.bio, 'updated bio');
    });
  });
}
