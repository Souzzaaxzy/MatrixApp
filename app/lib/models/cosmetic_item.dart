/// A server-owned cosmetic item (avatar frame, badge, profile effect, ...).
///
/// Cosmetics are pure DATA: the server owns the catalog, rarity and who owns
/// what. The app maps generic slots to renderers (`FramedAvatar`,
/// `CosmeticBadgeView`, ...) so adding a new cosmetic never requires
/// reworking the profile or this model.
class CosmeticItem {
  const CosmeticItem({
    required this.id,
    required this.slot,
    required this.name,
    this.assetUrl = '',
    this.rarity = 'COMMON',
    this.category,
    this.sortOrder = 0,
  });

  /// Server id of the item in the catalog.
  final String id;

  /// Slot/type: AVATAR_FRAME, PROFILE_BANNER, BADGE, PROFILE_EFFECT,
  /// THEME_ACCCENT (extensible — new server types arrive as plain strings).
  final String slot;

  final String name;

  /// Asset reference (may be a relative path key or a full URL).
  final String assetUrl;

  /// COMMON / UNCOMMON / RARE / EPIC / LEGENDARY (extensible).
  final String rarity;

  /// Server-owned grouping key for the picker UI (e.g. "reds", "special").
  /// Null for items without a group.
  final String? category;

  /// Curated ordering inside a category (catalogs are curated server-side,
  /// not alphabetical).
  final int sortOrder;

  /// For NAME_COLOR items the assetUrl IS the hex value ("#0066FF") — the
  /// server owns the palette, so the app never invents color values.
  String? get hexColor =>
      slot == nameColor && assetUrl.startsWith('#') ? assetUrl : null;

  /// Slot keys — mirror the server enum; kept as strings so new slots are
  /// forward-compatible.
  static const String avatarFrame = 'AVATAR_FRAME';
  static const String profileBanner = 'PROFILE_BANNER';
  static const String badge = 'BADGE';
  static const String profileEffect = 'PROFILE_EFFECT';
  static const String themeAccent = 'THEME_ACCCENT';
  static const String nameColor = 'NAME_COLOR';
}

/// Equipped cosmetics keyed by slot. An empty map means "all defaults"
/// (no frame, default name style, no badge) — the spec's "Nenhuma".
typedef CosmeticMap = Map<String, CosmeticItem>;
