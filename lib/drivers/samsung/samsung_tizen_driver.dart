import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../base/tv_driver.dart';
import '../../domain/entities/tv_command.dart';
import '../../core/utils/app_logger.dart';
import '../../core/constants/app_constants.dart';
import '../../core/error/exceptions.dart';

class SamsungTizenDriver implements TvDriver {
  final String ipAddress;
  WebSocket? _socket;
  int _reconnectAttempts = 0;

  final StreamController<DriverState> _stateController =
      StreamController<DriverState>.broadcast();

  DriverState _state = DriverState.disconnected;

  String? _token;

  SamsungTizenDriver(this.ipAddress);

  @override
  DriverState get state => _state;

  @override
  Stream<DriverState> get stateStream => _stateController.stream;

  @override
  bool get isConnected => _state == DriverState.connected;

  void _setState(DriverState s) {
    _state = s;
    _stateController.add(s);
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

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_prefsTokenKey);
    if (_token != null && _token!.isNotEmpty) {
      AppLogger.i('Samsung: Loaded token');
    }
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsTokenKey, token);
    _token = token;
    AppLogger.i('Samsung: Saved token');
  }

  Future<WebSocket> _tryConnect(String url) async {
    AppLogger.i('Samsung: Trying $url');
    return await WebSocket.connect(url).timeout(AppConstants.connectTimeout);
  }

  @override
  Future<void> connect() async {
    try {
      _setState(DriverState.connecting);
      await _loadToken();

      final appName = 'Remotix';
      final nameBase64 = base64Encode(utf8.encode(appName));
      final tokenParam = (_token != null && _token!.isNotEmpty) ? '&token=$_token' : '';

      final url =
          'ws://$ipAddress:${AppConstants.samsungTizenPort}'
          '/api/v2/channels/samsung.remote.control?name=$nameBase64$tokenParam';

      _socket = await _tryConnect(url);

      _socket!.listen(
        (dynamic data) {
          AppLogger.d('Samsung RX: $data');
          _handleMessage(data);
        },
        onError: (Object e) {
          AppLogger.e('Samsung WebSocket error', e);
          _setState(DriverState.error);
          _scheduleReconnect();
        },
        onDone: () {
          AppLogger.w('Samsung WebSocket closed');
          _setState(DriverState.disconnected);
        },
      );

      _reconnectAttempts = 0;
      _setState(DriverState.connected);
      AppLogger.i('Samsung: Connected');
    } on TimeoutException {
      _setState(DriverState.error);
      throw const ConnectionException('Samsung connection timed out');
    } catch (e, st) {
      _setState(DriverState.error);
      AppLogger.e('Samsung connect failed', e, st);
      throw ConnectionException('Samsung connect failed: $e');
    }
  }

  void _handleMessage(dynamic data) async {
    try {
      final msg = jsonDecode(data.toString());
      final event = msg['event'];

      // Token can arrive in connect event
      if (event == 'ms.channel.connect') {
        final token = msg['data']?['token'];
        if (token is String && token.isNotEmpty && token != _token) {
          await _saveToken(token);
        }
      }
    } catch (_) {
      // ignore
    }
  }

  @override
  Future<void> sendCommand(TvCommand command) async {
    if (!isConnected) throw const DriverException('Not connected');

    final key = _keyMap[command];
    if (key == null) {
      AppLogger.w('Samsung: No key mapping for $command');
      return;
    }

    try {
      final payload = jsonEncode({
        'method': 'ms.remote.control',
        'params': {
          'Cmd': 'Click',
          'DataOfCmd': key,
          'Option': 'false',
          'TypeOfRemote': 'SendRemoteKey',
        },
      });

      _socket!.add(payload);
      AppLogger.d('Samsung: Sent $command -> $key');
    } catch (e, st) {
      AppLogger.e('Samsung sendCommand error', e, st);
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= AppConstants.maxReconnectAttempts) {
      AppLogger.w('Samsung: Max reconnect attempts reached');
      return;
    }
    _reconnectAttempts++;
    Future.delayed(AppConstants.reconnectDelay, () async {
      try {
        await connect();
      } catch (e) {
        AppLogger.e('Samsung reconnect failed', e);
      }
    });
  }

  @override
  Future<void> disconnect() async {
    try {
      await _socket?.close();
    } catch (_) {
      // ignore
    } finally {
      _setState(DriverState.disconnected);
      AppLogger.i('Samsung: Disconnected');
    }
  }
}
