// lib/drivers/lg/lg_webos_driver.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../base/tv_driver.dart';
import '../../domain/entities/tv_command.dart';
import '../../core/utils/app_logger.dart';
import '../../core/constants/app_constants.dart';
import '../../core/error/exceptions.dart';

class LgWebOsDriver extends TvDriver {
  final String ipAddress;
  WebSocket? _socket;
  int _messageId = 0;
  int _reconnectAttempts = 0;

  final StreamController<DriverState> _stateController =
      StreamController<DriverState>.broadcast();

  DriverState _state = DriverState.disconnected;

  LgWebOsDriver(this.ipAddress);

  @override
  DriverState get state => _state;

  @override
  Stream<DriverState> get stateStream => _stateController.stream;

  void _setState(DriverState s) {
    _state = s;
    _stateController.add(s);
  }

  // Maps TvCommand to SSAP URI + optional payload builder
  // Uses the LG webOS SSAP protocol: ssap://<service>/<method>
  static const Map<TvCommand, String> _ssapUriMap = {
    TvCommand.power: 'ssap://system/turnOff',
    TvCommand.volumeUp: 'ssap://audio/volumeUp',
    TvCommand.volumeDown: 'ssap://audio/volumeDown',
    TvCommand.mute: 'ssap://audio/setMute',
    TvCommand.channelUp: 'ssap://tv/channelUp',
    TvCommand.channelDown: 'ssap://tv/channelDown',
    TvCommand.home: 'ssap://system.launcher/open',
    TvCommand.back: 'ssap://com.webos.service.ime/sendEnterKey',
    TvCommand.up: 'ssap://com.webos.service.networkinput/getPointerInputSocket',
    TvCommand.down: 'ssap://com.webos.service.networkinput/getPointerInputSocket',
    TvCommand.left: 'ssap://com.webos.service.networkinput/getPointerInputSocket',
    TvCommand.right: 'ssap://com.webos.service.networkinput/getPointerInputSocket',
    TvCommand.ok: 'ssap://com.webos.service.ime/sendEnterKey',
  };

  // Commands that use the remote input key approach via ssap://com.webos.service.networkinput
  static const Map<TvCommand, String> _keyButtonMap = {
    TvCommand.up: 'UP',
    TvCommand.down: 'DOWN',
    TvCommand.left: 'LEFT',
    TvCommand.right: 'RIGHT',
    TvCommand.ok: 'ENTER',
    TvCommand.back: 'BACK',
    TvCommand.home: 'HOME',
  };

  @override
  Future<void> connect() async {
    try {
      _setState(DriverState.connecting);
      AppLogger.i('LG: Connecting to ws://$ipAddress:${AppConstants.lgWebOsPort}');

      _socket = await WebSocket.connect(
        'ws://$ipAddress:${AppConstants.lgWebOsPort}',
      ).timeout(AppConstants.connectTimeout);

      _setState(DriverState.connected);
      _reconnectAttempts = 0;
      AppLogger.i('LG: Connected successfully');

      _socket!.listen(
        (data) {
          AppLogger.d('LG RX: $data');
        },
        onError: (Object e) {
          AppLogger.e('LG WebSocket error', e);
          _setState(DriverState.error);
          _scheduleReconnect();
        },
        onDone: () {
          AppLogger.w('LG WebSocket closed');
          _setState(DriverState.disconnected);
        },
      );

      await _sendRegistration();
    } on TimeoutException {
      _setState(DriverState.error);
      throw const ConnectionException('LG connection timed out');
    } catch (e, st) {
      _setState(DriverState.error);
      AppLogger.e('LG connect failed', e, st);
      throw ConnectionException('LG connect failed: $e');
    }
  }

  Future<void> _sendRegistration() async {
    await _sendRaw({
      'id': 'register_0',
      'type': 'register',
      'payload': {
        'forcePairing': false,
        'pairingType': 'PROMPT',
        'manifest': {
          'manifestVersion': 1,
          'appVersion': '1.1',
          'signed': {
            'created': '20140509',
            'appId': 'com.lge.test',
            'vendorId': 'com.lge',
            'localizedAppNames': {'': 'Remotix'},
            'localizedVendorNames': {'': 'Remotix'},
            'permissions': [
              'TEST_SECURE',
              'CONTROL_INPUT_TEXT',
              'CONTROL_MOUSE_AND_KEYBOARD',
              'READ_INSTALLED_APPS',
              'READ_LGE_SDX',
              'READ_NOTIFICATIONS',
              'SEARCH',
              'WRITE_SETTINGS',
              'WRITE_NOTIFICATION_ALERT',
              'CONTROL_POWER',
              'READ_CURRENT_CHANNEL',
              'READ_RUNNING_APPS',
              'READ_UPDATE_INFO',
              'UPDATE_FROM_REMOTE_APP',
              'READ_LGE_TV_INPUT_EVENTS',
              'READ_TV_CURRENT_TIME',
            ],
          },
        },
      },
    });
  }

