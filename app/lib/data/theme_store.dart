import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/services/theme_controller.dart';

/// Persists the theme preference (dark / light / system) next to the auth
/// tokens in the Keystore-backed secure storage.
///
/// Kept as a thin wrapper so it can be faked in widget tests — the same
/// pattern [TokenStore] uses.
class ThemeStore {
  ThemeStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _keyTheme = 'matrix.theme_mode';

  /// Reads the saved mode. Unknown/absent values fall back to `dark` (the
  /// classic MATRIX look).
  Future<MatrixThemeMode> read() async {
    final raw = await _storage.read(key: _keyTheme);
    for (final mode in MatrixThemeMode.values) {
      if (mode.name == raw) return mode;
    }
    return MatrixThemeMode.dark;
  }

  Future<void> write(MatrixThemeMode mode) =>
      _storage.write(key: _keyTheme, value: mode.name);
}
