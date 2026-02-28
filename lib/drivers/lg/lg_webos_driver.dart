import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../base/tv_driver.dart';
import '../../domain/entities/tv_command.dart';
import '../../core/utils/app_logger.dart';
import '../../core/constants/app_constants.dart';
import '../../core/error/exceptions.dart';

class LgWebOsDriver implements TvDriver {
  final String ipAddress;

  WebSocket? _ssapSocket;     // SSAP: register + requests
  WebSocket? _pointerSocket;  // pointer input socket

  final StreamController<DriverState> _stateController =
      StreamController<DriverState>.broadcast();

  DriverState _state = DriverState.disconnected;

  int _messageId = 0;
  int _reconnectAttempts = 0;

  String? _clientKey;
  String? _pointerPath;

  LgWebOsDriver(this.ipAddress);

  @override
  DriverState get state => _state;

  @override
  Stream<DriverState> get stateStream => _stateController.stream;

  void _setState(DriverState s) {
    _state = s;
    _stateController.add(s);
  }

  String get _prefsKeyClientKey => 'lg_webos_client_key_$ipAddress';

  Future<void> _loadClientKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_prefsKeyClientKey);
    if (key != null && key.isNotEmpty) {
      _clientKey = key;
      AppLogger.i('LG: Loaded saved client-key');
    }
  }

  Future<void> _saveClientKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyClientKey, key);
    _clientKey = key;
    AppLogger.i('LG: Saved client-key');
  }

  @override
  Future<void> connect() async {
    try {
      _setState(DriverState.connecting);
      await _loadClientKey();

      final url = 'ws://$ipAddress:${AppConstants.lgWebOsPort}';
      AppLogger.i('LG: Connecting SSAP: $url');

      _ssapSocket = await WebSocket.connect(url).timeout(AppConstants.connectTimeout);

      _ssapSocket!.listen(
        (data) async {
          AppLogger.d('LG RX: $data');
          await _handleMessage(data);
        },
        onError: (Object e) {
          AppLogger.e('LG SSAP error', e);
          _setState(DriverState.error);
          _scheduleReconnect();
        },
        onDone: () {
          AppLogger.w('LG SSAP closed');
          _setState(DriverState.disconnected);
        },
      );

      // 1) Register => TV prompt (first time only if client-key reused)
      await _sendRegistration();

      // 2) Request pointer socket
      await _requestPointerSocket();

      _reconnectAttempts = 0;
      _setState(DriverState.connected);
      AppLogger.i('LG: Connected');
    } on TimeoutException {
      _setState(DriverState.error);
      throw const ConnectionException('LG connection timed out');
    } catch (e, st) {
      _setState(DriverState.error);
      AppLogger.e('LG connect failed', e, st);
      throw ConnectionException('LG connect failed: $e');
    }
  }

  Future<void> _handleMessage(dynamic data) async {
    try {
      final msg = jsonDecode(data.toString()) as Map<String, dynamic>;
      final type = msg['type'];

      // Save client-key after successful pairing
      if (type == 'registered') {
        final payload = msg['payload'];
        final key = (payload is Map) ? payload['client-key'] : null;
        if (key is String && key.isNotEmpty) {
          if (key != _clientKey) await _saveClientKey(key);
        }
        return;
      }

      // Pointer socket response
      final uri = msg['uri'];
      if (uri == 'ssap://com.webos.service.networkinput/getPointerInputSocket') {
        final payload = msg['payload'];
        final path = (payload is Map) ? payload['socketPath'] : null;
        if (path is String && path.isNotEmpty) {
          _pointerPath = path;
          AppLogger.i('LG: Got pointer socketPath: $_pointerPath');
          await _connectPointerSocket();
        }
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _sendRegistration() async {
    await _sendRaw({
      'id': 'register_0',
      'type': 'register',
      'payload': {
        'forcePairing': false,
        'pairingType': 'PROMPT',
        if (_clientKey != null && _clientKey!.isNotEmpty) 'client-key': _clientKey,
        'manifest': {
          'manifestVersion': 1,
          'appVersion': '1.0',
          'signed': {
            'created': '20260301',
            'appId': 'com.remotix.app',
            'vendorId': 'com.remotix',
            'localizedAppNames': {'': 'Remotix'},
            'localizedVendorNames': {'': 'Remotix'},
            'permissions': [
              'CONTROL_POWER',
              'CONTROL_INPUT_TEXT',
              'CONTROL_MOUSE_AND_KEYBOARD',
              'READ_RUNNING_APPS',
              'READ_INSTALLED_APPS',
              'READ_CURRENT_CHANNEL',
              'SEARCH',
              'READ_NOTIFICATIONS',
            ],
          },
        },
      },
    });
  }

  Future<void> _requestPointerSocket() async {
    await _sendRaw({
      'id': 'ptr_${++_messageId}',
      'type': 'request',
      'uri': 'ssap://com.webos.service.networkinput/getPointerInputSocket',
      'payload': {},
    });
  }

  Future<void> _connectPointerSocket() async {
    if (_pointerPath == null || _pointerPath!.isEmpty) return;

    // Usually socketPath is like: "/some/path"
    final url = _pointerPath!.startsWith('ws://')
        ? _pointerPath!
        : 'ws://$ipAddress:${AppConstants.lgWebOsPort}${_pointerPath!}';

    try {
      await _pointerSocket?.close();
    } catch (_) {}

    AppLogger.i('LG: Connecting pointer socket: $url');
    _pointerSocket = await WebSocket.connect(url).timeout(AppConstants.connectTimeout);

    _pointerSocket!.listen(
      (data) => AppLogger.d('LG PTR RX: $data'),
      onError: (e) => AppLogger.e('LG pointer error', e),
      onDone: () => AppLogger.w('LG pointer closed'),
    );
  }

  Future<void> _sendRaw(Map<String, dynamic> payload) async {
    if (_ssapSocket == null) return;
    _ssapSocket!.add(jsonEncode(payload));
  }

  // IMPORTANT: LG pointer socket uses TEXT commands (NOT JSON)
  Future<void> _sendPointerButton(String name) async {
    if (_pointerSocket == null) {
      await _requestPointerSocket();
      AppLogger.w('LG: Pointer socket not ready yet');
      return;
    }
    // Expected format: "type:button\nname:UP\n\n"
    final msg = 'type:button\nname:$name\n\n';
    _pointerSocket!.add(msg);
  }

  @override
  Future<void> sendCommand(TvCommand command) async {
    if (!isConnected) throw const DriverException('Not connected');

    try {
      switch (command) {
        case TvCommand.power:
          // Power OFF only (Power ON needs Wake-on-LAN)
          await _sendRaw({
            'id': 'cmd_${++_messageId}',
            'type': 'request',
            'uri': 'ssap://system/turnOff',
            'payload': {},
          });
          break;

        case TvCommand.volumeUp:
          await _sendRaw({
            'id': 'cmd_${++_messageId}',
            'type': 'request',
            'uri': 'ssap://audio/volumeUp',
            'payload': {},
          });
          break;

        case TvCommand.volumeDown:
          await _sendRaw({
            'id': 'cmd_${++_messageId}',
            'type': 'request',
            'uri': 'ssap://audio/volumeDown',
            'payload': {},
          });
          break;

        case TvCommand.mute:
          // toggle is better, but keep as true if you want fixed mute
          await _sendRaw({
            'id': 'cmd_${++_messageId}',
            'type': 'request',
            'uri': 'ssap://audio/setMute',
            'payload': {'mute': true},
          });
          break;

        case TvCommand.channelUp:
          await _sendRaw({
            'id': 'cmd_${++_messageId}',
            'type': 'request',
            'uri': 'ssap://tv/channelUp',
            'payload': {},
          });
          break;

        case TvCommand.channelDown:
          await _sendRaw({
            'id': 'cmd_${++_messageId}',
            'type': 'request',
            'uri': 'ssap://tv/channelDown',
            'payload': {},
          });
          break;

        // D-Pad via pointer socket
        case TvCommand.up:
          await _sendPointerButton('UP');
          break;
        case TvCommand.down:
          await _sendPointerButton('DOWN');
          break;
        case TvCommand.left:
          await _sendPointerButton('LEFT');
          break;
        case TvCommand.right:
          await _sendPointerButton('RIGHT');
          break;
        case TvCommand.ok:
          await _sendPointerButton('ENTER');
          break;
        case TvCommand.back:
          await _sendPointerButton('BACK');
          break;
        case TvCommand.home:
          await _sendPointerButton('HOME');
          break;
      }
    } catch (e, st) {
      AppLogger.e('LG sendCommand error', e, st);
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= AppConstants.maxReconnectAttempts) return;
    _reconnectAttempts++;
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
      await _pointerSocket?.close();
      await _ssapSocket?.close();
    } catch (_) {
      // ignore
    } finally {
      _pointerSocket = null;
      _ssapSocket = null;
      _pointerPath = null;
      _setState(DriverState.disconnected);
    }
  }
}
