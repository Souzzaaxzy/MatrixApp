import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../models/conversation.dart';
import '../../models/matrix_user.dart';

/// Route arguments for a private conversation screen.
///
/// Carries everything the screen needs to render immediately (the OTHER
/// user's nickname + cosmetics for the header) plus the conversation id
/// when it already exists. `conversationId` may be empty when opening from
/// a profile/search/friend that has no conversation yet — the screen
/// get-or-creates it before loading messages.
class ConversationRouteArgs {
  const ConversationRouteArgs({
    required this.conversationId,
    required this.otherUserId,
    required this.otherNickname,
    this.otherAvatarUrl,
    this.otherNameColor,
    this.otherFrameId,
    this.otherFrameAsset,
  });

  /// A conversation loaded from the list (already exists).
  factory ConversationRouteArgs.fromConversation(Conversation c) =>
      ConversationRouteArgs(
        conversationId: c.id,
        otherUserId: c.otherUser.id,
        otherNickname: c.otherUser.nickname,
        otherAvatarUrl: c.otherUser.avatarUrl,
        otherNameColor: c.otherUser.nameColor,
        otherFrameId: c.otherUser.frameId,
        otherFrameAsset: c.otherUser.frameAsset,
      );

  /// Opens with another user (from a search result, a friend, a profile
  /// "Mensagem") — the conversation may not exist yet.
  factory ConversationRouteArgs.fromUser(MatrixUser user) =>
      ConversationRouteArgs(
        conversationId: '',
        otherUserId: user.id,
        otherNickname: user.nickname,
        otherAvatarUrl: user.avatarUrl,
        otherNameColor: user.nameColor,
        otherFrameId: user.frameId,
        otherFrameAsset: user.frameAsset,
      );

  final String conversationId;
  final String otherUserId;
  final String otherNickname;
  final String? otherAvatarUrl;
  final String? otherNameColor;
  final String? otherFrameId;
  final String? otherFrameAsset;

  /// A lightweight ChatUser matching the route payload (used to synthesize
  /// a cached conversation when a realtime message arrives for a
  /// conversation we haven't loaded yet).
  ChatUser get otherUser => ChatUser(
        id: otherUserId,
        nickname: otherNickname,
        avatarUrl: otherAvatarUrl,
        nameColor: otherNameColor,
        frameId: otherFrameId,
        frameAsset: otherFrameAsset,
      );
}

/// Pushes the private conversation screen. Every chat entry point
/// (search / friends / conversations list / profile "Mensagem") reaches the
/// SAME screen through this helper — there is exactly one conversation UI.
void openConversation(BuildContext context, ConversationRouteArgs args) {
  if (args.otherUserId.isEmpty) return;
  Navigator.of(context).pushNamed(AppRoutes.conversation, arguments: args);
}

/// Public helper used by the profile "Mensagem" button and friend tiles.
void openChatWithUser(BuildContext context, MatrixUser user) {
  openConversation(context, ConversationRouteArgs.fromUser(user));
}

/// Public helper used by the Chat tab's conversation list.
void openChatConversation(
  BuildContext context,
  Conversation conversation,
) {
  openConversation(context, ConversationRouteArgs.fromConversation(conversation));
}