// lib/drivers/lg/lg_webos_driver.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../base/tv_driver.dart';
import '../../domain/entities/tv_command.dart';
import '../../core/utils/app_logger.dart';
import '../../core/constants/app_constants.dart';
import '../../core/error/exceptions.dart';

class LgWebOsDriver extends TvDriver {
  final String ipAddress;

  WebSocket? _ssapSocket;
  WebSocket? _pointerSocket;

  final StreamController<DriverState> _stateController =
      StreamController<DriverState>.broadcast();

  DriverState _state = DriverState.disconnected;

  int _messageId = 0;
  int _reconnectAttempts = 0;

  String? _clientKey;
  String? _pointerPath;

  bool _muteState = false;

  Completer<void>? _registeredCompleter;
  bool _isRegistered = false;

  LgWebOsDriver(this.ipAddress);

  @override
  DriverState get state => _state;

  @override
  Stream<DriverState> get stateStream => _stateController.stream;

  void _setState(DriverState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  String get _prefsKeyClientKey => 'lg_webos_client_key_$ipAddress';

  Future<void> _loadClientKey() async {
    final prefs = await SharedPreferences.getInstance();
    _clientKey = prefs.getString(_prefsKeyClientKey);
    if (_clientKey != null && _clientKey!.isNotEmpty) {
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

      _isRegistered = false;
      _registeredCompleter = Completer<void>();

      // ✅ endpoint الصحيح
      final url = 'ws://$ipAddress:${AppConstants.lgWebOsPort}/api/websocket';
      AppLogger.i('LG: Connecting to $url');

      await _closeSockets();

      _ssapSocket =
          await WebSocket.connect(url).timeout(AppConstants.connectTimeout);

      _ssapSocket!.listen(
        (data) async {
          AppLogger.d('LG RX: $data');
          await _handleMessage(data);
        },
        onError: (Object e, StackTrace st) {
          AppLogger.e('LG WebSocket error', e, st);
          _setState(DriverState.error);
          _scheduleReconnect();
        },
        onDone: () {
          AppLogger.w('LG WebSocket closed');
          _setState(DriverState.disconnected);
        },
        cancelOnError: true,
      );

      // Register (pairing)
      await _sendRegistration();

      // ✅ وقت أطول عشان الـ prompt على التلفزيون
      await _registeredCompleter!.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw const ConnectionException(
            'LG pairing لم يكتمل. وافق على رسالة الاقتران على التلفزيون ثم أعد المحاولة.',
          );
        },
      );

      // Request pointer socket
      await _requestPointerSocket();

      // ✅ نستنى pointer فعليًا (بدون ما نهنّج كتير)
      int tries = 0;
      while (_pointerSocket == null && tries < 30) {
        await Future.delayed(const Duration(milliseconds: 120));
        tries++;
      }

      if (_pointerSocket == null) {
        throw const ConnectionException('LG pointer socket failed.');
      }

      _setState(DriverState.connected);
      _reconnectAttempts = 0;
      AppLogger.i('LG: Connected + registered + pointer ready');
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

      if (type == 'registered') {
        final payload = msg['payload'];
        final key = (payload is Map) ? payload['client-key'] : null;
        if (key is String && key.isNotEmpty) {
          await _saveClientKey(key);
        }

        _isRegistered = true;
        if (_registeredCompleter != null &&
            !_registeredCompleter!.isCompleted) {
          _registeredCompleter!.complete();
        }
        return;
      }

      final uri = msg['uri'];
      if (uri ==
          'ssap://com.webos.service.networkinput/getPointerInputSocket') {
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
        // ✅ رجّعنا manifest/permissions (التبسيط كان بيكسر التنفيذ على موديلات)
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

    final url = _pointerPath!.startsWith('ws://')
        ? _pointerPath!
        : 'ws://$ipAddress:${AppConstants.lgWebOsPort}${_pointerPath!}';

    try {
      await _pointerSocket?.close();
    } catch (_) {}

    AppLogger.i('LG: Connecting pointer socket: $url');
    _pointerSocket =
        await WebSocket.connect(url).timeout(AppConstants.connectTimeout);

    _pointerSocket!.listen(
      (data) => AppLogger.d('LG PTR RX: $data'),
      onError: (e, st) => AppLogger.e('LG Pointer socket error', e, st),
      onDone: () => AppLogger.w('LG Pointer socket closed'),
      cancelOnError: true,
    );
  }

  Future<void> _sendRaw(Map<String, dynamic> payload) async {
    final s = _ssapSocket;
    if (s == null) return;
    try {
      s.add(jsonEncode(payload));
    } catch (e, st) {
      AppLogger.e('LG: sendRaw failed', e, st);
      _setState(DriverState.error);
      _scheduleReconnect();
    }
  }

  // ✅ pointer socket = TEXT protocol
  Future<void> _sendPointerButton(String name) async {
    if (_pointerSocket == null) return;
    final msg = 'type:button\nname:$name\n\n';
    try {
      _pointerSocket!.add(msg);
      AppLogger.d('LG PTR TX: $msg');
    } catch (e, st) {
      AppLogger.e('LG: sendPointerButton failed', e, st);
    }
  }

  @override
  Future<void> sendCommand(TvCommand command) async {
    if (!isConnected) throw const DriverException('Not connected');
    if (!_isRegistered) throw const DriverException('LG pairing not completed');

    switch (command) {
      case TvCommand.power:
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
        _muteState = !_muteState;
        await _sendRaw({
          'id': 'cmd_${++_messageId}',
          'type': 'request',
          'uri': 'ssap://audio/setMute',
          'payload': {'mute': _muteState},
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
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= AppConstants.maxReconnectAttempts) return;
    _reconnectAttempts++;
    Future.delayed(AppConstants.reconnectDelay, () async {
      try {
        await connect();
      } catch (e, st) {
        AppLogger.e('LG reconnect failed', e, st);
      }
    });
  }

  Future<void> _closeSockets() async {
    try {
      await _pointerSocket?.close();
    } catch (_) {}
    try {
      await _ssapSocket?.close();
    } catch (_) {}
    _pointerSocket = null;
    _ssapSocket = null;
  }

  @override
  Future<void> disconnect() async {
    await _closeSockets();
    _isRegistered = false;
    _registeredCompleter = null;
    _setState(DriverState.disconnected);
  }
}
