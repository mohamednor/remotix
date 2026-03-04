// lib/presentation/providers/device_provider.dart

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/device.dart';
import '../../domain/entities/tv_command.dart';
import '../../domain/usecases/discover_devices_usecase.dart';
import '../../drivers/base/tv_driver.dart';
import '../../drivers/base/driver_factory.dart';
import '../../drivers/lg/lg_webos_driver.dart';
import '../../drivers/samsung/samsung_tizen_driver.dart';
import '../../core/utils/app_logger.dart';

enum ScanState { idle, scanning, done, error }

class DeviceProvider extends ChangeNotifier {
  final DiscoverDevicesUseCase _discoverUseCase;

  ScanState _scanState = ScanState.idle;
  final List<Device> _devices = [];
  Device? _selectedDevice;
  TvDriver? _driver;
  DriverState _driverState = DriverState.disconnected;
  String? _errorMessage;
  StreamSubscription<DriverState>? _driverStateSub;

  bool _isSelecting = false;

  DeviceProvider(this._discoverUseCase);

  // ─────────────────────────── Getters ──────────────────────────────

  ScanState get scanState => _scanState;
  List<Device> get devices => List.unmodifiable(_devices);
  Device? get selectedDevice => _selectedDevice;
  DriverState get driverState => _driverState;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _driverState == DriverState.connected;

  /// ✅ NEW: expose driver للـ UI عشان يعرف pairing state
  TvDriver? get currentDriver => _driver;

  /// ✅ NEW: هل في انتظار موافقة على التلفزيون؟
  bool get waitingForPairing {
    final d = _driver;
    if (d is LgWebOsDriver) return d.waitingForUserApproval;
    if (d is SamsungTizenDriver) return d.waitingForApproval;
    return false;
  }

  // ─────────────────────────── Scan ─────────────────────────────────

  Future<void> scanDevices() async {
    _scanState = ScanState.scanning;
    _devices.clear();
    _errorMessage = null;
    notifyListeners();

    try {
      final found = await _discoverUseCase();
      _devices
        ..clear()
        ..addAll(found);
      _scanState = ScanState.done;
      AppLogger.i('Scan complete: ${_devices.length} devices found');
    } catch (e, st) {
      AppLogger.e('Scan failed', e, st);
      _scanState = ScanState.error;
      _errorMessage = e.toString();
    }

    notifyListeners();
  }

  // ─────────────────────────── Select & Connect ─────────────────────

  Future<void> selectDevice(Device device) async {
    if (_isSelecting) return;
    _isSelecting = true;

    try {
      // إلغاء الاشتراك القديم
      await _driverStateSub?.cancel();
      _driverStateSub = null;

      // تنظيف الـ driver القديم
      try {
        await _driver?.disconnect();
      } catch (_) {}
      _driver = null;

      _selectedDevice = device;
      _driverState = DriverState.connecting;
      _errorMessage = null;
      notifyListeners();

      final driver = DriverFactory.create(device);
      _driver = driver;

      // ✅ FIX: اشترك في stream قبل ما connect() يترسل
      _driverStateSub = driver.stateStream.listen((state) {
        if (_driverState == state) return;
        _driverState = state;
        notifyListeners();
      });

      await driver.connect();

      // ✅ لو connect() رجع من غير exception، التلفزيون connected
      _driverState = driver.state;
      notifyListeners();
    } catch (e, st) {
      AppLogger.e('selectDevice failed', e, st);
      _driverState = DriverState.error;
      _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      notifyListeners();
    } finally {
      _isSelecting = false;
    }
  }

  // ─────────────────────────── Commands ─────────────────────────────

  Future<void> sendCommand(TvCommand command) async {
    final d = _driver;
    if (d == null) {
      throw Exception('لا يوجد تلفزيون متصل');
    }

    try {
      await d.sendCommand(command);
    } catch (e, st) {
      AppLogger.e('sendCommand failed: $command', e, st);
      // ✅ ارمي الـ exception للـ UI عشان يعرض error
      rethrow;
    }
  }

  // ─────────────────────────── Disconnect ───────────────────────────

  Future<void> disconnect() async {
    await _driverStateSub?.cancel();
    _driverStateSub = null;

    try {
      await _driver?.disconnect();
    } catch (_) {}

    _driver = null;
    _selectedDevice = null;
    _driverState = DriverState.disconnected;
    _errorMessage = null;
    notifyListeners();
  }

  // ─────────────────────────── Dispose ──────────────────────────────

  @override
  void dispose() {
    _driverStateSub?.cancel();
    _driver?.disconnect().catchError((_) {});
    super.dispose();
  }
}
