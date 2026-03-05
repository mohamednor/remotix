// lib/presentation/screens/device_list_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/device_model.dart';
import '../../domain/entities/device.dart';
import '../../drivers/lg/lg_webos_driver.dart';
import '../providers/device_provider.dart';
import 'pin_entry_screen.dart';

class DeviceListScreen extends StatelessWidget {
  const DeviceListScreen({super.key});

  IconData _iconForType(DeviceType type) {
    switch (type) {
      case DeviceType.lgWebOs:      return Icons.tv_rounded;
      case DeviceType.samsungTizen: return Icons.smart_display_rounded;
      case DeviceType.androidTv:    return Icons.cast_rounded;
      case DeviceType.unknown:      return Icons.devices_other_rounded;
    }
  }

  Color _colorForType(DeviceType type) {
    switch (type) {
      case DeviceType.lgWebOs:      return const Color(0xFFFF6584);
      case DeviceType.samsungTizen: return const Color(0xFF43E97B);
      case DeviceType.androidTv:    return const Color(0xFF38F9D7);
      case DeviceType.unknown:      return const Color(0xFF9090B0);
    }
  }

  Future<void> _onDeviceTap(BuildContext context, Device device) async {
    final provider = context.read<DeviceProvider>();

    // ابدأ الاتصال
    await provider.selectDevice(device);
    if (!context.mounted) return;

    // ✅ لو محتاج PIN → افتح شاشة PIN الأول
    if (provider.showPinScreen) {
      final driver = provider.currentDriver;
      if (driver is LgWebOsDriver) {
        final confirmed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => PinEntryScreen(driver: driver),
            fullscreenDialog: true,
          ),
        );

        if (!context.mounted) return;

        // لو ألغى → ارجع
        if (confirmed != true) {
          await provider.disconnect();
          return;
        }
      }
    }

    if (!context.mounted) return;
    Navigator.of(context).pushNamed('/remote');
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeviceProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF12121F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: const Text(
          'Select Device',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 18),
        ),
        actions: [
          // ✅ زر debug مؤقت — لمعرفة إيه اللي التلفزيون بيبعته
          IconButton(
            icon: const Icon(Icons.bug_report_rounded, color: Colors.orange),
            tooltip: 'Debug WS',
            onPressed: () => Navigator.of(context).pushNamed('/debug'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF6C63FF)),
            onPressed: () {
              provider.scanDevices().then((_) {
                if (!context.mounted) return;
                if (provider.devices.isEmpty) {
                  Navigator.of(context).pushReplacementNamed('/scan');
                }
              });
            },
          ),
        ],
      ),
      body: provider.devices.isEmpty
          ? _buildEmpty(context)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    '${provider.devices.length} device(s) found on your network',
                    style: const TextStyle(
                        color: Color(0xFF9090B0), fontSize: 13),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: provider.devices.length,
                    itemBuilder: (ctx, i) =>
                        _buildCard(ctx, provider.devices[i]),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.tv_off_rounded,
              color: Color(0xFF3D3D5C), size: 80),
          const SizedBox(height: 20),
          const Text('No TVs Found',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'Make sure your TV is on\nand on the same WiFi network',
            style: TextStyle(color: Color(0xFF9090B0), fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () =>
                Navigator.of(context).pushReplacementNamed('/scan'),
            icon: const Icon(Icons.search),
            label: const Text('Scan Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, Device device) {
    final color = _colorForType(device.type);

    return GestureDetector(
      onTap: () => _onDeviceTap(context, device),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0xFF0D0D1A),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(_iconForType(device.type),
                  color: color, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.displayName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${device.typeLabel}  •  ${device.ipAddress}',
                    style: const TextStyle(
                        color: Color(0xFF9090B0), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF6C63FF)),
          ],
        ),
      ),
    );
  }
}
