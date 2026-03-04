// lib/presentation/screens/remote_control_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/tv_command.dart';
import '../../drivers/base/tv_driver.dart';
import '../../drivers/lg/lg_webos_driver.dart';
import '../../drivers/samsung/samsung_tizen_driver.dart';
import '../providers/device_provider.dart';
import '../widgets/remote_button.dart';
import '../widgets/dpad_widget.dart';
import '../widgets/ad_banner_widget.dart';

class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({super.key});

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  static const _accent = Color(0xFF6C63FF);
  static const _bg = Color(0xFF12121F);

  String? _lastError;
  bool _showPairingBanner = false;

  @override
  void initState() {
    super.initState();
    // ✅ بعد أول frame اتحرك نستنى مشكلة من الـ driver
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPairingStatus();
    });
  }

  void _checkPairingStatus() {
    final driver = context.read<DeviceProvider>().currentDriver;
    if (driver is LgWebOsDriver && driver.waitingForUserApproval) {
      _showPairingDialog(isLg: true);
    } else if (driver is SamsungTizenDriver && driver.waitingForApproval) {
      _showPairingDialog(isLg: false);
    }
  }

  void _showPairingDialog({required bool isLg}) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.tv_rounded,
              color: isLg ? const Color(0xFFFF6584) : const Color(0xFF43E97B),
            ),
            const SizedBox(width: 10),
            Text(
              isLg ? 'اقتران LG webOS' : 'اقتران Samsung',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.phonelink_rounded,
              color: Color(0xFF6C63FF),
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              isLg
                  ? 'ظهر على شاشة التلفزيون طلب اقتران.\n\nاضغط "Allow" أو "السماح" على التلفزيون باستخدام الريموت الأصلي.'
                  : 'ظهر على شاشة التلفزيون رسالة لقبول الاتصال.\n\nاضغط "Accept" أو "قبول" على التلفزيون.',
              style: const TextStyle(
                color: Color(0xFFCCCCDD),
                fontSize: 14,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // ✅ بنر إضافي لو LG
            if (isLg)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF12121F),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF3D3D5C)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: Color(0xFFFFB347), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'في المرات الجاية هيتصل أوتوماتيك بدون موافقة',
                        style: TextStyle(
                          color: Color(0xFF9090B0),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'تم القبول ✓',
              style: TextStyle(
                color: Color(0xFF43E97B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // ارجع للقائمة
            },
            child: const Text(
              'إلغاء',
              style: TextStyle(color: Color(0xFF9090B0)),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ إظهار error لحظي لما زر يتضغط وما يرسلش
  Future<void> _sendCommand(DeviceProvider provider, TvCommand cmd) async {
    try {
      await provider.sendCommand(cmd);
      if (_lastError != null) setState(() => _lastError = null);
    } catch (e) {
      final msg = e.toString().replaceAll('Exception:', '').trim();
      setState(() => _lastError = msg);

      // ✅ لو التليفزيون بيطلب pairing وإحنا ضغطنا زر
      final driver = provider.currentDriver;
      if (driver is LgWebOsDriver && driver.waitingForUserApproval) {
        _showPairingDialog(isLg: true);
      } else if (driver is SamsungTizenDriver && driver.waitingForApproval) {
        _showPairingDialog(isLg: false);
      }

      // امسح الـ error بعد 3 ثواني
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _lastError = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeviceProvider>();
    final device = provider.selectedDevice;

    // ✅ راقب تغيير state الـ driver عشان نعرض banner الـ pairing
    final driverState = provider.driverState;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkPairingStatus();
    });

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white70, size: 18),
          onPressed: () async {
            await provider.disconnect();
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device?.displayName ?? 'Remote',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            _ConnectionStatus(state: driverState),
          ],
        ),
        actions: [
          // ✅ زر Reconnect لو في error
          if (driverState == DriverState.error ||
              driverState == DriverState.disconnected)
            IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  color: Color(0xFF6C63FF)),
              tooltip: 'إعادة الاتصال',
              onPressed: () async {
                if (device != null) {
                  await provider.selectDevice(device);
                  if (mounted) _checkPairingStatus();
                }
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ✅ Error banner
            if (_lastError != null) _buildErrorBanner(_lastError!),

            // ✅ Pairing waiting banner
            if (provider.waitingForPairing)
              _buildPairingWaitingBanner(provider),

            // ✅ Connecting overlay
            if (driverState == DriverState.connecting)
              _buildConnectingBanner(),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 16),
                child: Column(
                  children: [
                    _buildPowerButton(provider),
                    const SizedBox(height: 28),
                    _buildVolumeChannelRow(provider),
                    const SizedBox(height: 28),
                    DPadWidget(
                      onCommand: (cmd) => _sendCommand(provider, cmd),
                    ),
                    const SizedBox(height: 28),
                    _buildBottomRow(provider),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            const AdBannerWidget(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────── Banners ──────────────────────────────

  Widget _buildErrorBanner(String error) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: const Color(0xFFE53935).withOpacity(0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFFF6584), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(
                  color: Color(0xFFFF6584), fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _lastError = null),
            child: const Icon(Icons.close, color: Color(0xFF9090B0), size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildPairingWaitingBanner(DeviceProvider provider) {
    return Container(
      color: const Color(0xFFFFB347).withOpacity(0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFFFFB347)),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'انتظر الموافقة على التلفزيون...',
              style: TextStyle(color: Color(0xFFFFB347), fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap: _checkPairingStatus,
            child: const Icon(Icons.info_outline_rounded,
                color: Color(0xFFFFB347), size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectingBanner() {
    return Container(
      color: const Color(0xFF6C63FF).withOpacity(0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFF6C63FF)),
          ),
          SizedBox(width: 10),
          Text(
            'جاري الاتصال...',
            style: TextStyle(color: Color(0xFF6C63FF), fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── Buttons ──────────────────────────────

  Widget _buildPowerButton(DeviceProvider provider) {
    return Center(
      child: RemoteButton(
        size: 68,
        color: const Color(0xFFE53935),
        onTap: () => _sendCommand(provider, TvCommand.power),
        child: const Icon(
          Icons.power_settings_new_rounded,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildVolumeChannelRow(DeviceProvider provider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildLabeledControl(
          label: 'VOLUME',
          topIcon: Icons.volume_up_rounded,
          bottomIcon: Icons.volume_down_rounded,
          onTop: () => _sendCommand(provider, TvCommand.volumeUp),
          onBottom: () => _sendCommand(provider, TvCommand.volumeDown),
        ),
        Column(
          children: [
            const SizedBox(height: 12),
            RemoteButton(
              size: 56,
              onTap: () => _sendCommand(provider, TvCommand.mute),
              child: const Icon(
                Icons.volume_off_rounded,
                color: Colors.white70,
                size: 24,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'MUTE',
              style: TextStyle(
                color: Color(0xFF9090B0),
                fontSize: 10,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        _buildLabeledControl(
          label: 'CHANNEL',
          topIcon: Icons.keyboard_arrow_up_rounded,
          bottomIcon: Icons.keyboard_arrow_down_rounded,
          onTop: () => _sendCommand(provider, TvCommand.channelUp),
          onBottom: () => _sendCommand(provider, TvCommand.channelDown),
        ),
      ],
    );
  }

  Widget _buildLabeledControl({
    required String label,
    required IconData topIcon,
    required IconData bottomIcon,
    required VoidCallback onTop,
    required VoidCallback onBottom,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF9090B0),
            fontSize: 10,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        RemoteButton(
          size: 52,
          onTap: onTop,
          child: Icon(topIcon, color: Colors.white70, size: 26),
        ),
        const SizedBox(height: 8),
        RemoteButton(
          size: 52,
          onTap: onBottom,
          child: Icon(bottomIcon, color: Colors.white70, size: 26),
        ),
      ],
    );
  }

  Widget _buildBottomRow(DeviceProvider provider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildIconLabelButton(
          icon: Icons.arrow_back_rounded,
          label: 'BACK',
          onTap: () => _sendCommand(provider, TvCommand.back),
        ),
        _buildIconLabelButton(
          icon: Icons.home_rounded,
          label: 'HOME',
          onTap: () => _sendCommand(provider, TvCommand.home),
          color: _accent,
        ),
      ],
    );
  }

  Widget _buildIconLabelButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Column(
      children: [
        RemoteButton(
          size: 56,
          color: color,
          onTap: onTap,
          child: Icon(icon, color: Colors.white70, size: 24),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF9090B0),
            fontSize: 10,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────── Connection Status Widget ──────────────────────

class _ConnectionStatus extends StatelessWidget {
  final DriverState state;
  const _ConnectionStatus({required this.state});

  @override
  Widget build(BuildContext context) {
    final (Color color, String label) = switch (state) {
      DriverState.connected => (const Color(0xFF43E97B), 'Connected'),
      DriverState.connecting => (const Color(0xFFFFB347), 'Connecting…'),
      DriverState.error => (const Color(0xFFFF6584), 'Error'),
      DriverState.disconnected => (const Color(0xFF9090B0), 'Disconnected'),
    };

    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}
