import 'dart:async';
import 'dart:io';

import '../base/tv_driver.dart';
import '../../domain/entities/tv_command.dart';
import '../../core/utils/app_logger.dart';
import '../../core/constants/app_constants.dart';
import '../../core/error/exceptions.dart';

class AndroidTvDriver extends TvDriver {
  final String ipAddress;
  Socket? _socket;
  int _reconnectAttempts = 0;

  final StreamController<DriverState> _stateController =
      StreamController<DriverState>.broadcast();

  DriverState _state = DriverState.disconnected;

  AndroidTvDriver(this.ipAddress);

  @override
  DriverState get state => _state;

  @override
  Stream<DriverState> get stateStream => _stateController.stream;

  void _setState(DriverState s) {
    _state = s;
    _stateController.add(s);
  }

  static const Map<TvCommand, int> _keycodeMap = {
    TvCommand.power: 26,
    TvCommand.volumeUp: 24,
    TvCommand.volumeDown: 25,
    TvCommand.mute: 164,
    TvCommand.channelUp: 166,
    TvCommand.channelDown: 167,
    TvCommand.up: 19,
    TvCommand.down: 20,
    TvCommand.left: 21,
    TvCommand.right: 22,
    TvCommand.ok: 23,
    TvCommand.home: 3,
    TvCommand.back: 4,
  };

  @override
  Future<void> connect() async {
    try {
      _setState(DriverState.connecting);
      AppLogger.i('AndroidTV: Connecting to $ipAddress:${AppConstants.androidTvPort}');
      _socket = await Socket.connect(
        ipAddress,
        AppConstants.androidTvPort,
        timeout: AppConstants.connectTimeout,
      );
      _setState(DriverState.connected);
      _reconnectAttempts = 0;
      AppLogger.i('AndroidTV: Connected');
    } on SocketException catch (e) {
      _setState(DriverState.error);
      throw ConnectionException('AndroidTV connection failed: ${e.message}');
    } on TimeoutException {
      _setState(DriverState.error);
      throw const ConnectionException('AndroidTV connection timed out');
    }
  }

  @override
  Future<void> sendCommand(TvCommand command) async {
    if (!isConnected) throw const DriverException('Not connected');

    final keycode = _keycodeMap[command];
    if (keycode == null) return;

    try {
      // Build-safe فقط
      final cmd = 'input keyevent $keycode\n';
      _socket!.write(cmd);
      await _socket!.flush();
      AppLogger.d('AndroidTV: Sent $command -> $keycode');
    } catch (e, st) {
      AppLogger.e('AndroidTV sendCommand error', e, st);
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= AppConstants.maxReconnectAttempts) return;
    _reconnectAttempts++;
    Future.delayed(AppConstants.reconnectDelay, () async {
      try {
        await connect();
      } catch (e) {
        AppLogger.e('AndroidTV reconnect failed', e);
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
      _socket = null;
      _setState(DriverState.disconnected);
    }
  }
}
