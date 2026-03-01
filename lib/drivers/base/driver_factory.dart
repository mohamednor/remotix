// lib/drivers/base/driver_factory.dart

import '../../domain/entities/device.dart';
import 'tv_driver.dart';
import '../androidtv/android_tv_driver.dart';
import '../lg/lg_webos_driver.dart';
import '../samsung/samsung_tizen_driver.dart';

class DriverFactory {
  static TvDriver create(Device device) {
    final manufacturer = (device.manufacturer ?? '').toLowerCase();
    final model = (device.model ?? '').toLowerCase();
    final name = (device.name ?? '').toLowerCase();

    final combined = '$manufacturer $model $name';

    if (combined.contains('lg') || combined.contains('webos')) {
      return LgWebOsDriver(device.ipAddress);
    }

    if (combined.contains('samsung') || combined.contains('tizen')) {
      return SamsungTizenDriver(device.ipAddress);
    }

    if (combined.contains('android')) {
      return AndroidTvDriver(device.ipAddress);
    }

    throw Exception(
      'Unsupported TV type: ${device.ipAddress}',
    );
  }
}
