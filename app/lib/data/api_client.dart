import 'dart:async';

import 'package:dio/dio.dart';

import 'api_config.dart';
import 'token_store.dart';

/// Builds and configures the singleton [Dio] instance used across the app.
///
/// Two interceptors are attached:
/// 1. [_AuthInterceptor] — attaches the bearer access token to every request
///    and transparently refreshes it once on a 401, then retries.
/// 2. A response normalizer that converts non-2xx responses into
///    [ApiException] (the backend already returns a normalized error body).
class ApiClient {
  ApiClient({required TokenStore tokenStore, Dio? dio})
      : _tokenStore = tokenStore,
        _dio = dio ?? Dio() {
    _configure(_dio);
    _dio.interceptors.add(_AuthInterceptor(this, _tokenStore));
  }

  final TokenStore _tokenStore;
  final Dio _dio;
  final StreamController<void> _unauthController =
      StreamController<void>.broadcast();

  /// Notifies the app when the session is invalid (refresh failed) so it can
  /// navigate back to the login screen.
  Stream<void> get onSessionExpired => _unauthController.stream;

  Dio get dio => _dio;
  TokenStore get tokenStore => _tokenStore;

  void _configure(Dio dio) {
    dio
      ..options.baseUrl = ApiConfig.baseUrl
      ..options.connectTimeout = ApiConfig.connectTimeout
      ..options.receiveTimeout = ApiConfig.receiveTimeout;
    // NOTE: do NOT set a global contentType here. Dio already sends
    // application/json automatically when a request carries a Map body, and
    // a global value would also be attached to BODILESS posts (e.g. the like
    // toggle) — Fastify rejects 'Content-Type: application/json' with an
    // empty body, which is exactly what broke likes.
  }

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      _request<T>(() => _dio.get<T>(
            path,
            queryParameters: queryParameters,
            options: options,
          ));

  Future<T> post<T>(
    String path, {
    Object? data,
    Options? options,
  }) =>
      _request<T>(() => _dio.post<T>(path, data: data, options: options));

  Future<T> patch<T>(
    String path, {
    Object? data,
    Options? options,
  }) =>
      _request<T>(() => _dio.patch<T>(path, data: data, options: options));

  Future<T> delete<T>(String path, {Options? options}) =>
      _request<T>(() => _dio.delete<T>(path, options: options));

  /// Sends a multipart upload (for images).
  Future<T> upload<T>(
    String path, {
    required MultipartFile file,
    Options? options,
  }) async {
    final form = FormData.fromMap({'file': file});
    return _request<T>(() => _dio.post<T>(
          path,
          data: form,
          options: options?.copyWith(
            contentType: 'multipart/form-data',
          ),
        ));
  }

  Future<T> _request<T>(Future<Response<T>> Function() send) async {
    try {
      final response = await send();
      return response.data as T;
    } on DioException catch (err) {
      throw ApiException.fromDioError(err);
    }
  }

  /// Used by the auth interceptor to refresh the access token once.
  Future<bool> refreshSession() async {
    final refresh = await _tokenStore.refreshToken;
    if (refresh == null) return false;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/auth/refresh',
        data: {'refreshToken': refresh},
      );
      final data = response.data!;
      await _tokenStore.save(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
      );
      return true;
    } on DioException {
      await _tokenStore.clear();
      _unauthController.add(null);
      return false;
    }
  }

  void dispose() => _unauthController.close();
}

/// Attaches the bearer token and performs a single refresh-on-401 retry.
class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._client, this._tokenStore);

  final ApiClient _client;
  final TokenStore _tokenStore;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // The refresh endpoint authenticates with the refresh token in the body;
    // never attach an (expired) access token to it.
    if (options.path == '/api/auth/refresh' ||
        options.path == '/api/auth/login' ||
        options.path == '/api/auth/register' ||
        options.path == '/api/auth/recover') {
      return handler.next(options);
    }
    final token = await _tokenStore.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final isUnauthorized =
        err.response?.statusCode == 401 &&
            err.requestOptions.path != '/api/auth/refresh' &&
            err.requestOptions.path != '/api/auth/login';

    if (!isUnauthorized) {
      return handler.next(err);
    }

    final refreshed = await _client.refreshSession();
    if (!refreshed) {
      return handler.next(err);
    }

    // Replay the original request with the new token.
    final newToken = await _tokenStore.accessToken;
    err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
    try {
      final response = await _client.dio.fetch(err.requestOptions);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
