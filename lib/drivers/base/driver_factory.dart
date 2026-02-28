import '../../domain/entities/device.dart';
import 'tv_driver.dart';

import '../lg/lg_webos_driver.dart';
import '../samsung/samsung_tizen_driver.dart';
import '../androidtv/android_tv_driver.dart';

import '../../core/utils/app_logger.dart';

class DriverFactory {
  static TvDriver create(Device device) {
    AppLogger.i(
        'DriverFactory: Creating driver for ${device.typeLabel} @ ${device.ipAddress}');

    switch (device.type) {
      case DeviceType.lgWebOs:
        return LgWebOsDriver(device.ipAddress);

      case DeviceType.samsungTizen:
        return SamsungTizenDriver(device.ipAddress);

      case DeviceType.androidTv:
        return AndroidTvDriver(device.ipAddress);

      case DeviceType.unknown:
        // الافتراضي: نجرب سامسونج WebSocket (مش مضمون)
        return SamsungTizenDriver(device.ipAddress);
    }
  }
}
