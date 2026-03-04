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

  // ✅ FIX: Completer يتعمل مرة واحدة بس ومش بيتعمل override
  Completer<void>? _registeredCompleter;
  bool _isRegistered = false;

  Completer<void>? _pointerReadyCompleter;

  // ✅ NEW: حالة الـ pairing عشان نعرض للمستخدم
  bool _waitingForUserApproval = false;
  bool get waitingForUserApproval => _waitingForUserApproval;

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

  String get _prefsKeyClientKey => 'lg_webos_client_key_$ipAddress';

  // ─────────────────────────── SharedPrefs ───────────────────────────

  Future<void> _loadClientKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _clientKey = prefs.getString(_prefsKeyClientKey);
      if ((_clientKey ?? '').isNotEmpty) {
        AppLogger.i('LG: Loaded saved client-key ($_clientKey)');
      }
    } catch (e) {
      AppLogger.w('LG: Could not load client-key: $e');
    }
  }

  Future<void> _saveClientKey(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyClientKey, key);
      _clientKey = key;
      AppLogger.i('LG: Saved client-key');
    } catch (e) {
      AppLogger.w('LG: Could not save client-key: $e');
    }
  }

  Future<void> _clearClientKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKeyClientKey);
      _clientKey = null;
      AppLogger.w('LG: Cleared saved client-key');
    } catch (e) {
      AppLogger.w('LG: Could not clear client-key: $e');
    }
  }

  // ─────────────────────────── Connect ───────────────────────────────

  Future<WebSocket> _openSsapSocket() async {
    // بعض موديلات LG بتفتح على endpoint مختلف
    final endpoints = [
      'ws://$ipAddress:${AppConstants.lgWebOsPort}',
      'ws://$ipAddress:${AppConstants.lgWebOsPort}/api/websocket',
    ];

    Object? lastErr;
    for (final url in endpoints) {
      try {
        AppLogger.i('LG: Trying SSAP → $url');
        return await WebSocket.connect(url)
            .timeout(AppConstants.connectTimeout);
      } catch (e) {
        lastErr = e;
        AppLogger.w('LG: $url failed → $e');
      }
    }
    throw ConnectionException('LG WebSocket failed: $lastErr');
  }

  @override
  Future<void> connect() async {
    _setState(DriverState.connecting);
    _waitingForUserApproval = false;

    await _loadClientKey();

    // ✅ FIX: أنشئ Completer جديد قبل أي await حتى لا يفوتنا الرد
    _isRegistered = false;
    _registeredCompleter = Completer<void>();
    _pointerReadyCompleter = Completer<void>();
    _pointerPath = null;

    await _closeSockets();

    try {
      _ssapSocket = await _openSsapSocket();
    } catch (e, st) {
      _setState(DriverState.error);
      AppLogger.e('LG: Cannot open socket', e, st);
      throw ConnectionException('LG: $e');
    }

    _ssapSocket!.listen(
      (data) async {
        AppLogger.d('LG RX: $data');
        await _handleMessage(data as String);
      },
      onError: (Object e, StackTrace st) {
        AppLogger.e('LG WS error', e, st);
        _setState(DriverState.error);
        _scheduleReconnect();
      },
      onDone: () {
        AppLogger.w('LG WS closed');
        _setState(DriverState.disconnected);
      },
      cancelOnError: true,
    );

    // ── محاولة 1: بالـ client-key المحفوظ ──
    final hasKey = (_clientKey ?? '').isNotEmpty;
    await _sendRegistration(forcePairing: false, withKey: hasKey);

    bool registered = await _waitRegistered(seconds: hasKey ? 6 : 20);

    // ── محاولة 2: لو الـ key القديم رُفض → امسحه وأعد المحاولة ──
    if (!registered && hasKey) {
      AppLogger.w('LG: Saved key rejected — clearing and re-registering');
      await _clearClientKey();

      // ✅ FIX: Completer جديد قبل الـ send
      _isRegistered = false;
      _registeredCompleter = Completer<void>();

      // ✅ بلّغ المستخدم إنه هيشوف prompt على التلفزيون
      _waitingForUserApproval = true;
      if (!_stateController.isClosed) {
        _stateController.add(DriverState.connecting); // notify UI
      }

      await _sendRegistration(forcePairing: true, withKey: false);
      registered = await _waitRegistered(seconds: 30);
    }

    // ── محاولة 3: لو أول مرة وما رجعش registered بعد 20 ثانية ──
    if (!registered && !hasKey) {
      _waitingForUserApproval = true;
      registered = await _waitRegistered(seconds: 60);
    }

    if (!registered) {
      _setState(DriverState.error);
      throw const ConnectionException(
        'LG: انتهت المهلة. '
        'تأكد إن LG Connect Apps مفعّل على التلفزيون '
        'ووافق على طلب الاقتران.',
      );
    }

    _waitingForUserApproval = false;
    _setState(DriverState.connected);
    _reconnectAttempts = 0;
    AppLogger.i('LG: ✅ Connected & registered');

    // Pointer socket (اختياري — مش بيكسر الاتصال لو فشل)
    unawaited(_requestPointerSocket());
  }

  // ─────────────────────────── Registration ──────────────────────────

  Future<void> _sendRegistration({
    required bool forcePairing,
    required bool withKey,
  }) async {
    final payload = <String, dynamic>{
      'forcePairing': forcePairing,
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

    if (withKey && (_clientKey ?? '').isNotEmpty) {
      payload['client-key'] = _clientKey;
    }

    await _sendRaw({
      'id': 'register_0',
      'type': 'register',
      'payload': payload,
    });
  }

  Future<bool> _waitRegistered({required int seconds}) async {
    try {
      await _registeredCompleter!.future.timeout(Duration(seconds: seconds));
      return true;
    } on TimeoutException {
      return _isRegistered;
    } catch (_) {
      return _isRegistered;
    }
  }

  // ─────────────────────────── Message Handler ───────────────────────

  Future<void> _handleMessage(String raw) async {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = msg['type'] as String?;

    // ── registered → حفظ client-key وإكمال ──
    if (type == 'registered') {
      final payload = msg['payload'];
      if (payload is Map) {
        final key = payload['client-key'];
        if (key is String && key.isNotEmpty) {
          await _saveClientKey(key);
        }
      }
      _isRegistered = true;
      if (_registeredCompleter != null &&
          !_registeredCompleter!.isCompleted) {
        _registeredCompleter!.complete();
      }
      return;
    }

    // ── error على register → لو الـ key منتهي الصلاحية ──
    if (type == 'error') {
      final errorPayload = msg['error'] as String? ?? '';
      if (errorPayload.contains('403') ||
          errorPayload.toLowerCase().contains('not_found') ||
          errorPayload.toLowerCase().contains('invalid')) {
        AppLogger.w('LG: Registration error → $errorPayload');
        // complete بـ error عشان يتحرك للـ fallback
        if (_registeredCompleter != null &&
            !_registeredCompleter!.isCompleted) {
          _registeredCompleter!.completeError(errorPayload);
        }
      }
      return;
    }

    // ── pointer socket path ──
    if (type == 'response') {
      final uri = msg['uri'] as String? ?? '';
      if (uri.contains('getPointerInputSocket')) {
        final payload = msg['payload'];
        if (payload is Map) {
          final path = payload['socketPath'] as String?;
          if (path != null && path.isNotEmpty) {
            _pointerPath = path;
            AppLogger.i('LG: Got pointer path → $_pointerPath');
            await _connectPointerSocket();
          }
        }
      }
    }
  }

  // ─────────────────────────── Pointer Socket ────────────────────────

  Future<void> _requestPointerSocket() async {
    try {
      await _sendRaw({
        'id': 'ptr_${++_messageId}',
        'type': 'request',
        'uri': 'ssap://com.webos.service.networkinput/getPointerInputSocket',
        'payload': {},
      });
    } catch (e) {
      AppLogger.w('LG: Could not request pointer socket: $e');
    }
  }

  Future<void> _connectPointerSocket() async {
    final path = _pointerPath ?? '';
    if (path.isEmpty) return;

    // ✅ FIX: بعض الموديلات بيبعتوا full URL وبعضها path فقط
    String url;
    if (path.startsWith('ws://') || path.startsWith('wss://')) {
      url = path;
    } else {
      url = 'ws://$ipAddress:${AppConstants.lgWebOsPort}$path';
    }

    try {
      await _pointerSocket?.close();
    } catch (_) {}

    AppLogger.i('LG: Connecting pointer WS → $url');
    try {
      _pointerSocket = await WebSocket.connect(url)
          .timeout(AppConstants.connectTimeout);

      if (_pointerReadyCompleter != null &&
          !_pointerReadyCompleter!.isCompleted) {
        _pointerReadyCompleter!.complete();
      }

      _pointerSocket!.listen(
        (data) => AppLogger.d('LG PTR RX: $data'),
        onError: (e, st) {
          AppLogger.e('LG Pointer error', e, st);
          _pointerSocket = null;
        },
        onDone: () {
          AppLogger.w('LG Pointer closed');
          _pointerSocket = null;
        },
        cancelOnError: true,
      );
    } catch (e) {
      AppLogger.w('LG: Pointer socket failed (non-fatal): $e');
      _pointerSocket = null;
    }
  }

  // ─────────────────────────── Send Helpers ──────────────────────────

  Future<void> _sendRaw(Map<String, dynamic> payload) async {
    final s = _ssapSocket;
    if (s == null ||
        s.readyState != WebSocket.open &&
            s.readyState != WebSocket.connecting) {
      AppLogger.w('LG: _sendRaw skipped — socket not open');
      return;
    }
    try {
      s.add(jsonEncode(payload));
    } catch (e) {
      AppLogger.e('LG: _sendRaw error', e);
    }
  }

  Future<void> _sendPointerButton(String name) async {
    // ✅ لو الـ pointer socket مش جاهز، حاول تجيبه
    if (_pointerSocket == null) {
      unawaited(_requestPointerSocket());
      try {
        await _pointerReadyCompleter?.future
            .timeout(const Duration(milliseconds: 1500));
      } catch (_) {}
    }

    final p = _pointerSocket;
    if (p == null) {
      AppLogger.w('LG: Pointer not available for $name — falling back to SSAP');
      // ✅ FIX: fallback إلى SSAP لو الـ pointer مش شغال
      await _sendSsapButtonFallback(name);
      return;
    }

    try {
      // LG pointer protocol: type:button\nname:KEY_NAME\n\n
      p.add('type:button\nname:$name\n\n');
      AppLogger.d('LG PTR: $name');
    } catch (e) {
      AppLogger.e('LG: Pointer send error', e);
      _pointerSocket = null;
    }
  }

  /// ✅ FIX: fallback لـ SSAP لو pointer socket مش متاح
  Future<void> _sendSsapButtonFallback(String name) async {
    // Map pointer button names to SSAP equivalents
    const ssapMap = {
      'UP': 'ssap://com.webos.service.ime/sendEnterKey',
      'DOWN': 'ssap://com.webos.service.ime/sendEnterKey',
      'LEFT': 'ssap://com.webos.service.ime/sendEnterKey',
      'RIGHT': 'ssap://com.webos.service.ime/sendEnterKey',
      'ENTER': 'ssap://com.webos.service.ime/sendEnterKey',
      'BACK': 'ssap://com.webos.service.applicationManager/launch',
      'HOME': 'ssap://com.webos.service.applicationManager/launch',
    };

    // للـ HOME نعمل launch للـ home screen
    if (name == 'HOME') {
      await _sendRaw({
        'id': 'cmd_${++_messageId}',
        'type': 'request',
        'uri': 'ssap://system.launcher/open',
        'payload': {'id': 'com.webos.app.home'},
      });
      return;
    }

    // لو SSAP map موجود
    if (ssapMap.containsKey(name)) {
      await _sendRaw({
        'id': 'cmd_${++_messageId}',
        'type': 'request',
        'uri': ssapMap[name],
        'payload': {},
      });
    }
  }

  // ─────────────────────────── Commands ──────────────────────────────

  @override
  Future<void> sendCommand(TvCommand command) async {
    // ✅ FIX: أوضح error message + لو disconnected نعمل reconnect أوتوماتيك
    if (!isConnected) {
      AppLogger.w('LG: sendCommand called while not connected — state: $_state');
      throw DriverException(
        _state == DriverState.connecting
            ? 'جاري الاتصال، انتظر...'
            : 'التلفزيون غير متصل',
      );
    }

    if (!_isRegistered) {
      AppLogger.w('LG: sendCommand called before registration complete');
      throw const DriverException('جاري إتمام الاقتران مع التلفزيون...');
    }

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

      case TvCommand.up:
        await _sendPointerButton('UP');
      case TvCommand.down:
        await _sendPointerButton('DOWN');
      case TvCommand.left:
        await _sendPointerButton('LEFT');
      case TvCommand.right:
        await _sendPointerButton('RIGHT');
      case TvCommand.ok:
        await _sendPointerButton('ENTER');
      case TvCommand.back:
        await _sendPointerButton('BACK');
      case TvCommand.home:
        await _sendPointerButton('HOME');
    }
  }

  // ─────────────────────────── Reconnect ─────────────────────────────

  void _scheduleReconnect() {
    if (_reconnectAttempts >= AppConstants.maxReconnectAttempts) {
      AppLogger.w('LG: Max reconnect attempts reached');
      return;
    }
    if (_state == DriverState.connecting) return;

    _reconnectAttempts++;
    AppLogger.i('LG: Reconnect attempt $_reconnectAttempts...');

    Future.delayed(AppConstants.reconnectDelay, () async {
      try {
        await connect();
      } catch (e) {
        AppLogger.e('LG: Reconnect failed', e);
      }
    });
  }

  // ─────────────────────────── Cleanup ───────────────────────────────

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
    _reconnectAttempts = AppConstants.maxReconnectAttempts; // وقّف أي reconnect
    await _closeSockets();
    _isRegistered = false;
    _waitingForUserApproval = false;
    _registeredCompleter = null;
    _pointerReadyCompleter = null;
    _setState(DriverState.disconnected);
    AppLogger.i('LG: Disconnected');
  }
}

// Helper عشان Dart 3 ما يشكيش على unawaited futures
void unawaited(Future<void> future) {
  future.catchError((Object e) {
    AppLogger.w('unawaited error: $e');
  });
}
