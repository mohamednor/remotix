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
    if (_state == s) return;
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  String get _prefsKey => 'lg_client_key_$ipAddress';

  Future<void> _loadClientKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _clientKey = prefs.getString(_prefsKey);
      AppLogger.i('LG: clientKey="${_clientKey ?? 'none'}"');
    } catch (e) {
      AppLogger.w('LG: load clientKey failed: $e');
    }
  }

  Future<void> _saveClientKey(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, key);
      _clientKey = key;
      AppLogger.i('LG: clientKey saved');
    } catch (e) {
      AppLogger.w('LG: save clientKey failed: $e');
    }
  }

  Future<void> _clearClientKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
      _clientKey = null;
      AppLogger.w('LG: clientKey cleared');
    } catch (e) {
      AppLogger.w('LG: clear clientKey failed: $e');
    }
  }

  @override
  Future<void> connect() async {
    _setState(DriverState.connecting);
    await _loadClientKey();

    _isRegistered = false;
    _registeredCompleter = Completer<void>();

    await _closeSockets();

    WebSocket socket;
    try {
      socket = await WebSocket.connect(
        'ws://$ipAddress:${AppConstants.lgWebOsPort}',
      ).timeout(AppConstants.connectTimeout);
    } catch (_) {
      try {
        socket = await WebSocket.connect(
          'ws://$ipAddress:${AppConstants.lgWebOsPort}/api/websocket',
        ).timeout(AppConstants.connectTimeout);
      } catch (e, st) {
        AppLogger.e('LG: socket failed', e, st);
        _setState(DriverState.error);
        throw ConnectionException('LG: $e');
      }
    }

    _ssapSocket = socket;
    AppLogger.i('LG: socket open ✅');

    socket.listen(
      (data) async => _handleMessage(data as String),
      onError: (Object e, StackTrace st) {
        AppLogger.e('LG WS error', e, st);
        _setState(DriverState.error);
        _scheduleReconnect();
      },
      onDone: () {
        AppLogger.w('LG WS closed');
        if (_state != DriverState.disconnected) {
          _setState(DriverState.disconnected);
          _scheduleReconnect();
        }
      },
      cancelOnError: true,
    );

    await _sendRegistration(force: false);

    final hasKey = (_clientKey ?? '').isNotEmpty;

    // ✅ FIX: لو مفيش key → المستخدم هيوافق على التلفزيون
    // بنستنى 60 ثانية عشان يوافق
    bool registered = await _waitRegistered(hasKey ? 8 : 60);

    if (!registered && hasKey) {
      AppLogger.w('LG: old key rejected — clearing and retrying');
      await _clearClientKey();
      _isRegistered = false;
      _registeredCompleter = Completer<void>();
      await _sendRegistration(force: true);
      // ✅ استنى 60 ثانية للموافقة
      registered = await _waitRegistered(60);
    }

    if (!registered) {
      _setState(DriverState.error);
      throw const ConnectionException(
        'LG: انتهت مهلة الاقتران.\n'
        'وافق على الطلب الظاهر على شاشة التلفزيون ثم أعد المحاولة.',
      );
    }

    // ✅ بس بعد ما registered يتأكد نبعت connected
    _setState(DriverState.connected);
    _reconnectAttempts = 0;
    AppLogger.i('LG: connected & registered ✅');

    _requestPointerSocket().catchError(
      (Object e) => AppLogger.w('LG: pointer request failed: $e'),
    );
  }

  Future<void> _sendRegistration({required bool force}) async {
    final payload = <String, dynamic>{
      'forcePairing': force,
      'pairingType': 'PROMPT',
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
    };

    if ((_clientKey ?? '').isNotEmpty) {
      payload['client-key'] = _clientKey;
    }

    AppLogger.i('LG: sending register (force=$force, hasKey=${(_clientKey ?? '').isNotEmpty})');
    await _sendRaw({'id': 'register_0', 'type': 'register', 'payload': payload});
  }

  Future<bool> _waitRegistered(int seconds) async {
    try {
      await _registeredCompleter!.future.timeout(Duration(seconds: seconds));
      return true;
    } catch (_) {
      return _isRegistered;
    }
  }

  Future<void> _handleMessage(String raw) async {
    AppLogger.d('LG RX: $raw');

    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = msg['type'] as String? ?? '';

    switch (type) {
      case 'registered':
        final key = (msg['payload'] as Map?)?['client-key'];
        if (key is String && key.isNotEmpty) await _saveClientKey(key);
        _isRegistered = true;
        if (_registeredCompleter?.isCompleted == false) {
          _registeredCompleter!.complete();
        }
        AppLogger.i('LG: registered ✅ key=$key');

      case 'error':
        AppLogger.w('LG: error response: $raw');
        if (_registeredCompleter?.isCompleted == false) {
          _registeredCompleter!.completeError(raw);
        }

      case 'response':
        final uri = msg['uri'] as String? ?? '';
        if (uri.contains('getPointerInputSocket')) {
          final path = (msg['payload'] as Map?)?['socketPath'] as String?;
          if (path != null && path.isNotEmpty) {
            _pointerPath = path;
            AppLogger.i('LG: pointer path = $path');
            _connectPointerSocket().catchError(
              (Object e) => AppLogger.w('LG: pointer connect failed: $e'),
            );
          }
        }
    }
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
    final path = _pointerPath ?? '';
    if (path.isEmpty) return;

    final url = (path.startsWith('ws://') || path.startsWith('wss://'))
        ? path
        : 'ws://$ipAddress:${AppConstants.lgWebOsPort}$path';

    AppLogger.i('LG: connecting pointer WS = $url');

    try {
      await _pointerSocket?.close();
    } catch (_) {}

    _pointerSocket =
        await WebSocket.connect(url).timeout(AppConstants.connectTimeout);

    _pointerSocket!.listen(
      (d) => AppLogger.d('LG PTR RX: $d'),
      onError: (e) {
        AppLogger.w('LG PTR error: $e');
        _pointerSocket = null;
      },
      onDone: () {
        AppLogger.w('LG PTR closed');
        _pointerSocket = null;
      },
      cancelOnError: true,
    );
    AppLogger.i('LG: pointer socket ready ✅');
  }

  Future<void> _sendRaw(Map<String, dynamic> payload) async {
    final s = _ssapSocket;
    if (s == null) {
      AppLogger.w('LG TX SKIP: socket is null');
      return;
    }
    if (s.readyState != WebSocket.open) {
      AppLogger.w('LG TX SKIP: readyState=${s.readyState}');
      return;
    }
    final json = jsonEncode(payload);
    AppLogger.d('LG TX: $json');
    s.add(json);
  }

  Future<void> _sendPointerButton(String name) async {
    if (_pointerSocket == null ||
        _pointerSocket!.readyState != WebSocket.open) {
      AppLogger.i('LG: pointer not ready — requesting');
      await _requestPointerSocket();
      await Future.delayed(const Duration(milliseconds: 1500));
    }

    final p = _pointerSocket;
    if (p != null && p.readyState == WebSocket.open) {
      p.add('type:button\nname:$name\n\n');
      AppLogger.d('LG PTR TX: $name');
    } else {
      AppLogger.w('LG: pointer still not ready, SSAP fallback for $name');
      await _ssapButtonFallback(name);
    }
  }

  Future<void> _ssapButtonFallback(String name) async {
    switch (name) {
      case 'HOME':
        await _sendRaw({
          'id': 'cmd_${++_messageId}',
          'type': 'request',
          'uri': 'ssap://system.launcher/open',
          'payload': {'id': 'com.webos.app.home'},
        });
      case 'BACK':
        await _sendRaw({
          'id': 'cmd_${++_messageId}',
          'type': 'request',
          'uri': 'ssap://com.webos.service.ime/sendEnterKey',
          'payload': {},
        });
      default:
        AppLogger.w('LG: no SSAP fallback for $name');
    }
  }

  @override
  Future<void> sendCommand(TvCommand command) async {
    // ✅ FIX: لازم يكون registered فعلاً مش بس socket مفتوح
    // لأن التلفزيون بيرفض الأوامر قبل اكتمال الـ pairing
    if (!_isRegistered) {
      AppLogger.w('LG: sendCommand blocked — not registered yet');
      // ✅ لو socket مفتوح وبس مش registered → استنى شوية
      if (_ssapSocket != null &&
          _ssapSocket!.readyState == WebSocket.open &&
          _registeredCompleter != null &&
          !_registeredCompleter!.isCompleted) {
        AppLogger.i('LG: waiting for registration to complete...');
        try {
          await _registeredCompleter!.future
              .timeout(const Duration(seconds: 10));
        } catch (_) {}
      }
      if (!_isRegistered) {
        throw const DriverException('جاري إتمام الاقتران مع التلفزيون، انتظر...');
      }
    }

    final s = _ssapSocket;
    if (s == null || s.readyState != WebSocket.open) {
      throw DriverException('LG غير متصل (state: $_state)');
    }

    AppLogger.i('LG: ► sendCommand: $command');

    switch (command) {
      case TvCommand.power:
        await _sendRaw({
          'id': 'cmd_${++_messageId}',
          'type': 'request',
          'uri': 'ssap://system/turnOff',
          'payload': {},
        });

      case TvCommand.volumeUp:
        await _sendRaw({
          'id': 'cmd_${++_messageId}',
          'type': 'request',
          'uri': 'ssap://audio/volumeUp',
          'payload': {},
        });

      case TvCommand.volumeDown:
        await _sendRaw({
          'id': 'cmd_${++_messageId}',
          'type': 'request',
          'uri': 'ssap://audio/volumeDown',
          'payload': {},
        });

      case TvCommand.mute:
        _muteState = !_muteState;
        await _sendRaw({
          'id': 'cmd_${++_messageId}',
          'type': 'request',
          'uri': 'ssap://audio/setMute',
          'payload': {'mute': _muteState},
        });

      case TvCommand.channelUp:
        await _sendRaw({
          'id': 'cmd_${++_messageId}',
          'type': 'request',
          'uri': 'ssap://tv/channelUp',
          'payload': {},
        });

      case TvCommand.channelDown:
        await _sendRaw({
          'id': 'cmd_${++_messageId}',
          'type': 'request',
          'uri': 'ssap://tv/channelDown',
          'payload': {},
        });

      case TvCommand.up:    await _sendPointerButton('UP');
      case TvCommand.down:  await _sendPointerButton('DOWN');
      case TvCommand.left:  await _sendPointerButton('LEFT');
      case TvCommand.right: await _sendPointerButton('RIGHT');
      case TvCommand.ok:    await _sendPointerButton('ENTER');
      case TvCommand.back:  await _sendPointerButton('BACK');
      case TvCommand.home:  await _sendPointerButton('HOME');
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= AppConstants.maxReconnectAttempts) return;
    if (_state == DriverState.connecting) return;
    _reconnectAttempts++;
    AppLogger.i('LG: reconnect #$_reconnectAttempts');
    Future.delayed(AppConstants.reconnectDelay, () async {
      try {
        await connect();
      } catch (e) {
        AppLogger.e('LG: reconnect failed', e);
      }
    });
  }

  Future<void> _closeSockets() async {
    try { await _pointerSocket?.close(); } catch (_) {}
    try { await _ssapSocket?.close(); } catch (_) {}
    _pointerSocket = null;
    _ssapSocket = null;
  }

  @override
  Future<void> disconnect() async {
    _reconnectAttempts = AppConstants.maxReconnectAttempts;
    await _closeSockets();
    _isRegistered = false;
    _registeredCompleter = null;
    _setState(DriverState.disconnected);
    AppLogger.i('LG: disconnected');
  }
}
