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

/// حالة الـ pairing
enum LgPairingState { none, waitingPin, paired, failed }

class LgWebOsDriver extends TvDriver {
  final String ipAddress;

  WebSocket? _socket;
  WebSocket? _pointerSocket;

  final StreamController<DriverState> _stateController =
      StreamController<DriverState>.broadcast();

  // ✅ stream للـ pairing state عشان الـ UI يعرف يعرض شاشة الـ PIN
  final StreamController<LgPairingState> _pairingController =
      StreamController<LgPairingState>.broadcast();

  DriverState _state = DriverState.disconnected;
  LgPairingState _pairingState = LgPairingState.none;

  int _messageId = 0;
  int _reconnectAttempts = 0;

  String? _clientKey;
  String? _pointerPath;
  bool _muteState = false;
  bool _isRegistered = false;

  Completer<void>? _registeredCompleter;
  // ✅ Completer ينتظر المستخدم يدخل الـ PIN
  Completer<String>? _pinCompleter;

  LgWebOsDriver(this.ipAddress);

  @override
  DriverState get state => _state;

  @override
  Stream<DriverState> get stateStream => _stateController.stream;

  Stream<LgPairingState> get pairingStream => _pairingController.stream;
  LgPairingState get pairingState => _pairingState;

  void _setState(DriverState s) {
    if (_state == s) return;
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  void _setPairing(LgPairingState s) {
    _pairingState = s;
    if (!_pairingController.isClosed) _pairingController.add(s);
  }

  String get _prefsKey => 'lg_key_$ipAddress';

  // ─── Storage ──────────────────────────────────────────────────────

  Future<void> _loadKey() async {
    try {
      final p = await SharedPreferences.getInstance();
      _clientKey = p.getString(_prefsKey);
      AppLogger.i('LG: key=${_clientKey ?? "none"}');
    } catch (_) {}
  }

  Future<void> _saveKey(String k) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefsKey, k);
      _clientKey = k;
      AppLogger.i('LG: key saved');
    } catch (_) {}
  }

  Future<void> _deleteKey() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_prefsKey);
      _clientKey = null;
      AppLogger.w('LG: key deleted');
    } catch (_) {}
  }

  // ─── Connect ──────────────────────────────────────────────────────

  @override
  Future<void> connect() async {
    _setState(DriverState.connecting);
    _setPairing(LgPairingState.none);
    _isRegistered = false;

    await _loadKey();
    await _closeAll();

    // ── فتح socket ──
    WebSocket ws;
    try {
      ws = await WebSocket.connect(
        'ws://$ipAddress:${AppConstants.lgWebOsPort}',
      ).timeout(AppConstants.connectTimeout);
    } catch (_) {
      try {
        ws = await WebSocket.connect(
          'ws://$ipAddress:${AppConstants.lgWebOsPort}/api/websocket',
        ).timeout(AppConstants.connectTimeout);
      } catch (e, st) {
        AppLogger.e('LG: open failed', e, st);
        _setState(DriverState.error);
        throw ConnectionException('LG: $e');
      }
    }

    _socket = ws;
    AppLogger.i('LG: socket open');

    _registeredCompleter = Completer<void>();

    ws.listen(
      (data) => _onMessage(data as String),
      onError: (Object e, StackTrace st) {
        AppLogger.e('LG WS error', e, st);
        _isRegistered = false;
        _setState(DriverState.error);
        _scheduleReconnect();
      },
      onDone: () {
        AppLogger.w('LG WS closed');
        _isRegistered = false;
        if (_state != DriverState.disconnected) {
          _setState(DriverState.disconnected);
          _scheduleReconnect();
        }
      },
      cancelOnError: false,
    );

    // ── Register بالـ PIN ──
    _sendRegister(force: false);

    final hasKey = (_clientKey ?? '').isNotEmpty;

    // لو عنده key محفوظ → بيرد بسرعة
    // لو مفيش key → التلفزيون هيعرض PIN وننتظر المستخدم يدخله
    bool ok = await _waitReg(hasKey ? 8 : 120);

    if (!ok && hasKey) {
      AppLogger.w('LG: key rejected, retry without key');
      await _deleteKey();
      _isRegistered = false;
      _registeredCompleter = Completer<void>();
      _sendRegister(force: true);
      ok = await _waitReg(120);
    }

    if (!ok) {
      _setPairing(LgPairingState.failed);
      _setState(DriverState.error);
      throw const ConnectionException(
        'LG: انتهت مهلة الاقتران. أعد المحاولة.',
      );
    }

    if (_socket == null || _socket!.readyState != WebSocket.open) {
      _setState(DriverState.error);
      throw const ConnectionException('LG: socket closed after registration');
    }

    _setPairing(LgPairingState.paired);
    _setState(DriverState.connected);
    _reconnectAttempts = 0;
    AppLogger.i('LG: READY ✅');

    _requestPointer();
  }

  // ─── Register ─────────────────────────────────────────────────────

  void _sendRegister({required bool force}) {
    final payload = <String, dynamic>{
      'forcePairing': force,
      'pairingType': 'PIN',   // ✅ PIN بدل PROMPT
      'manifest': {
        'manifestVersion': 1,
        'appVersion': '1.1',
        'signed': {
          'created': '20260305',
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

    AppLogger.i('LG: register PIN (force=$force hasKey=${payload.containsKey('client-key')})');
    _tx({'id': 'reg_0', 'type': 'register', 'payload': payload});
  }

  /// ✅ إرسال الـ PIN للتلفزيون
  Future<void> submitPin(String pin) async {
    AppLogger.i('LG: submitting PIN=$pin');
    _tx({
      'id': 'pin_${++_messageId}',
      'type': 'request',
      'uri': 'ssap://pairing/setPin',
      'payload': {'pin': pin},
    });
    // أعطِ التلفزيون وقت للرد
    await Future.delayed(const Duration(milliseconds: 500));
  }

  Future<bool> _waitReg(int secs) async {
    try {
      await _registeredCompleter!.future.timeout(Duration(seconds: secs));
      return true;
    } catch (_) {
      return _isRegistered;
    }
  }

  // ─── Message Handler ──────────────────────────────────────────────

  void _onMessage(String raw) {
    AppLogger.d('LG ◀ $raw');
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
        if (key is String && key.isNotEmpty) _saveKey(key);
        _isRegistered = true;
        AppLogger.i('LG: registered ✅');
        if (_registeredCompleter?.isCompleted == false) {
          _registeredCompleter!.complete();
        }

      case 'response':
        // ✅ التلفزيون بعت pairing challenge → اعرض شاشة الـ PIN
        final returnValue = msg['returnValue'];
        if (returnValue == true || returnValue == 'true') {
          // رد ناجح على setPin → اكتمل الـ pairing
          AppLogger.i('LG: PIN accepted');
        }

        final uri = msg['uri'] as String? ?? '';
        if (uri.contains('getPointerInputSocket')) {
          final path = (msg['payload'] as Map?)?['socketPath'] as String?;
          if (path != null && path.isNotEmpty) {
            _pointerPath = path;
            _connectPointer();
          }
        }

      case 'error':
        AppLogger.w('LG: error ← $raw');
        if (_registeredCompleter?.isCompleted == false) {
          _registeredCompleter!.completeError('LG error');
        }

      // ✅ التلفزيون بيطلب PIN
      case 'pairing':
        AppLogger.i('LG: pairing challenge received → show PIN screen');
        _setPairing(LgPairingState.waitingPin);
    }
  }

  // ─── Pointer ──────────────────────────────────────────────────────

  void _requestPointer() {
    _tx({
      'id': 'ptr_${++_messageId}',
      'type': 'request',
      'uri': 'ssap://com.webos.service.networkinput/getPointerInputSocket',
      'payload': {},
    });
  }

  Future<void> _connectPointer() async {
    final path = _pointerPath ?? '';
    if (path.isEmpty) return;

    final url = (path.startsWith('ws://') || path.startsWith('wss://'))
        ? path
        : 'ws://$ipAddress:${AppConstants.lgWebOsPort}$path';

    AppLogger.i('LG: pointer → $url');
    try {
      await _pointerSocket?.close();
    } catch (_) {}
    try {
      _pointerSocket = await WebSocket.connect(url)
          .timeout(AppConstants.connectTimeout);
      _pointerSocket!.listen(
        (d) => AppLogger.d('LG PTR ◀ $d'),
        onError: (e) { _pointerSocket = null; },
        onDone: () { _pointerSocket = null; },
        cancelOnError: true,
      );
      AppLogger.i('LG: pointer ready ✅');
    } catch (e) {
      AppLogger.w('LG: pointer failed: $e');
      _pointerSocket = null;
    }
  }

  // ─── TX ───────────────────────────────────────────────────────────

  void _tx(Map<String, dynamic> payload) {
    final s = _socket;
    if (s == null) { AppLogger.w('LG TX: socket null'); return; }
    if (s.readyState != WebSocket.open) {
      AppLogger.w('LG TX: readyState=${s.readyState}');
      return;
    }
    final j = jsonEncode(payload);
    AppLogger.d('LG ▶ $j');
    s.add(j);
  }

  Future<void> _pointerTx(String name) async {
    if (_pointerSocket == null ||
        _pointerSocket!.readyState != WebSocket.open) {
      _requestPointer();
      await Future.delayed(const Duration(milliseconds: 1500));
    }

    final p = _pointerSocket;
    if (p != null && p.readyState == WebSocket.open) {
      p.add('type:button\nname:$name\n\n');
      AppLogger.d('LG PTR ▶ $name');
    } else {
      AppLogger.w('LG: pointer N/A, SSAP fallback: $name');
      _ssapFallback(name);
    }
  }

  void _ssapFallback(String name) {
    switch (name) {
      case 'HOME':
        _tx({'id': 'cmd_${++_messageId}', 'type': 'request',
            'uri': 'ssap://system.launcher/open',
            'payload': {'id': 'com.webos.app.home'}});
      case 'BACK':
        _tx({'id': 'cmd_${++_messageId}', 'type': 'request',
            'uri': 'ssap://com.webos.service.ime/sendEnterKey',
            'payload': {}});
    }
  }

  // ─── Commands ─────────────────────────────────────────────────────

  @override
  Future<void> sendCommand(TvCommand command) async {
    AppLogger.i('LG: cmd=$command reg=$_isRegistered socketState=${_socket?.readyState}');

    if (!_isRegistered) {
      final comp = _registeredCompleter;
      if (comp != null && !comp.isCompleted) {
        try {
          await comp.future.timeout(const Duration(seconds: 8));
        } catch (_) {}
      }
      if (!_isRegistered) {
        throw const DriverException('التلفزيون لم يكتمل الاقتران بعد');
      }
    }

    final s = _socket;
    if (s == null || s.readyState != WebSocket.open) {
      throw DriverException('انقطع الاتصال (state=$_state)');
    }

    switch (command) {
      case TvCommand.power:
        _tx({'id': 'cmd_${++_messageId}', 'type': 'request',
            'uri': 'ssap://system/turnOff', 'payload': {}});
      case TvCommand.volumeUp:
        _tx({'id': 'cmd_${++_messageId}', 'type': 'request',
            'uri': 'ssap://audio/volumeUp', 'payload': {}});
      case TvCommand.volumeDown:
        _tx({'id': 'cmd_${++_messageId}', 'type': 'request',
            'uri': 'ssap://audio/volumeDown', 'payload': {}});
      case TvCommand.mute:
        _muteState = !_muteState;
        _tx({'id': 'cmd_${++_messageId}', 'type': 'request',
            'uri': 'ssap://audio/setMute',
            'payload': {'mute': _muteState}});
      case TvCommand.channelUp:
        _tx({'id': 'cmd_${++_messageId}', 'type': 'request',
            'uri': 'ssap://tv/channelUp', 'payload': {}});
      case TvCommand.channelDown:
        _tx({'id': 'cmd_${++_messageId}', 'type': 'request',
            'uri': 'ssap://tv/channelDown', 'payload': {}});
      case TvCommand.up:    await _pointerTx('UP');
      case TvCommand.down:  await _pointerTx('DOWN');
      case TvCommand.left:  await _pointerTx('LEFT');
      case TvCommand.right: await _pointerTx('RIGHT');
      case TvCommand.ok:    await _pointerTx('ENTER');
      case TvCommand.back:  await _pointerTx('BACK');
      case TvCommand.home:  await _pointerTx('HOME');
    }
  }

  // ─── Reconnect ────────────────────────────────────────────────────

  void _scheduleReconnect() {
    if (_reconnectAttempts >= AppConstants.maxReconnectAttempts) return;
    if (_state == DriverState.connecting) return;
    _reconnectAttempts++;
    Future.delayed(AppConstants.reconnectDelay, () async {
      try { await connect(); } catch (e) { AppLogger.e('LG reconnect', e); }
    });
  }

  // ─── Cleanup ──────────────────────────────────────────────────────

  Future<void> _closeAll() async {
    try { await _pointerSocket?.close(); } catch (_) {}
    try { await _socket?.close(); } catch (_) {}
    _pointerSocket = null;
    _socket = null;
  }

  @override
  Future<void> disconnect() async {
    _reconnectAttempts = AppConstants.maxReconnectAttempts;
    _isRegistered = false;
    _registeredCompleter = null;
    _pinCompleter = null;
    await _closeAll();
    _setState(DriverState.disconnected);
  }
}
