// lib/presentation/providers/device_provider.dart

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/device.dart';
import '../../domain/entities/tv_command.dart';
import '../../domain/usecases/discover_devices_usecase.dart';
import '../../drivers/base/tv_driver.dart';
import '../../drivers/base/driver_factory.dart';
import '../../drivers/lg/lg_webos_driver.dart';
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

  // ✅ PIN pairing state
  bool _waitingForPin = false;
  StreamSubscription<LgPairingState>? _pairingSub;

  bool _isSelecting = false;

  DeviceProvider(this._discoverUseCase);

  ScanState get scanState => _scanState;
  List<Device> get devices => List.unmodifiable(_devices);
  Device? get selectedDevice => _selectedDevice;
  DriverState get driverState => _driverState;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _driverState == DriverState.connected;
  bool get waitingForPin => _waitingForPin;

  // ✅ للـ UI يوصل للـ driver مباشرة لإرسال PIN
  TvDriver? get currentDriver => _driver;

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
      AppLogger.i('Scan: ${_devices.length} found');
    } catch (e, st) {
      AppLogger.e('Scan failed', e, st);
      _scanState = ScanState.error;
      _errorMessage = e.toString();
    }

    notifyListeners();
  }

  Future<void> selectDevice(Device device) async {
    if (_isSelecting) return;
    _isSelecting = true;

    try {
      await _driverStateSub?.cancel();
      await _pairingSub?.cancel();
      _driverStateSub = null;
      _pairingSub = null;

      try { await _driver?.disconnect(); } catch (_) {}
      _driver = null;
      _waitingForPin = false;

      _selectedDevice = device;
      _driverState = DriverState.connecting;
      _errorMessage = null;
      notifyListeners();

      final driver = DriverFactory.create(device);
      _driver = driver;

      _driverStateSub = driver.stateStream.listen((state) {
        if (_driverState == state) return;
        _driverState = state;
        notifyListeners();
      });

      // ✅ اشترك في pairing stream لو LG
      if (driver is LgWebOsDriver) {
        _pairingSub = driver.pairingStream.listen((ps) {
          if (ps == LgPairingState.waitingPin) {
            _waitingForPin = true;
            notifyListeners();
          } else if (ps == LgPairingState.paired) {
            _waitingForPin = false;
            notifyListeners();
          }
        });
      }

      await driver.connect();

      _driverState = driver.state;
      _waitingForPin = false;
      notifyListeners();
    } catch (e, st) {
      AppLogger.e('selectDevice failed', e, st);
      _driverState = DriverState.error;
      _waitingForPin = false;
      _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      notifyListeners();
    } finally {
      _isSelecting = false;
    }
  }

  Future<void> sendCommand(TvCommand command) async {
    final d = _driver;
    if (d == null) throw Exception('لا يوجد تلفزيون متصل');
    try {
      await d.sendCommand(command);
    } catch (e, st) {
      AppLogger.e('sendCommand failed: $command', e, st);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await _driverStateSub?.cancel();
    await _pairingSub?.cancel();
    _driverStateSub = null;
    _pairingSub = null;
    try { await _driver?.disconnect(); } catch (_) {}
    _driver = null;
    _selectedDevice = null;
    _driverState = DriverState.disconnected;
    _waitingForPin = false;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _driverStateSub?.cancel();
    _pairingSub?.cancel();
    _driver?.disconnect().catchError((_) {});
    super.dispose();
  }
}
