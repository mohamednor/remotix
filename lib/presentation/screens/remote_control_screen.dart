// lib/presentation/screens/remote_control_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/tv_command.dart';
import '../../drivers/base/tv_driver.dart';
import '../providers/device_provider.dart';
import '../widgets/remote_button.dart';
import '../widgets/dpad_widget.dart';
import '../widgets/ad_banner_widget.dart';

class RemoteControlScreen extends StatelessWidget {
  const RemoteControlScreen({super.key});

  static const _accent = Color(0xFF6C63FF);
  static const _bg = Color(0xFF12121F);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeviceProvider>();
    final device = provider.selectedDevice;

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
            _ConnectionStatus(state: provider.driverState),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  children: [
                    // Power (الزرار الأحمر فقط)
                    _buildPowerButton(provider),
                    const SizedBox(height: 28),

                    // Volume + Channel
                    _buildVolumeChannelRow(provider),
                    const SizedBox(height: 28),

                    // D-Pad
                    DPadWidget(onCommand: (cmd) => provider.sendCommand(cmd)),
                    const SizedBox(height: 28),

                    // Home / Back row (بدون تكرار MUTE)
                    _buildBottomRow(provider),
                    const SizedBox(height: 24),

                    // Signature
                    const Text(
                      'by: Mohamed Elshref',
                      style: TextStyle(
                        color: Color(0xFF9090B0),
                        fontSize: 10,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // AdMob banner
            const AdBannerWidget(),
          ],
        ),
      ),
    );
  }

  Widget _buildPowerButton(DeviceProvider provider) {
    return Center(
      child: RemoteButton(
        size: 68,
        color: const Color(0xFFE53935),
        onTap: () => provider.sendCommand(TvCommand.power),
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
          onTop: () => provider.sendCommand(TvCommand.volumeUp),
          onBottom: () => provider.sendCommand(TvCommand.volumeDown),
        ),
        Column(
          children: [
            const SizedBox(height: 12),
            RemoteButton(
              size: 56,
              onTap: () => provider.sendCommand(TvCommand.mute),
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
          onTop: () => provider.sendCommand(TvCommand.channelUp),
          onBottom: () => provider.sendCommand(TvCommand.channelDown),
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
          onTap: () => provider.sendCommand(TvCommand.back),
        ),
        _buildIconLabelButton(
          icon: Icons.home_rounded,
          label: 'HOME',
          onTap: () => provider.sendCommand(TvCommand.home),
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

class _ConnectionStatus extends StatelessWidget {
  final DriverState state;

  const _ConnectionStatus({required this.state});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    switch (state) {
      case DriverState.connected:
        color = const Color(0xFF43E97B);
        label = 'Connected';
        break;
      case DriverState.connecting:
        color = const Color(0xFFFFB347);
        label = 'Connecting…';
        break;
      case DriverState.error:
        color = const Color(0xFFFF6584);
        label = 'Error';
        break;
      case DriverState.disconnected:
        color = const Color(0xFF9090B0);
        label = 'Disconnected';
        break;
    }

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
