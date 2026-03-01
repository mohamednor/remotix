// lib/presentation/providers/device_provider.dart

import '../../drivers/base/tv_driver.dart';
import '../../drivers/base/driver_factory.dart';

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
      _errorMessage = 'Scan failed: $e';
    }

    notifyListeners();
  }

  Future<void> selectDevice(Device device) async {
    // clean old connection
    try {
      await _driver?.disconnect();
    } catch (_) {}
    await _driverStateSub?.cancel();

    _selectedDevice = device;
    _driverState = DriverState.connecting;
    _errorMessage = null;

    // create new driver
    _driver = DriverFactory.create(device);

    // listen driver state
    _driverStateSub = _driver!.stateStream.listen((state) {
      _driverState = state;
      notifyListeners();
    });

    notifyListeners();

    // connect
    try {
      await _driver!.connect();
    } catch (e) {
      _errorMessage = e.toString();
      _driverState = DriverState.error;
      notifyListeners();
    }
  }

  Future<void> sendCommand(TvCommand command) async {
    final d = _driver;
    if (d == null) return;

    try {
      await d.sendCommand(command);
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    try {
      await _driver?.disconnect();
    } catch (_) {}

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
