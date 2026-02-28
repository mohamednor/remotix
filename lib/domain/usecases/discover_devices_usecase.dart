// lib/domain/usecases/discover_devices_usecase.dart

import '../entities/device.dart';
import '../repositories/device_repository.dart';

class DiscoverDevicesUseCase {
  final DeviceRepository repository;

  const DiscoverDevicesUseCase(this.repository);

  Future<List<Device>> call() => repository.discoverDevices();

  Stream<Device> get deviceStream => repository.deviceStream;
}
