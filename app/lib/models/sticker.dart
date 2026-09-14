/// One sticker from the server catalog. Carries the persisted file reference
/// ([fileUrl], absolute) plus its package context and the session user's
/// favorite state ([favorited]).
class Sticker {
  const Sticker({
    required this.id,
    required this.packageId,
    required this.order,
    required this.fileUrl,
    this.thumbUrl,
    this.width,
    this.height,
    this.favorited = false,
  });

  final String id;
  final String packageId;
  final int order;
  final String fileUrl;
  final String? thumbUrl;
  final int? width;
  final int? height;
  final bool favorited;

  Sticker copyWith({bool? favorited}) => Sticker(
        id: id,
        packageId: packageId,
        order: order,
        fileUrl: fileUrl,
        thumbUrl: thumbUrl,
        width: width,
        height: height,
        favorited: favorited ?? this.favorited,
      );
}

/// A sticker package (server-owned catalog entry). `installed` is the session
/// user's current install state; `stickers` carries the full grid content.
class StickerPackage {
  const StickerPackage({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.author,
    required this.iconUrl,
    required this.installed,
    required this.stickerCount,
    required this.stickers,
  });

  final String id;
  final String name;
  final String slug;
  final String description;
  final String author;
  final String iconUrl;
  final bool installed;
  final int stickerCount;
  final List<Sticker> stickers;

  StickerPackage copyWith({bool? installed}) => StickerPackage(
        id: id,
        name: name,
        slug: slug,
        description: description,
        author: author,
        iconUrl: iconUrl,
        installed: installed ?? this.installed,
        stickerCount: stickerCount,
        stickers: stickers,
      );

  /// Returns a copy with one sticker replaced via [update].
  StickerPackage replaceSticker(String stickerId, Sticker Function(Sticker) update) =>
      StickerPackage(
        id: id,
        name: name,
        slug: slug,
        description: description,
        author: author,
        iconUrl: iconUrl,
        installed: installed,
        stickerCount: stickerCount,
        stickers: stickers
            .map((s) => s.id == stickerId ? update(s) : s)
            .toList(),
      );
}

/// A received sticker reference embedded in a chat message. The image URL is
/// persisted (never tied to the package), so history/favorites always render.
class StickerRef {
  const StickerRef({
    required this.id,
    required this.packageId,
    required this.url,
  });

  final String id;
  final String packageId;
  final String url;
}