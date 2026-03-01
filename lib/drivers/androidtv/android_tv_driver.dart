// lib/drivers/androidtv/android_tv_driver.dart

import 'dart:async';

import '../base/tv_driver.dart';
import '../../domain/entities/tv_command.dart';
import '../../core/error/exceptions.dart';

class AndroidTvDriver extends TvDriver {
  final String ipAddress;

  final StreamController<DriverState> _stateController =
      StreamController<DriverState>.broadcast();

  DriverState _state = DriverState.disconnected;

  AndroidTvDriver(this.ipAddress);

  @override
  DriverState get state => _state;

  @override
  Stream<DriverState> get stateStream => _stateController.stream;

  void _setState(DriverState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  @override
  Future<void> connect() async {
    // Placeholder: Android TV ADB مش مدعوم حالياً
    _setState(DriverState.error);
    throw const ConnectionException(
      'Android TV يحتاج Pairing/Wireless Debugging (ADB) علشان التحكم يشتغل.',
    );
  }

  @override
  Future<void> sendCommand(TvCommand command) async {
    if (!isConnected) {
      throw const DriverException(
        'Android TV غير مدعوم حالياً بدون Pairing (ADB).',
      );
    }
    // لو اتدعّم ADB لاحقاً، هنا مكان التنفيذ
  }

  @override
  Future<void> disconnect() async {
    _setState(DriverState.disconnected);
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _stateController.close();
  }
}
