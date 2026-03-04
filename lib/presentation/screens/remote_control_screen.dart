// lib/presentation/screens/remote_control_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/tv_command.dart';
import '../../drivers/base/tv_driver.dart';
import '../../core/utils/app_logger.dart';
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

  String? _errorMsg;

  // ✅ الإصلاح الرئيسي: sendCommand async مع catch حقيقي
  Future<void> _send(TvCommand cmd) async {
    final provider = context.read<DeviceProvider>();
    try {
      await provider.sendCommand(cmd);
      // لو نجح امسح الـ error القديم
      if (_errorMsg != null && mounted) {
        setState(() => _errorMsg = null);
      }
    } catch (e) {
      final msg = e.toString()
          .replaceAll('Exception:', '')
          .replaceAll('DriverException:', '')
          .trim();
      AppLogger.e('RemoteScreen: sendCommand error', e);
      if (mounted) {
        setState(() => _errorMsg = msg);
        // امسح الـ error بعد 4 ثواني
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _errorMsg = null);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeviceProvider>();
    final device = provider.selectedDevice;
    final driverState = provider.driverState;

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
          // زر reconnect لو في error
          if (driverState == DriverState.error ||
              driverState == DriverState.disconnected)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: _accent),
              tooltip: 'إعادة الاتصال',
              onPressed: () async {
                if (device != null) await provider.selectDevice(device);
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Error banner ──
            if (_errorMsg != null)
              Container(
                width: double.infinity,
                color: const Color(0xFFE53935).withOpacity(0.18),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Color(0xFFFF6584), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMsg!,
                        style: const TextStyle(
                            color: Color(0xFFFF6584), fontSize: 13),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _errorMsg = null),
                      child: const Icon(Icons.close,
                          color: Color(0xFF9090B0), size: 16),
                    ),
                  ],
                ),
              ),

            // ── Connecting banner ──
            if (driverState == DriverState.connecting)
              Container(
                width: double.infinity,
                color: _accent.withOpacity(0.12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _accent),
                    ),
                    SizedBox(width: 10),
                    Text('جاري الاتصال...',
                        style: TextStyle(color: _accent, fontSize: 12)),
                  ],
                ),
              ),

            // ── Main remote UI ──
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  children: [
                    _buildPowerButton(),
                    const SizedBox(height: 28),
                    _buildVolumeChannelRow(),
                    const SizedBox(height: 28),
                    DPadWidget(onCommand: _send),
                    const SizedBox(height: 28),
                    _buildBottomRow(),
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

  Widget _buildPowerButton() {
    return Center(
      child: RemoteButton(
        size: 68,
        color: const Color(0xFFE53935),
        onTap: () => _send(TvCommand.power),
        child: const Icon(
          Icons.power_settings_new_rounded,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildVolumeChannelRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildLabeledColumn(
          label: 'VOLUME',
          topIcon: Icons.volume_up_rounded,
          bottomIcon: Icons.volume_down_rounded,
          onTop: () => _send(TvCommand.volumeUp),
          onBottom: () => _send(TvCommand.volumeDown),
        ),
        Column(
          children: [
            const SizedBox(height: 12),
            RemoteButton(
              size: 56,
              onTap: () => _send(TvCommand.mute),
              child: const Icon(Icons.volume_off_rounded,
                  color: Colors.white70, size: 24),
            ),
            const SizedBox(height: 6),
            const Text('MUTE',
                style: TextStyle(
                    color: Color(0xFF9090B0),
                    fontSize: 10,
                    letterSpacing: 1)),
          ],
        ),
        _buildLabeledColumn(
          label: 'CHANNEL',
          topIcon: Icons.keyboard_arrow_up_rounded,
          bottomIcon: Icons.keyboard_arrow_down_rounded,
          onTop: () => _send(TvCommand.channelUp),
          onBottom: () => _send(TvCommand.channelDown),
        ),
      ],
    );
  }

  Widget _buildLabeledColumn({
    required String label,
    required IconData topIcon,
    required IconData bottomIcon,
    required VoidCallback onTop,
    required VoidCallback onBottom,
  }) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF9090B0), fontSize: 10, letterSpacing: 1)),
        const SizedBox(height: 8),
        RemoteButton(
            size: 52,
            onTap: onTop,
            child: Icon(topIcon, color: Colors.white70, size: 26)),
        const SizedBox(height: 8),
        RemoteButton(
            size: 52,
            onTap: onBottom,
            child: Icon(bottomIcon, color: Colors.white70, size: 26)),
      ],
    );
  }

  Widget _buildBottomRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildIconLabel(
          icon: Icons.arrow_back_rounded,
          label: 'BACK',
          onTap: () => _send(TvCommand.back),
        ),
        _buildIconLabel(
          icon: Icons.home_rounded,
          label: 'HOME',
          onTap: () => _send(TvCommand.home),
          color: _accent,
        ),
      ],
    );
  }

  Widget _buildIconLabel({
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
        Text(label,
            style: const TextStyle(
                color: Color(0xFF9090B0), fontSize: 10, letterSpacing: 1)),
      ],
    );
  }
}

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
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}
