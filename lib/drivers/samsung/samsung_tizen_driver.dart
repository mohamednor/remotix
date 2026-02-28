// lib/drivers/samsung/samsung_tizen_driver.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

  SamsungTizenDriver(this.ipAddress);

  @override
  DriverState get state => _state;

  @override
  Stream<DriverState> get stateStream => _stateController.stream;

  void _setState(DriverState s) {
    _state = s;
    _stateController.add(s);
  }

  // Samsung Tizen remote key codes for ms.remote.control
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

  @override
  Future<void> connect() async {
    try {
      _setState(DriverState.connecting);
      final appName = Uri.encodeComponent('Remotix');
      final url =
          'ws://$ipAddress:${AppConstants.samsungTizenPort}'
          '/api/v2/channels/samsung.remote.control?name=$appName';
      AppLogger.i('Samsung: Connecting to $url');

      _socket = await WebSocket.connect(url)
          .timeout(AppConstants.connectTimeout);

      _setState(DriverState.connected);
      _reconnectAttempts = 0;
      AppLogger.i('Samsung: Connected successfully');

      _socket!.listen(
        (dynamic data) {
          AppLogger.d('Samsung RX: $data');
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
    } on TimeoutException {
      _setState(DriverState.error);
      throw const ConnectionException('Samsung connection timed out');
    } catch (e, st) {
      _setState(DriverState.error);
      AppLogger.e('Samsung connect failed', e, st);
      throw ConnectionException('Samsung connect failed: $e');
    }
  }

  @override
  Future<void> sendCommand(TvCommand command) async {
    if (!isConnected) throw const DriverException('Not connected');
    try {
      final key = _keyMap[command];
      if (key == null) {
        AppLogger.w('Samsung: No key mapping for $command');
        return;
      }
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
    AppLogger.i('Samsung: Reconnecting attempt $_reconnectAttempts');
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
    } catch (e) {
      AppLogger.e('Samsung disconnect error', e);
    } finally {
      _setState(DriverState.disconnected);
      AppLogger.i('Samsung: Disconnected');
    }
  }
}
