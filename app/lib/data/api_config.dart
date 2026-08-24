import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Resolves the backend base URL for the current build mode.
///
/// In debug (local dev) it points to the Android emulator's host-loopback
/// alias (10.0.2.2) so the app can reach the API running on the developer
/// machine. In release it uses the production API URL (configurable via
/// `--dart-define=API_BASE_URL=...`).
class ApiConfig {
  const ApiConfig._();

  static String get baseUrl {
    // Highest priority: build-time override (`--dart-define=API_BASE_URL=...`).
    // The CI release build injects this from the API_BASE_URL secret.
    const defined = String.fromEnvironment('API_BASE_URL');
    if (defined.isNotEmpty) return defined;

    if (kReleaseMode) {
      // Production default — the MATRIX API hosted on the panel
      // (Pterodactyl/Bronxys). Update this to your server's public URL, or
      // (better) set the API_BASE_URL secret so the CI build injects it.
      // Must be reachable from the device; do NOT use localhost/10.0.2.2 here.
      return _productionUrl;
    }
    // Debug default — the Android emulator maps 10.0.2.2 to the host machine's
    // localhost (where `npm start` / `npm run dev` runs the API).
    return 'http://10.0.2.2:3000';
  }

  /// Production API URL used when no `--dart-define` override is provided.
  /// Can also be overridden at build time with `--dart-define=API_PROD_URL=...`.
  static const String _productionUrl = String.fromEnvironment(
    'API_PROD_URL',
    defaultValue: 'https://api.matrix.app',
  );

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);
}

/// Typed exception raised by the API layer. Carries an HTTP status code and
/// a human-readable message (already translated/normalized by the backend).
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.message,
    this.code,
  });

  final int statusCode;
  final String message;
  final String? code;

  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;
  bool get isValidation => statusCode == 400;
  bool get isConflict => statusCode == 409;

  @override
  String toString() => 'ApiException($statusCode): $message';

  /// Converts a Dio error into an [ApiException], extracting the backend's
  /// normalized `{ "error": { "message": "..." } }` envelope when present.
  factory ApiException.fromDioError(DioException err) {
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      return const ApiException(
        statusCode: 0,
        message: 'Tempo de conexão esgotado. Verifique sua internet.',
      );
    }
    if (err.type == DioExceptionType.connectionError) {
      return const ApiException(
        statusCode: 0,
        message: 'Não foi possível conectar ao servidor.',
      );
    }

    final response = err.response;
    if (response == null) {
      return ApiException(
        statusCode: 0,
        message: err.message ?? 'Erro desconhecido.',
      );
    }

    final data = response.data;
    String message = 'Ocorreu um erro inesperado.';
    String? code;
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is Map<String, dynamic>) {
        message = (error['message'] as String?) ?? message;
        code = error['code'] as String?;
      } else if (data['message'] is String) {
        message = data['message'] as String;
      }
    }

    return ApiException(
      statusCode: response.statusCode ?? 0,
      message: message,
      code: code,
    );
  }
}
