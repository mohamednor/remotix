import '../../domain/entities/device.dart';
import 'tv_driver.dart';

import '../lg/lg_webos_driver.dart';
import '../samsung/samsung_tizen_driver.dart';
import '../androidtv/android_tv_driver.dart';

class DriverFactory {
  static TvDriver create(Device device) {
    final label = (device.typeLabel).toLowerCase();

    if (label.contains('webos') || label.contains('lg')) {
      return LgWebOsDriver(device.ipAddress);
    }

    if (label.contains('tizen') || label.contains('samsung')) {
      return SamsungTizenDriver(device.ipAddress);
    }

    if (label.contains('android') || label.contains('google')) {
      return AndroidTvDriver(device.ipAddress);
    }

    // Default:
    return SamsungTizenDriver(device.ipAddress);
  }
}
