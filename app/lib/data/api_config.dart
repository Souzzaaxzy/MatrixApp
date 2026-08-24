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

  /// URL oficial da API em produção — a ÚNICA API do app.
  ///
  /// É o endereço público REAL do ServidorMtx hospedado na
  /// Bronxys/Pterodactyl: o IP/host público do node + a porta alocada,
  /// visível na página do servidor no painel (seção de alocação/network),
  /// ex.: `http://123.45.67.89:4316`. Use HTTPS somente se o painel
  /// fornecer um domínio/proxy com SSL válido. NUNCA use localhost,
  /// 127.0.0.1, 0.0.0.0 ou 10.0.2.2 aqui — esses endereços só existem
  /// dentro do servidor/emulador.
  ///
  /// Prioridade: `--dart-define=API_BASE_URL=...` (o CI injeta a partir do
  /// secret API_BASE_URL) → esta constante. Sem barra final.
  static const String _productionUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String get baseUrl {
    if (_productionUrl.isNotEmpty) return _productionUrl;

    if (kReleaseMode) {
      // Falha explícita em vez de apontar para um endereço errado: um APK
      // de produção sem URL configurada não conseguiria falar com API
      // nenhuma, e o erro precisa ser óbvio no build, não no celular.
      throw StateError(
        'API_BASE_URL não configurada. Configure o secret API_BASE_URL no '
        'GitHub Actions (usado pelo build de release) ou preencha '
        '_productionUrl em lib/data/api_config.dart com o endereço público '
        'do servidor no painel Bronxys/Pterodactyl.',
      );
    }
    // Debug default — o emulador Android mapeia 10.0.2.2 para o localhost
    // da máquina de desenvolvimento (onde `npm start` roda a API).
    return 'http://10.0.2.2:3000';
  }

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
  /// Each failure mode maps to a DISTINCT message so the user (and support)
  /// can tell a wrong password apart from a dead server or a bad
  /// certificate.
  factory ApiException.fromDioError(DioException err) {
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      return const ApiException(
        statusCode: 0,
        message: 'O servidor não respondeu a tempo. Tente novamente.',
      );
    }
    if (err.type == DioExceptionType.badCertificate || _isTlsError(err)) {
      return const ApiException(
        statusCode: 0,
        message:
            'Erro de certificado SSL. A URL da API pode estar usando HTTPS '
            'sem um certificado válido.',
      );
    }
    if (err.type == DioExceptionType.connectionError) {
      return const ApiException(
        statusCode: 0,
        message:
            'Não foi possível conectar ao servidor. Verifique sua internet '
            'e se a API está online.',
      );
    }

    final response = err.response;
    if (response == null) {
      return ApiException(
        statusCode: 0,
        message: err.message ?? 'Erro desconhecido.',
      );
    }

    final statusCode = response.statusCode ?? 0;
    final data = response.data;
    String? message;
    String? code;
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is Map<String, dynamic>) {
        message = error['message'] as String?;
        code = error['code'] as String?;
        // 400 envelope carries per-field details — surface the first one
        // (e.g. "A senha deve ter no mínimo 8 caracteres") instead of the
        // generic "Dados inválidos.".
        final details = error['details'];
        if (details is List && details.isNotEmpty) {
          final first = details.first;
          if (first is Map<String, dynamic> && first['message'] is String) {
            message = first['message'] as String;
          }
        }
      } else if (data['message'] is String) {
        message = data['message'] as String;
      }
    }

    return ApiException(
      statusCode: statusCode,
      message: message ?? _statusFallback(statusCode),
      code: code,
    );
  }

  /// TLS/SSL failures surface as connectionError wrapping a handshake
  /// exception — detect them so they aren't mislabeled as "server offline".
  static bool _isTlsError(DioException err) {
    final cause = err.error;
    if (cause == null) return false;
    final text = cause.toString();
    return text.contains('HandshakeException') ||
        text.contains('CertificateException') ||
        text.contains('TlsException');
  }

  static String _statusFallback(int statusCode) {
    if (statusCode == 400) return 'Dados inválidos.';
    if (statusCode == 401) return 'Credenciais inválidas.';
    if (statusCode == 403) return 'Acesso negado.';
    if (statusCode == 404) return 'Recurso não encontrado no servidor.';
    if (statusCode == 409) return 'Este registro já existe.';
    if (statusCode == 429) {
      return 'Muitas tentativas. Aguarde um momento e tente novamente.';
    }
    if (statusCode >= 500) return 'Erro interno do servidor.';
    return 'Ocorreu um erro inesperado.';
  }
}
