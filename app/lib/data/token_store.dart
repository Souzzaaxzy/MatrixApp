import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the access/refresh token pair securely (Keystore/Keychain).
///
/// Kept as a thin wrapper so it can be faked in widget tests.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  final FlutterSecureStorage _storage;

  static const _keyAccess = 'matrix.access_token';
  static const _keyRefresh = 'matrix.refresh_token';

  Future<String?> get accessToken => _storage.read(key: _keyAccess);
  Future<String?> get refreshToken => _storage.read(key: _keyRefresh);

  Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _keyAccess, value: accessToken);
    await _storage.write(key: _keyRefresh, value: refreshToken);
  }

  Future<void> clear() async {
    await _storage.delete(key: _keyAccess);
    await _storage.delete(key: _keyRefresh);
  }
}
