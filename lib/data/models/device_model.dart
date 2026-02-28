// lib/data/models/device_model.dart

import '../../domain/entities/device.dart';

enum DeviceType { lgWebOs, samsungTizen, androidTv, unknown }

class DeviceModel {
  final String name;
  final String ipAddress;
  final String manufacturer;
  final String model;
  final DeviceType type;

  const DeviceModel({
    required this.name,
    required this.ipAddress,
    required this.manufacturer,
    required this.model,
    required this.type,
  });

  Device toEntity() => Device(
        name: name,
        ipAddress: ipAddress,
        manufacturer: manufacturer,
        model: model,
        type: type,
      );

  factory DeviceModel.fromEntity(Device device) => DeviceModel(
        name: device.name,
        ipAddress: device.ipAddress,
        manufacturer: device.manufacturer,
        model: device.model,
        type: device.type,
      );

  @override
  String toString() =>
      'DeviceModel(name: $name, ip: $ipAddress, type: $type)';
}
