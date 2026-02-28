import 'dart:io';
import 'dart:typed_data';

class WakeOnLan {
  static Future<void> wake({
    required String macAddress,
    String broadcastAddress = '255.255.255.255',
    int port = 9,
  }) async {
    final mac = _parseMac(macAddress);
    final packet = Uint8List(6 + 16 * 6);

    for (int i = 0; i < 6; i++) {
      packet[i] = 0xFF;
    }

    for (int i = 6; i < packet.length; i += 6) {
      packet.setRange(i, i + 6, mac);
    }

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      socket.broadcastEnabled = true;
      socket.send(packet, InternetAddress(broadcastAddress), port);
    } finally {
      socket.close();
    }
  }

  static List<int> _parseMac(String mac) {
    final cleaned =
        mac.trim().replaceAll('-', ':').replaceAll(' ', '').toLowerCase();
    final parts = cleaned.split(':');
    if (parts.length != 6) {
      throw FormatException('Invalid MAC address: $mac');
    }
    return parts.map((p) => int.parse(p, radix: 16)).toList();
  }
}