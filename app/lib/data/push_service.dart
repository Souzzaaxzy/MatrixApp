import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';
import 'api_config.dart';
import 'token_store.dart';

/// MATRIX push service — native Android notifications driven by the
/// ServidorMtx realtime channel (WebSocket) plus a device-token registry
/// on the server. No Google/Firebase services involved.
///
/// Lifecycle:
///   login/register/restore → [sync]  (register token + open socket)
///   logout                 → [stop]  (unregister token + close socket)
///
/// Dedupe: each server notification carries a unique id; the service shows
/// each id at most once per session, mirroring the server-side dedupe.
class PushService {
  PushService({required ApiClient api, required TokenStore tokenStore})
      : _api = api,
        _tokenStore = tokenStore;

  final ApiClient _api;
  final TokenStore _tokenStore;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Called when the user taps a native notification. Receives the routing
  /// payload (type / actorUsername / postId / commentId / friendRequestId).
  void Function(Map<String, dynamic> data)? onNavigate;

  static const _channelId = 'matrix_notifications';
  static const _channelName = 'MATRIX';

  String? _deviceToken;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  bool _active = false;
  bool _initialized = false;
  final Set<String> _shown = <String>{};

  /// Initializes the local notification plugin + channel and requests the
  /// Android 13+ notification permission once. If the user denies it, the
  /// app keeps working normally — only without native notifications.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: _onTap,
    );
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Atividades do MATRIX',
        importance: Importance.high,
      ),
    );
    await android?.requestNotificationsPermission();
  }

  /// Binds this device to the logged-in account and opens the realtime
  /// channel. Idempotent — safe to call on every login/session restore.
  Future<void> sync() async {
    await init();
    _active = true;
    _deviceToken ??= _generateToken();
    try {
      await _api.post<void>(
        '/api/devices/register',
        data: {
          'token': _deviceToken,
          'platform': Platform.isAndroid ? 'android' : 'other',
        },
      );
    } catch (_) {
      // Best-effort: the realtime socket still delivers pushes even when
      // the token registry call fails.
    }
    await _connect();
  }

  /// Unbinds this device and closes the realtime channel (logout).
  Future<void> stop() async {
    _active = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
    final token = _deviceToken;
    _deviceToken = null;
    if (token != null) {
      try {
        await _api.delete<void>('/api/devices/$token');
      } catch (_) {
        // Token may already be gone server-side; unregister is idempotent.
      }
    }
  }

  Future<void> _connect() async {
    if (!_active) return;
    final access = await _tokenStore.accessToken;
    if (access == null || access.isEmpty) return;
    final base = Uri.parse(ApiConfig.baseUrl);
    final wsUri = Uri(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/api/push/stream',
      queryParameters: {'token': access},
    );
    try {
      final channel = WebSocketChannel.connect(wsUri);
      _channel = channel;
      _sub = channel.stream.listen(
        _onMessage,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  // Gentle backoff: one reconnect attempt every 10s while the session is
  // active — no aggressive polling.
  void _scheduleReconnect() {
    if (!_active || _reconnectTimer != null) return;
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      _reconnectTimer = null;
      _connect();
    });
  }

  Future<void> _onMessage(dynamic raw) async {
    Map<String, dynamic> message;
    try {
      message = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (message['kind'] != 'notification') return;
    final data =
        (message['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final id = data['notificationId'] as String? ?? '';
    if (id.isNotEmpty && !_shown.add(id)) return; // dedupe, once per id
    await _plugin.show(
      id.isEmpty
          ? DateTime.now().millisecondsSinceEpoch ~/ 1000
          : id.hashCode,
      message['title'] as String? ?? _channelName,
      message['body'] as String? ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Atividades do MATRIX',
          importance: Importance.high,
          priority: Priority.high,
          color: Color(0xFF00B4FF),
        ),
      ),
      payload: jsonEncode(data),
    );
  }

  void _onTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      onNavigate?.call(data);
    } catch (_) {
      // Malformed payload: ignore the tap.
    }
  }

  // Random per-install token (not a credential). The server maps it to the
  // authenticated user; it can be rotated freely on logout/login.
  String _generateToken() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
