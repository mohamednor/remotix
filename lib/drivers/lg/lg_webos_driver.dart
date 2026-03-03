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
  }

  Future<void> _saveClientKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyClientKey, key);
    _clientKey = key;
  }

  @override
  Future<void> connect() async {
    try {
      _setState(DriverState.connecting);
      await _loadClientKey();

      _isRegistered = false;
      _registeredCompleter = Completer<void>();

      final url =
          'ws://$ipAddress:${AppConstants.lgWebOsPort}/api/websocket';

      await _closeSockets();

      _ssapSocket =
          await WebSocket.connect(url).timeout(AppConstants.connectTimeout);

      _ssapSocket!.listen(
        (data) async => await _handleMessage(data),
        onError: (e, st) {
          _setState(DriverState.error);
        },
        onDone: () {
          _setState(DriverState.disconnected);
        },
        cancelOnError: true,
      );

      await _sendRegistration();

      // نستنى registered
      await _registeredCompleter!.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          throw const ConnectionException(
              'LG pairing لم يكتمل. وافق على التلفزيون.');
        },
      );

      await _requestPointerSocket();

      // ✅ نستنى pointer socket يفتح فعليًا
      int tries = 0;
      while (_pointerSocket == null && tries < 20) {
        await Future.delayed(const Duration(milliseconds: 150));
        tries++;
      }

      if (_pointerSocket == null) {
        throw const ConnectionException('LG pointer socket failed.');
      }

      _setState(DriverState.connected);
      _reconnectAttempts = 0;
    } catch (e) {
      _setState(DriverState.error);
      rethrow;
    }
  }

  Future<void> _handleMessage(dynamic data) async {
    try {
      final msg = jsonDecode(data.toString());
      final type = msg['type'];

      if (type == 'registered') {
        final key = msg['payload']?['client-key'];
        if (key != null) await _saveClientKey(key);

        _isRegistered = true;
        if (!_registeredCompleter!.isCompleted) {
          _registeredCompleter!.complete();
        }
        return;
      }

      if (msg['uri'] ==
          'ssap://com.webos.service.networkinput/getPointerInputSocket') {
        final path = msg['payload']?['socketPath'];
        if (path != null) {
          _pointerPath = path;
          await _connectPointerSocket();
        }
      }
    } catch (_) {}
  }

  Future<void> _sendRegistration() async {
    await _sendRaw({
      'id': 'register_0',
      'type': 'register',
      'payload': {
        'pairingType': 'PROMPT',
        if (_clientKey != null) 'client-key': _clientKey,
      },
    });
  }

  Future<void> _requestPointerSocket() async {
    await _sendRaw({
      'id': 'ptr_${++_messageId}',
      'type': 'request',
      'uri':
          'ssap://com.webos.service.networkinput/getPointerInputSocket',
      'payload': {},
    });
  }

  Future<void> _connectPointerSocket() async {
    if (_pointerPath == null) return;

    final url = _pointerPath!.startsWith('ws://')
        ? _pointerPath!
        : 'ws://$ipAddress:${AppConstants.lgWebOsPort}${_pointerPath!}';

    _pointerSocket =
        await WebSocket.connect(url).timeout(AppConstants.connectTimeout);

    _pointerSocket!.listen((_) {});
  }

  Future<void> _sendRaw(Map<String, dynamic> payload) async {
    _ssapSocket?.add(jsonEncode(payload));
  }

  Future<void> _sendPointerButton(String name) async {
    if (_pointerSocket == null) return;

    final msg = 'type:button\nname:$name\n\n';
    _pointerSocket!.add(msg);
  }

  @override
  Future<void> sendCommand(TvCommand command) async {
    if (!isConnected || !_isRegistered) return;

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
        });
        break;

      case TvCommand.volumeDown:
        await _sendRaw({
          'id': 'cmd_${++_messageId}',
          'type': 'request',
          'uri': 'ssap://audio/volumeDown',
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
        });
        break;

      case TvCommand.channelDown:
        await _sendRaw({
          'id': 'cmd_${++_messageId}',
          'type': 'request',
          'uri': 'ssap://tv/channelDown',
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

  Future<void> _closeSockets() async {
    await _pointerSocket?.close();
    await _ssapSocket?.close();
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
