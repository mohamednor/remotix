import '../../domain/entities/device.dart';
import 'tv_driver.dart';
import '../androidtv/android_tv_driver.dart';
import '../lg/lg_webos_driver.dart';
import '../samsung/samsung_tizen_driver.dart';

class DriverFactory {
  static TvDriver create(Device device) {
    switch (device.type) {
      case DeviceType.lgWebOs:
        return LgWebOsDriver(device.ipAddress);
      case DeviceType.samsungTizen:
        return SamsungTizenDriver(device.ipAddress);
      case DeviceType.androidTv:
        return AndroidTvDriver(device.ipAddress);
      case DeviceType.unknown:
      default:
        // fallback عشان التطبيق ما يقعش لو الاكتشاف رجّع Unknown
        final s =
            '${device.manufacturer} ${device.model} ${device.name}'.toLowerCase();

        if (s.contains('lg') || s.contains('webos')) {
          return LgWebOsDriver(device.ipAddress);
        }
        if (s.contains('samsung') || s.contains('tizen')) {
          return SamsungTizenDriver(device.ipAddress);
        }
        if (s.contains('android')) {
          return AndroidTvDriver(device.ipAddress);
        }

        throw Exception(
          'Unsupported TV type: ${device.typeLabel} (${device.ipAddress})',
        );
    }
  }
}
