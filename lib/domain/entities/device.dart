// lib/domain/entities/device.dart

import '../../data/models/device_model.dart';

class Device {
  final String name;
  final String ipAddress;
  final String manufacturer;
  final String model;
  final DeviceType type;

  const Device({
    required this.name,
    required this.ipAddress,
    required this.manufacturer,
    required this.model,
    required this.type,
  });

  String get displayName => name.isNotEmpty ? name : 'Smart TV ($ipAddress)';

  String get typeLabel {
    switch (type) {
      case DeviceType.lgWebOs:
        return 'LG webOS';
      case DeviceType.samsungTizen:
        return 'Samsung Tizen';
      case DeviceType.androidTv:
        return 'Android TV';
      case DeviceType.unknown:
        return 'Unknown';
    }
  }
}
