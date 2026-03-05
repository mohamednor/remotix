// lib/drivers/base/driver_factory.dart
import 'dart:io';
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

    // ✅ تعرف من الاسم أو الـ manufacturer
    if (combined.contains('lg') || combined.contains('webos')) {
      return LgWebOsDriver(device.ipAddress);
    }
    if (combined.contains('samsung') || combined.contains('tizen')) {
      return SamsungTizenDriver(device.ipAddress);
    }
    if (combined.contains('android') || combined.contains('google')) {
      return AndroidTvDriver(device.ipAddress);
    }

    // ✅ Unknown → افترض LG لأن LG webOS على port 3000
    // وهو الأكثر شيوعاً في التلفزيونات الذكية
    // السامسونج على 8001 والـ SSDP بيتعرف عليه عادةً
    return LgWebOsDriver(device.ipAddress);
  }

  /// تحقق من نوع التلفزيون عن طريق الـ ports
  static Future<TvDriver> createWithDetection(Device device) async {
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
    if (combined.contains('android') || combined.contains('google')) {
      return AndroidTvDriver(device.ipAddress);
    }

    // ✅ Unknown → جرب تتعرف من الـ ports
    final type = await _detectByPort(device.ipAddress);
    switch (type) {
      case _TvType.lg:
        return LgWebOsDriver(device.ipAddress);
      case _TvType.samsung:
        return SamsungTizenDriver(device.ipAddress);
      case _TvType.android:
        return AndroidTvDriver(device.ipAddress);
      case _TvType.unknown:
        // افترض LG كـ fallback
        return LgWebOsDriver(device.ipAddress);
    }
  }

  static Future<_TvType> _detectByPort(String ip) async {
    // LG webOS → port 3000
    // Samsung Tizen → port 8001
    // Android TV → port 6466

    final results = await Future.wait([
      _canConnect(ip, 3000),   // LG
      _canConnect(ip, 8001),   // Samsung
      _canConnect(ip, 6466),   // Android TV
    ]);

    if (results[0]) return _TvType.lg;
    if (results[1]) return _TvType.samsung;
    if (results[2]) return _TvType.android;
    return _TvType.unknown;
  }

  static Future<bool> _canConnect(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port,
          timeout: const Duration(seconds: 2));
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }
}

enum _TvType { lg, samsung, android, unknown }
