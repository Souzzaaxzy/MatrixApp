/// A nickname visual effect from the SERVER-OWNED catalog (NAME_EFFECT).
///
/// The app never hardcodes which effects exist or invents render settings:
/// everything the renderer needs arrives in [config] (animation kind,
/// intensity, speed, particles, optional gradient palette). Color and
/// effect are fully independent — any nameColorId combines with any
/// nameEffectId. `null` effect = "Nenhum" (plain colored nickname).
class NameEffect {
  const NameEffect({
    required this.id,
    this.name = '',
    this.config = const {},
  });

  /// Catalog id (e.g. "glow", "glitch", "fire").
  final String id;

  /// Display name from the catalog.
  final String name;

  /// Render contract: {animation, intensity, speed, particles, colors?}.
  final Map<String, dynamic> config;

  /// Animation kind consumed by the NicknameRenderer (defaults to the
  /// catalog id so server-side aliases still resolve).
  String get animation => (config['animation'] as String?) ?? id;

  /// 0..1 — how strong the glow/distortion/particle density is.
  double get intensity =>
      ((config['intensity'] as num?) ?? 0.5).toDouble().clamp(0.0, 1.0);

  /// Animation speed multiplier (1 = catalog default).
  double get speed => ((config['speed'] as num?) ?? 1).toDouble();

  /// Whether the effect spawns floating particles (reduced in long lists
  /// to keep scrolling fluid).
  bool get particles => (config['particles'] as bool?) ?? false;

  /// Optional gradient palette (color/elemental effects). Independent of
  /// the nickname's base color — when present the effect animates between
  /// these server-provided hexes.
  List<String> get colors =>
      (config['colors'] as List?)?.whereType<String>().toList() ?? const [];

  factory NameEffect.fromJson(Map<String, dynamic> json) => NameEffect(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? '',
        config: (json['config'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}
