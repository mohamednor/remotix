// lib/core/constants/app_constants.dart

class AppConstants {
  // SSDP
  static const String ssdpMulticastAddress = '239.255.255.250';
  static const int ssdpPort = 1900;
  static const Duration ssdpTimeout = Duration(seconds: 5);
  static const String ssdpMSearchMessage =
      'M-SEARCH * HTTP/1.1\r\n'
      'HOST: 239.255.255.250:1900\r\n'
      'MAN: "ssdp:discover"\r\n'
      'MX: 3\r\n'
      'ST: ssdp:all\r\n'
      '\r\n';

  // Driver ports
  static const int lgWebOsPort = 3000;
  static const int samsungTizenPort = 8001;
  static const int androidTvPort = 6466;

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration commandTimeout = Duration(seconds: 5);
  static const Duration reconnectDelay = Duration(seconds: 3);
  static const int maxReconnectAttempts = 3;

  // AdMob
  static const String admobAppId = 'ca-app-pub-4380269071153281~1338541200';
  static const String bannerAdUnitId = 'ca-app-pub-4380269071153281/2984104871';
}
