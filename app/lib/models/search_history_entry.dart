import 'matrix_user.dart';

/// One entry of the per-user search history ("Pesquisas recentes").
///
/// Lightweight snapshot of the visited profile (no counters, no full
/// cosmetic map) so the search screen can render the list offline instantly
/// from the persisted store. [frameId]/[frameAsset] drive the frame look.
class SearchHistoryEntry {
  const SearchHistoryEntry({
    required this.userId,
    required this.nickname,
    this.avatarSeed,
    this.avatarUrl,
    this.nameColor,
    this.frameId,
    this.frameAsset,
  });

  final String userId;
  final String nickname;
  final String? avatarSeed;
  final String? avatarUrl;
  final String? nameColor;
  final String? frameId;
  final String? frameAsset;

  factory SearchHistoryEntry.fromUser(MatrixUser user) => SearchHistoryEntry(
        userId: user.id,
        nickname: user.nickname,
        avatarSeed: user.avatarSeed,
        avatarUrl: user.avatarUrl,
        nameColor: user.nameColor,
        frameId: user.frameId,
        frameAsset: user.frameAsset,
      );

  factory SearchHistoryEntry.fromJson(Map<String, dynamic> json) =>
      SearchHistoryEntry(
        userId: json['userId'] as String,
        nickname: json['nickname'] as String,
        avatarSeed: json['avatarSeed'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        nameColor: json['nameColor'] as String?,
        frameId: json['frameId'] as String?,
        frameAsset: json['frameAsset'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'nickname': nickname,
        'avatarSeed': avatarSeed,
        'avatarUrl': avatarUrl,
        'nameColor': nameColor,
        'frameId': frameId,
        'frameAsset': frameAsset,
      };

  /// Builds a lightweight [MatrixUser] capable of opening the profile.v
  MatrixUser toUser() => MatrixUser(
        id: userId,
        nickname: nickname,
        avatarSeed: avatarSeed,
        avatarUrl: avatarUrl,
        nameColor: nameColor,
        frameId: frameId,
        frameAsset: frameAsset,
      );
}