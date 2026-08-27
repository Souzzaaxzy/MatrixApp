import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../models/matrix_user.dart';

/// Real user ids of the profiles currently visible in the navigation stack
/// (the own-profile tab plus any pushed ProfileScreen routes). This is the
/// guard for the "never open the same profile twice" rule: if the tapped user
/// is ALREADY open somewhere in the stack, tapping its photo/nickname is a
/// no-op (no duplicate route, no loop, no extra frame of build work).
/// Compared by REAL id — never by nickname (mutable) or visual state.
///
/// The stack is maintained by [ProfileScreen]: it marks its resolved user id
/// open on load (including the own tab) and closes it on dispose for pushed
/// routes.
final Set<String> _openProfileIds = {};

/// Marks the profile of [userId] as currently open (own tab or a pushed
/// profile route that has resolved the viewed user's id).
void markProfileOpen(String userId) {
  if (userId.isNotEmpty) _openProfileIds.add(userId);
}

/// Marks the profile of [userId] as closed (a pushed ProfileScreen was
/// disposed / popped). The persistent own-profile tab is not removed by the
/// screen that owns it.
void closeProfile(String userId) {
  if (userId.isNotEmpty) _openProfileIds.remove(userId);
}

/// Whether a profile for [userId] is currently open in the stack.
bool isProfileOpen(String userId) => _openProfileIds.contains(userId);

/// Opens the profile of [user] on the root navigator (host apps push by the
/// user's nickname, which the server resolves case-insensitively to the real
/// user). If that user's profile is already open (same real id anywhere in
/// the stack), this is a no-op — nothing navigates, no duplicate route, no
/// loop.
void openUserProfile(BuildContext context, MatrixUser user) {
  if (user.id.isEmpty) return;
  if (isProfileOpen(user.id)) return;
  Navigator.of(context).pushNamed(AppRoutes.profile, arguments: user.nickname);
}

/// Opens a profile from a lightweight author payload (feed post, comment)
/// that carries the real user id + nickname but not a full [MatrixUser].
/// Same no-op guard as [openUserProfile].
void openProfileById(
  BuildContext context, {
  required String id,
  required String nickname,
}) {
  if (id.isEmpty || nickname.isEmpty) return;
  if (isProfileOpen(id)) return;
  Navigator.of(context).pushNamed(AppRoutes.profile, arguments: nickname);
}

/// Test-only hook: clears all recorded open-profile ids. The app never calls
/// this — it keeps every open profile tracked for the app lifetime.
@visibleForTesting
void resetProfileTracking() => _openProfileIds.clear();