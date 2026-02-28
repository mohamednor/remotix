import 'package:shared_preferences/shared_preferences.dart';

class TvStorage {
  static String _macKey(String ip) => 'tv_mac_$ip';

  static Future<void> saveMac(String ip, String mac) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_macKey(ip), mac.trim());
  }

  static Future<String?> loadMac(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_macKey(ip));
    if (v == null) return null;
    final s = v.trim();
    return s.isEmpty ? null : s;
  }
}