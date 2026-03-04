// lib/drivers/samsung/samsung_tizen_driver.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../base/tv_driver.dart';
import '../../domain/entities/tv_command.dart';
import '../../core/utils/app_logger.dart';
import '../../core/constants/app_constants.dart';
import '../../core/error/exceptions.dart';

class SamsungTizenDriver extends TvDriver {
  final String ipAddress;

  WebSocket? _socket;
  int _reconnectAttempts = 0;

  final StreamController<DriverState> _stateController =
      StreamController<DriverState>.broadcast();

  DriverState _state = DriverState.disconnected;

  String? _token;

  // ✅ NEW: هل التلفزيون طلب موافقة؟
  bool _waitingForApproval = false;
  bool get waitingForApproval => _waitingForApproval;

  SamsungTizenDriver(this.ipAddress);

  @override
  DriverState get state => _state;

  @override
  Stream<DriverState> get stateStream => _stateController.stream;

  void _setState(DriverState s) {
    if (_state == s) return;
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  String get _prefsTokenKey => 'samsung_tizen_token_$ipAddress';

  static const Map<TvCommand, String> _keyMap = {
    TvCommand.power: 'KEY_POWER',
    TvCommand.volumeUp: 'KEY_VOLUP',
    TvCommand.volumeDown: 'KEY_VOLDOWN',
    TvCommand.mute: 'KEY_MUTE',
    TvCommand.channelUp: 'KEY_CHUP',
    TvCommand.channelDown: 'KEY_CHDOWN',
    TvCommand.up: 'KEY_UP',
    TvCommand.down: 'KEY_DOWN',
    TvCommand.left: 'KEY_LEFT',
    TvCommand.right: 'KEY_RIGHT',
    TvCommand.ok: 'KEY_ENTER',
    TvCommand.home: 'KEY_HOME',
    TvCommand.back: 'KEY_RETURN',
  };

  // ─────────────────────────── SharedPrefs ───────────────────────────

  Future<void> _loadToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_prefsTokenKey);
      if ((_token ?? '').isNotEmpty) AppLogger.i('Samsung: Loaded token');
    } catch (e) {
      AppLogger.w('Samsung: Could not load token: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsTokenKey, token);
      _token = token;
      AppLogger.i('Samsung: Saved token');
    } catch (e) {
      AppLogger.w('Samsung: Could not save token: $e');
    }
  }

  // ─────────────────────────── Connect ───────────────────────────────

  Future<WebSocket> _openSocket(String url) async {
    AppLogger.i('Samsung: Trying → $url');
    return WebSocket.connect(url).timeout(AppConstants.connectTimeout);
  }

  @override
  Future<void> connect() async {
    _setState(DriverState.connecting);
    _waitingForApproval = false;

    await _loadToken();

    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;

    final appName = 'Remotix';
    final nameB64 = base64Encode(utf8.encode(appName));
    final nameEnc = Uri.encodeComponent(appName);

    // ✅ Samsung بيستخدم base64 اسم التطبيق — بعض الأجهزة بتقبل encoded
    final tokenSuffix =
        (_token != null && _token!.isNotEmpty) ? '&token=$_token' : '';

    final urls = [
      'ws://$ipAddress:${AppConstants.samsungTizenPort}'
          '/api/v2/channels/samsung.remote.control'
          '?name=$nameB64$tokenSuffix',
      'ws://$ipAddress:${AppConstants.samsungTizenPort}'
          '/api/v2/channels/samsung.remote.control'
          '?name=$nameEnc$tokenSuffix',
    ];

    Object? lastErr;
    for (final url in urls) {
      try {
        _socket = await _openSocket(url);
        break;
      } catch (e) {
        lastErr = e;
        AppLogger.w('Samsung: $url failed → $e');
      }
    }

    if (_socket == null) {
      _setState(DriverState.error);
      throw ConnectionException('Samsung: $lastErr');
    }

    _socket!.listen(
      (dynamic data) {
        AppLogger.d('Samsung RX: $data');
        _handleMessage(data as String);
      },
      onError: (Object e, StackTrace st) {
        AppLogger.e('Samsung WS error', e, st);
        _setState(DriverState.error);
        _scheduleReconnect();
      },
      onDone: () {
        AppLogger.w('Samsung WS closed');
        _setState(DriverState.disconnected);
        _scheduleReconnect();
      },
      cancelOnError: true,
    );

    _reconnectAttempts = 0;
    _setState(DriverState.connected);
    AppLogger.i('Samsung: ✅ Connected');
  }

  // ─────────────────────────── Message Handler ───────────────────────

  void _handleMessage(String raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final event = msg['event'] as String? ?? '';

    switch (event) {
      // ✅ اتصال ناجح + token جديد
      case 'ms.channel.connect':
        _waitingForApproval = false;
        final token = msg['data']?['token'];
        if (token is String && token.isNotEmpty && token != _token) {
          _saveToken(token);
        }
        AppLogger.i('Samsung: Channel connected, token received');

      // ✅ التلفزيون بيطلب موافقة المستخدم
      case 'ms.channel.clientConnect':
        AppLogger.i('Samsung: Client connected event');

      // ✅ FIX: Samsung بيبعت unauthorized لو محتاج موافقة
      case 'ms.channel.unauthorized':
        _waitingForApproval = true;
        AppLogger.w(
          'Samsung: Unauthorized — TV is waiting for user approval. '
          'Accept the connection request on the TV.',
        );
        // ✅ مش بنعمل error هنا — نفضل connected وننتظر الموافقة

      // خطأ عام
      default:
        if (msg.containsKey('error')) {
          AppLogger.w('Samsung: Error message → $raw');
        }
    }
  }

  // ─────────────────────────── Commands ──────────────────────────────

  @override
  Future<void> sendCommand(TvCommand command) async {
    if (!isConnected) {
      throw DriverException(
        _state == DriverState.connecting
            ? 'جاري الاتصال، انتظر...'
            : 'التلفزيون غير متصل',
      );
    }

    final s = _socket;
    if (s == null) throw const DriverException('Socket not ready');

    final key = _keyMap[command];
    if (key == null) {
      AppLogger.w('Samsung: No key mapping for $command');
      return;
    }

    try {
      s.add(jsonEncode({
        'method': 'ms.remote.control',
        'params': {
          'Cmd': 'Click',
          'DataOfCmd': key,
          'Option': 'false',
          'TypeOfRemote': 'SendRemoteKey',
        },
      }));
      AppLogger.d('Samsung: Sent $command → $key');
    } catch (e, st) {
      AppLogger.e('Samsung: sendCommand error', e, st);
      _setState(DriverState.error);
      _scheduleReconnect();
    }
  }

  // ─────────────────────────── Reconnect ─────────────────────────────

  void _scheduleReconnect() {
    if (_reconnectAttempts >= AppConstants.maxReconnectAttempts) return;
    if (_state == DriverState.connecting || _state == DriverState.connected) {
      return;
    }
    _reconnectAttempts++;
    AppLogger.i('Samsung: Reconnect attempt $_reconnectAttempts');

    Future.delayed(AppConstants.reconnectDelay, () async {
      try {
        await connect();
      } catch (e) {
        AppLogger.e('Samsung: Reconnect failed', e);
      }
    });
  }

  // ─────────────────────────── Cleanup ───────────────────────────────

  @override
  Future<void> disconnect() async {
    _reconnectAttempts = AppConstants.maxReconnectAttempts;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _waitingForApproval = false;
    _setState(DriverState.disconnected);
    AppLogger.i('Samsung: Disconnected');
  }
}
