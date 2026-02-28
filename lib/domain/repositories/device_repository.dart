// lib/domain/repositories/device_repository.dart

import '../entities/device.dart';

abstract class DeviceRepository {
  Future<List<Device>> discoverDevices();
  Stream<Device> get deviceStream;
}
