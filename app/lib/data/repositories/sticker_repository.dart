import '../api_client.dart';
import '../dtos/dtos.dart';
import '../../models/sticker.dart';

/// Sticker (figurinha) repository — the data layer for the sticker picker.
///
/// Talks ONLY to the existing MATRIX API (same auth/realtime/storage stack);
/// every endpoint hits the server catalog and the session user's persisted
/// installs/favorites/recents, so the picker state survives restarts.
class StickerRepository {
  StickerRepository(this._api);

  final ApiClient _api;

  /// Full active sticker catalog: every package with its stickers, each entry
  /// carrying the session user's `installed`/`favorited` flags.
  Future<List<StickerPackage>> catalog() async {
    final json = await _api.get<Map<String, dynamic>>('/api/stickers/packages');
    return (json['packages'] as List)
        .cast<Map<String, dynamic>>()
        .map(StickerPackageDto.fromJson)
        .map((d) => d.toModel())
        .toList();
  }

  /// One package by id (active only) with its stickers + user flags.
  Future<StickerPackage> package(String packageId) async {
    final json =
        await _api.get<Map<String, dynamic>>('/api/stickers/packages/$packageId');
    return StickerPackageDto.fromJson(json['package'] as Map<String, dynamic>)
        .toModel();
  }

  /// Installs a package for the session user (idempotent).
  Future<void> install(String packageId) async {
    await _api.post('/api/stickers/packages/$packageId/install');
  }

  /// Removes a package for the session user (idempotent). Favorites/history
  /// keep rendering — the sticker files are never deleted with the package.
  Future<void> uninstall(String packageId) async {
    await _api.delete('/api/stickers/packages/$packageId/install');
  }

  /// The session user's favorites, newest first.
  Future<List<Sticker>> favorites() async {
    final json = await _api.get<Map<String, dynamic>>('/api/stickers/favorites');
    return (json['stickers'] as List)
        .cast<Map<String, dynamic>>()
        .map(StickerDto.fromJson)
        .map((d) => d.toModel())
        .toList();
  }

  /// Favorites a sticker (idempotent).
  Future<void> favorite(String stickerId) async {
    await _api.post('/api/stickers/$stickerId/favorite');
  }

  /// Removes a favorite (idempotent).
  Future<void> unfavorite(String stickerId) async {
    await _api.delete('/api/stickers/$stickerId/favorite');
  }

  /// The session user's recents, newest first, deduped (bounded server-side).
  Future<List<Sticker>> recents() async {
    final json = await _api.get<Map<String, dynamic>>('/api/stickers/recents');
    return (json['stickers'] as List)
        .cast<Map<String, dynamic>>()
        .map(StickerDto.fromJson)
        .map((d) => d.toModel())
        .toList();
  }

  /// Registers a sticker as recently used (idempotent move-to-front).
  Future<void> markRecent(String stickerId) async {
    await _api.post('/api/stickers/$stickerId/recent');
  }
}