import 'package:flutter/material.dart';

import '../../data/theme_store.dart';

/// User-selectable theme option persisted locally ("theme = dark/light/system").
enum MatrixThemeMode { dark, light, system }

/// Global theme controller: holds the user's preference, persists it via
/// [ThemeStore], and notifies the root [MaterialApp] to rebuild.
///
/// The `system` mode follows platform brightness changes (a
/// [WidgetsBindingObserver] emits [notifyListeners] when Android flips
/// dark/light), so the MatrixApp re-resolves and follows the phone.
class ThemeController extends ChangeNotifier with WidgetsBindingObserver {
  ThemeController._({ThemeStore? store}) : _store = store ?? ThemeStore() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final ThemeController instance = ThemeController._();

  /// Test-only entry point with an injectable (in-memory) store.
  @visibleForTesting
  factory ThemeController.debug(ThemeStore store) =>
      ThemeController._(store: store);

  final ThemeStore _store;

  MatrixThemeMode _mode = MatrixThemeMode.dark;

  MatrixThemeMode get mode => _mode;

  ThemeMode get materialMode => switch (_mode) {
        MatrixThemeMode.dark => ThemeMode.dark,
        MatrixThemeMode.light => ThemeMode.light,
        MatrixThemeMode.system => ThemeMode.system,
      };

  /// Platform brightness changed -> re-resolve the effective theme so
  /// `system` follows the phone live.
  @override
  void didChangePlatformBrightness() {
    notifyListeners();
  }

  /// Loads the persisted preference. Called once by Services.init().
  Future<void> load() async {
    try {
      _mode = await _store.read();
    } catch (_) {
      _mode = MatrixThemeMode.dark;
    }
    notifyListeners();
  }

  /// Changes the mode and persists it. Re-calling [load] afterwards keeps
  /// the chosen value — this is what makes the theme survive restarts.
  Future<void> setMode(MatrixThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    try {
      await _store.write(mode);
    } catch (_) {
      // Persistence is best-effort: the in-memory mode already applied.
    }
  }
}
