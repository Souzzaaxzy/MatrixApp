import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/widgets/nickname_renderer.dart';
import 'package:matrix_app/features/notifications/notifications_screen.dart';
import 'package:matrix_app/models/friend_request.dart';
import 'package:matrix_app/models/matrix_notification.dart';
import 'package:matrix_app/models/matrix_user.dart';

import '../helpers/test_app.dart';

MatrixNotification _notification({
  required String id,
  required String type,
  String? postId,
  String? commentId,
  String? friendRequestId,
  String? friendRequestStatus,
  bool read = false,
}) {
  return MatrixNotification(
    id: id,
    type: type,
    read: read,
    createdAt: DateTime(2024, 1, 10, 12),
    actorId: 'u2',
    actorNickname: 'joao',
    postId: postId,
    commentId: commentId,
    friendRequestId: friendRequestId,
    friendRequestStatus: friendRequestStatus,
  );
}

FriendRequest _request(String id) {
  return FriendRequest(
    id: id,
    status: 'PENDING',
    createdAt: DateTime(2024, 1, 10),
    sender: MatrixUser(id: 'u2', nickname: 'joao'),
    receiverId: 'u0',
  );
}

void main() {
  testWidgets('shows the ALL CLEAR empty state without notifications', (tester) async {
    await pumpMatrixApp(tester, const NotificationsScreen());
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('ATIVIDADES'), findsOneWidget);
    expect(find.text('ALL CLEAR'), findsOneWidget);
  });

  testWidgets(
      'friend accepted shows the actor nickname (without "@") and opens the '
      'friend profile on tap', (tester) async {
    final state = await seededAppStateWithSocial(notifications: [
      _notification(id: 'n9', type: 'FRIEND_ACCEPTED', read: false),
    ]);
    await pumpMatrixApp(tester, const NotificationsScreen(), state: state);
    await tester.pump(const Duration(milliseconds: 400));

    // The actor's nickname renders through the shared NicknameRenderer
    // (color of the ACTOR), so the message spans are split.
    expect(find.textContaining('Agora você e', findRichText: true), findsOneWidget);
    expect(find.textContaining('são amigos.', findRichText: true), findsOneWidget);
    final actor = find.byWidgetPredicate(
      (w) => w is NicknameRenderer && w.text == 'joao',
    );
    expect(actor, findsOneWidget);

    final message = find.textContaining('Agora você e', findRichText: true);
    await tester.tap(message);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));

    // Opens the friend's profile (respecting currentUser ≠ viewedUser).
    expect(find.text('ADICIONAR'), findsOneWidget);
    expect(find.textContaining('joao', findRichText: true), findsWidgets);
  });

  testWidgets('renders like notification with actor, description and unread state', (tester) async {
    final state = await seededAppStateWithSocial(notifications: [
      _notification(id: 'n1', type: 'LIKE', postId: 'p1'),
    ]);
    await pumpMatrixApp(tester, const NotificationsScreen(), state: state);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('joao', findRichText: true), findsOneWidget);
    expect(find.textContaining('curtiu sua publicação.', findRichText: true), findsOneWidget);
    expect(find.text('há'), findsNothing); // relative time shows "há 2 min"-style
    expect(state.unreadNotifications, 1);
  });

  testWidgets('friend request card shows Aceitar / Recusar; Aceitar creates friendship', (tester) async {
    final state = await seededAppStateWithSocial(
      notifications: [
        _notification(
          id: 'n2',
          type: 'FRIEND_REQUEST',
          friendRequestId: 'fr_u2_u0',
          friendRequestStatus: 'PENDING',
        ),
      ],
      friendRequests: [_request('fr_u2_u0')],
    );
    await pumpMatrixApp(tester, const NotificationsScreen(), state: state);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('enviou uma solicitação de amizade.'), findsOneWidget);
    expect(find.text('ACEITAR'), findsOneWidget);
    expect(find.text('RECUSAR'), findsOneWidget);

    await tester.tap(find.text('ACEITAR'));
    await tester.pump(const Duration(milliseconds: 400));

    // The actionable card disappears once accepted and the counter updates.
    expect(find.text('ACEITAR'), findsNothing);
    expect(find.text('RECUSAR'), findsNothing);
    expect(find.text('ALL CLEAR'), findsOneWidget);
    expect(state.unreadNotifications, 0);
  });

  testWidgets('Recusar removes the request card', (tester) async {
    final state = await seededAppStateWithSocial(
      notifications: [
        _notification(
          id: 'n3',
          type: 'FRIEND_REQUEST',
          friendRequestId: 'fr_u2_u0b',
          friendRequestStatus: 'PENDING',
        ),
      ],
      friendRequests: [_request('fr_u2_u0b')],
    );
    await pumpMatrixApp(tester, const NotificationsScreen(), state: state);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('RECUSAR'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('ACEITAR'), findsNothing);
    expect(find.text('ALL CLEAR'), findsOneWidget);
  });

  testWidgets('mark-all-read clears the unread counter', (tester) async {
    final state = await seededAppStateWithSocial(notifications: [
      _notification(id: 'n4', type: 'LIKE', postId: 'p1'),
    ]);
    await pumpMatrixApp(tester, const NotificationsScreen(), state: state);
    await tester.pump(const Duration(milliseconds: 400));

    expect(state.unreadNotifications, 1);

    await tester.tap(find.byIcon(Icons.checklist_rounded));
    await tester.pump(const Duration(milliseconds: 400));

    expect(state.unreadNotifications, 0);
  });

  testWidgets('tapping a comment notification opens the post detail', (tester) async {
    final state = await seededAppStateWithSocial(notifications: [
      _notification(id: 'n5', type: 'COMMENT', postId: 'p1', commentId: 'c1'),
    ]);
    await pumpMatrixApp(tester, const NotificationsScreen(), state: state);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.textContaining('comentou na sua publicação.', findRichText: true));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));

    // Post detail header.
    expect(find.text('PUBLICAÇÃO'), findsOneWidget);
    // Opening the notification marks it as read.
    expect(state.unreadNotifications, 0);
  });
}