  Future<void> _sendRaw(Map<String, dynamic> payload) async {
    if (_socket == null || _state != DriverState.connected) {
      AppLogger.w('LG: Cannot send - not connected');
      return;
    }
    try {
      _socket!.add(jsonEncode(payload));
    } catch (e) {
      AppLogger.e('LG send error', e);
    }
  }

  @override
  Future<void> sendCommand(TvCommand command) async {
    if (!isConnected) throw const DriverException('Not connected');
    try {
      final id = 'cmd_${++_messageId}';

      // Navigation and action keys use button press approach
      if (_keyButtonMap.containsKey(command) &&
          command != TvCommand.home) {
        // For directional keys and back/ok, send via SSAP button press
        await _sendRaw({
          'id': id,
          'type': 'request',
          'uri': 'ssap://com.webos.service.ime/sendEnterKey',
          'payload': {},
        });
        AppLogger.d('LG: Sent key command $command');
        return;
      }

      switch (command) {
        case TvCommand.power:
          await _sendRaw({
            'id': id,
            'type': 'request',
            'uri': 'ssap://system/turnOff',
            'payload': {},
          });
          break;
        case TvCommand.volumeUp:
          await _sendRaw({
            'id': id,
            'type': 'request',
            'uri': 'ssap://audio/volumeUp',
            'payload': {},
          });
          break;
        case TvCommand.volumeDown:
          await _sendRaw({
            'id': id,
            'type': 'request',
            'uri': 'ssap://audio/volumeDown',
            'payload': {},
          });
          break;
        case TvCommand.mute:
          await _sendRaw({
            'id': id,
            'type': 'request',
            'uri': 'ssap://audio/setMute',
            'payload': {'mute': true},
          });
          break;
        case TvCommand.channelUp:
          await _sendRaw({
            'id': id,
            'type': 'request',
            'uri': 'ssap://tv/channelUp',
            'payload': {},
          });
          break;
        case TvCommand.channelDown:
          await _sendRaw({
            'id': id,
            'type': 'request',
            'uri': 'ssap://tv/channelDown',
            'payload': {},
          });
          break;
        case TvCommand.home:
          await _sendRaw({
            'id': id,
            'type': 'request',
            'uri': 'ssap://system.launcher/open',
            'payload': {'id': 'com.webos.app.home'},
          });
          break;
        case TvCommand.back:
          await _sendRaw({
            'id': id,
            'type': 'request',
            'uri': 'ssap://com.webos.service.ime/sendEnterKey',
            'payload': {},
          });
          break;
        case TvCommand.ok:
          await _sendRaw({
            'id': id,
            'type': 'request',
            'uri': 'ssap://com.webos.service.ime/sendEnterKey',
            'payload': {},
          });
          break;
        case TvCommand.up:
        case TvCommand.down:
        case TvCommand.left:
        case TvCommand.right:
          // Directional commands - send pointer move via SSAP
          await _sendRaw({
            'id': id,
            'type': 'request',
            'uri': 'ssap://com.webos.service.networkinput/getPointerInputSocket',
            'payload': {},
          });
          break;
      }

      AppLogger.d('LG: Sent command $command (id=$id)');
    } catch (e, st) {
      AppLogger.e('LG sendCommand error', e, st);
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= AppConstants.maxReconnectAttempts) {
      AppLogger.w('LG: Max reconnect attempts reached');
      return;
    }
    _reconnectAttempts++;
    AppLogger.i('LG: Scheduling reconnect attempt $_reconnectAttempts...');
    Future.delayed(AppConstants.reconnectDelay, () async {
      try {
        await connect();
      } catch (e) {
        AppLogger.e('LG reconnect failed', e);
      }
    });
  }

  @override
  Future<void> disconnect() async {
    try {
      await _socket?.close();
    } catch (e) {
      AppLogger.e('LG disconnect error', e);
    } finally {
      _setState(DriverState.disconnected);
      AppLogger.i('LG: Disconnected');
    }
  }
}
