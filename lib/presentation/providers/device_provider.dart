import 'dart:async';
import 'package:flutter/foundation.dart';

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

  DeviceProvider(this._discoverUseCase);

  ScanState get scanState => _scanState;
  List<Device> get devices => List.unmodifiable(_devices);
  Device? get selectedDevice => _selectedDevice;
  DriverState get driverState => _driverState;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _driverState == DriverState.connected;

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
      _errorMessage = e.toString();
    }

    notifyListeners();
  }

  Future<void> selectDevice(Device device) async {
    await _driver?.disconnect();
    await _driverStateSub?.cancel();

    _selectedDevice = device;
    _driverState = DriverState.connecting;
    _errorMessage = null;

    _driver = DriverFactory.create(device);

    _driverStateSub = _driver!.stateStream.listen((state) {
      _driverState = state;
      notifyListeners();
    });

    notifyListeners();

    try {
      await _driver!.connect();
    } catch (e) {
      _driverState = DriverState.error;
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
    _driver = null;
    _selectedDevice = null;
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
