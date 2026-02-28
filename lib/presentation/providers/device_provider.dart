// lib/presentation/providers/device_provider.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/device.dart';
import '../../domain/entities/tv_command.dart';
import '../../domain/usecases/discover_devices_usecase.dart';
import '../../drivers/base/tv_driver.dart';
import '../../drivers/base/driver_factory.dart';
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

  // ✅ للـ Android TV / WOL etc (لو عندك UI بيطلب MAC)
  String? _macAddress;

  DeviceProvider(this._discoverUseCase);

  ScanState get scanState => _scanState;
  List<Device> get devices => List.unmodifiable(_devices);
  Device? get selectedDevice => _selectedDevice;
  DriverState get driverState => _driverState;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _driverState == DriverState.connected;

  String? get macAddress => _macAddress;

  String _macPrefsKey(String ip) => 'device_mac_$ip';

  Future<void> loadSavedMacIfAny(Device device) async {
    final prefs = await SharedPreferences.getInstance();
    _macAddress = prefs.getString(_macPrefsKey(device.ipAddress));
    notifyListeners();
  }

  // ✅ خليها Future عشان await مايكسرش
  Future<void> setMacAddress(String mac) async {
    _macAddress = mac.trim();
    if (_selectedDevice != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_macPrefsKey(_selectedDevice!.ipAddress), _macAddress!);
    }
    notifyListeners();
  }

  Future<void> scanDevices() async {
    _scanState = ScanState.scanning;
    _devices.clear();
    _errorMessage = null;
    notifyListeners();

    try {
      final found = await _discoverUseCase();
      _devices.addAll(found);
      _scanState = ScanState.done;
      AppLogger.i('Scan complete: ${_devices.length} devices found');
    } catch (e, st) {
      AppLogger.e('Scan failed', e, st);
      _scanState = ScanState.error;
      _errorMessage = 'Scan failed: $e';
    }
    notifyListeners();
  }

  Future<void> selectDevice(Device device) async {
    await _driver?.disconnect();
    await _driverStateSub?.cancel();

    _selectedDevice = device;
    _driver = DriverFactory.create(device);

    // load saved mac (لو عندك شاشة بتستخدمها)
    await loadSavedMacIfAny(device);

    _driverStateSub = _driver!.stateStream.listen((state) {
      _driverState = state;
      notifyListeners();
    });

    notifyListeners();

    try {
      await _driver!.connect();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> sendCommand(TvCommand command) async {
    if (_driver == null) return;
    try {
      await _driver!.sendCommand(command);
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _driver?.disconnect();
    _selectedDevice = null;
    _driver = null;
    _driverState = DriverState.disconnected;
    notifyListeners();
  }

  @override
  void dispose() {
    _driverStateSub?.cancel();
    _driver?.disconnect();
    super.dispose();
  }
}
