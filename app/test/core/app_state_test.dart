import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/services/app_state.dart';
import 'package:matrix_app/models/friend_request.dart';

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
    expect(state.currentUser!.nickname, isNotEmpty);
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

    test('rolls back the optimistic update when the API fails', () async {
      final failing = AppState(repositories: FakeRepositories(failLikes: true));
      await failing.restoreSession();
      await failing.loadFeed();
      final first = failing.posts.first;
      final initialLikes = first.likes;
      final initialLiked = first.liked;

      final ok = await failing.toggleLike(first.id);

      expect(ok, isFalse);
      expect(failing.posts.first.liked, initialLiked);
      expect(failing.posts.first.likes, initialLikes);
    });

    test('returns true when the server confirms the toggle', () async {
      final ok = await state.toggleLike(state.posts.first.id);
      expect(ok, isTrue);
    });
  });

  group('loadProfile', () {
    test('loads the user and their posts from the server', () async {
      await state.loadProfile('leonardo');
      final profile = state.profileFor('leonardo');
      expect(profile, isNotNull);
      expect(profile!.user.nickname, 'leonardo');
      expect(profile.posts, isNotEmpty);
      expect(
        profile.posts.every((p) => p.authorNickname == 'leonardo'),
        isTrue,
      );
    });

    test('keeps the session user in sync when viewing the own profile',
        () async {
      await state.updateProfile(nickname: 'Neo');
      await state.loadProfile('leonardo');
      expect(state.currentUser!.nickname, 'Neo');
    });
  });

  // Regression suite for the profile bug: the session user and the viewed
  // user live in separate slots — viewing a profile must NEVER overwrite
  // currentUser, and profiles must not bleed into each other.
  group('profile isolation (currentUser vs viewedUser)', () {
    test('viewing another profile never overwrites the session user',
        () async {
      await state.loadProfile('joao');
      expect(state.currentUser!.nickname, 'leonardo');
      expect(state.profileFor('joao')!.user.nickname, 'joao');
    });

    test('slots stay independent across A → B → A navigation', () async {
      await state.loadProfile('joao');
      await state.loadProfile('leonardo');
      expect(state.profileFor('joao')!.user.nickname, 'joao');
      expect(state.profileFor('leonardo')!.user.nickname, 'leonardo');
      expect(state.currentUser!.nickname, 'leonardo');
    });

    test('sendFriendRequest only touches that profile slot', () async {
      await state.loadProfile('joao');
      await state.sendFriendRequest('u2');
      expect(
        state.profileFor('joao')!.friendship,
        Friendship.outgoingPending,
      );
      expect(state.currentUser!.nickname, 'leonardo');
    });
  });

  group('getPost', () {
    test('fetches a post by id and caches it for engagement', () async {
      final post = await state.getPost('p1');
      expect(post.id, 'p1');
      // Likes work on the cached copy even if the post left the feed.
      final ok = await state.toggleLike('p1');
      expect(ok, isTrue);
      expect(post.liked, isTrue);
    });
  });

  group('addComment', () {
    test('creates a comment remotely with the current user as author', () async {
      final first = state.posts.first;

      final comment = await state.addComment(first.id, 'Olá');

      expect(comment.text, 'Olá');
      expect(comment.authorNickname, state.currentUser!.nickname);
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
      expect(state.posts.first.authorNickname, state.currentUser!.nickname);
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
      await state.login(nickname: 'leonardo', password: 'whatever');
      expect(state.currentUser, isNotNull);
      expect(state.currentUser!.nickname, 'leonardo');
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
      await state.updateProfile(nickname: 'Neo', bio: 'The one');
      expect(state.currentUser!.nickname, 'Neo');
      expect(state.currentUser!.bio, 'The one');
    });

    test('preserves previous values when fields are null', () async {
      await state.updateProfile(nickname: 'Neo');
      expect(state.currentUser!.nickname, 'Neo');
      await state.updateProfile(bio: 'updated bio');
      expect(state.currentUser!.nickname, 'Neo');
      expect(state.currentUser!.bio, 'updated bio');
    });
  });
}
