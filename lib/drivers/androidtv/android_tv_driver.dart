// lib/drivers/androidtv/android_tv_driver.dart

import 'dart:async';
import 'dart:io';
import '../base/tv_driver.dart';
import '../../domain/entities/tv_command.dart';
import '../../core/utils/app_logger.dart';
import '../../core/constants/app_constants.dart';
import '../../core/error/exceptions.dart';

class AndroidTvDriver implements TvDriver {
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

  // Android TV / Google TV ADB keycodes (KEYCODE_* values)
  static const Map<TvCommand, int> _keycodeMap = {
    TvCommand.power: 26,       // KEYCODE_POWER
    TvCommand.volumeUp: 24,    // KEYCODE_VOLUME_UP
    TvCommand.volumeDown: 25,  // KEYCODE_VOLUME_DOWN
    TvCommand.mute: 164,       // KEYCODE_VOLUME_MUTE
    TvCommand.channelUp: 166,  // KEYCODE_CHANNEL_UP
    TvCommand.channelDown: 167, // KEYCODE_CHANNEL_DOWN
    TvCommand.up: 19,          // KEYCODE_DPAD_UP
    TvCommand.down: 20,        // KEYCODE_DPAD_DOWN
    TvCommand.left: 21,        // KEYCODE_DPAD_LEFT
    TvCommand.right: 22,       // KEYCODE_DPAD_RIGHT
    TvCommand.ok: 23,          // KEYCODE_DPAD_CENTER
    TvCommand.home: 3,         // KEYCODE_HOME
    TvCommand.back: 4,         // KEYCODE_BACK
  };

  @override
  Future<void> connect() async {
    try {
      _setState(DriverState.connecting);
      AppLogger.i(
          'AndroidTV: Connecting to $ipAddress:${AppConstants.androidTvPort}');

      _socket = await Socket.connect(
        ipAddress,
        AppConstants.androidTvPort,
        timeout: AppConstants.connectTimeout,
      );

      _setState(DriverState.connected);
      _reconnectAttempts = 0;
      AppLogger.i('AndroidTV: Connected successfully');

      _socket!.listen(
        (List<int> data) {
          AppLogger.d('AndroidTV RX: ${data.length} bytes');
        },
        onError: (Object e) {
          AppLogger.e('AndroidTV socket error', e);
          _setState(DriverState.error);
          _scheduleReconnect();
        },
        onDone: () {
          AppLogger.w('AndroidTV socket closed');
          _setState(DriverState.disconnected);
        },
      );
    } on SocketException catch (e) {
      _setState(DriverState.error);
      throw ConnectionException('AndroidTV connection failed: ${e.message}');
    } on TimeoutException {
      _setState(DriverState.error);
      throw const ConnectionException('AndroidTV connection timed out');
    } catch (e, st) {
      _setState(DriverState.error);
      AppLogger.e('AndroidTV connect failed', e, st);
      throw ConnectionException('AndroidTV connect failed: $e');
    }
  }

  @override
  Future<void> sendCommand(TvCommand command) async {
    if (!isConnected) throw const DriverException('Not connected');
    try {
      final keycode = _keycodeMap[command];
      if (keycode == null) {
        AppLogger.w('AndroidTV: No keycode mapping for $command');
        return;
      }
      // Send as ADB shell input keyevent command
      final cmd = 'input keyevent $keycode\n';
      _socket!.write(cmd);
      await _socket!.flush();
      AppLogger.d('AndroidTV: Sent $command -> KEYCODE $keycode');
    } catch (e, st) {
      AppLogger.e('AndroidTV sendCommand error', e, st);
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= AppConstants.maxReconnectAttempts) {
      AppLogger.w('AndroidTV: Max reconnect attempts reached');
      return;
    }
    _reconnectAttempts++;
    AppLogger.i('AndroidTV: Reconnect attempt $_reconnectAttempts');
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
    } catch (e) {
      AppLogger.e('AndroidTV disconnect error', e);
    } finally {
      _setState(DriverState.disconnected);
      AppLogger.i('AndroidTV: Disconnected');
    }
  }
}
