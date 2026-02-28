import '../../domain/entities/device.dart';
import 'tv_driver.dart';
import '../lg/lg_webos_driver.dart';
import '../samsung/samsung_tizen_driver.dart';
import '../androidtv/android_tv_driver.dart';

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
        // خلي unknown يحاول LG أو Samsung؟ الأفضل: خليه Samsung مؤقتًا أو اعمل UI يطلب اختيار النوع
        return SamsungTizenDriver(device.ipAddress);
    }
  }
}
