// lib/data/repositories/device_repository_impl.dart

import '../../core/network/ssdp_discovery.dart';
import '../../domain/entities/device.dart';
import '../../domain/repositories/device_repository.dart';

class DeviceRepositoryImpl implements DeviceRepository {
  final SsdpDiscovery _ssdpDiscovery;

  DeviceRepositoryImpl(this._ssdpDiscovery);

  @override
  Future<List<Device>> discoverDevices() async {
    final models = await _ssdpDiscovery.discover();
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Stream<Device> get deviceStream =>
      _ssdpDiscovery.deviceStream.map((m) => m.toEntity());
}
