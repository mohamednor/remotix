// lib/presentation/screens/remote_control_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/tv_command.dart';
import '../../drivers/base/tv_driver.dart';
import '../providers/device_provider.dart';
import '../widgets/remote_button.dart';
import '../widgets/dpad_widget.dart';
import '../widgets/ad_banner_widget.dart';
import '../../core/network/wol.dart';

class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({super.key});

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  static const _accent = Color(0xFF6C63FF);
  static const _bg = Color(0xFF12121F);

  final TextEditingController _macController = TextEditingController();
  bool _macInitialized = false;

  @override
  void dispose() {
    _macController.dispose();
    super.dispose();
  }

  void _initMacOnce(DeviceProvider provider) {
    if (_macInitialized) return;
    _macController.text = provider.macAddress ?? '';
    _macInitialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeviceProvider>();
    final device = provider.selectedDevice;

    _initMacOnce(provider);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white70, size: 18),
          onPressed: () {
            provider.disconnect();
            Navigator.of(context).pop();
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
                  fontWeight: FontWeight.w600),
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
                    // Power
                    _buildPowerButton(provider),
                    const SizedBox(height: 14),

                    // ✅ MAC (Wake-on-LAN) box
                    _buildMacBox(context, provider),

                    const SizedBox(height: 22),
                    // Volume + Channel side by side
                    _buildVolumeChannelRow(provider),
                    const SizedBox(height: 28),
                    // D-Pad
                    DPadWidget(onCommand: (cmd) => provider.sendCommand(cmd)),
                    const SizedBox(height: 28),
                    // Home / Back / Mute row
                    _buildBottomRow(provider),
                    const SizedBox(height: 16),

                    // Error message (if any)
                    if (provider.errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          provider.errorMessage!,
                          style: const TextStyle(
                            color: Color(0xFFFF6584),
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // AdMob banner at the very bottom
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
        child: const Icon(Icons.power_settings_new_rounded,
            color: Colors.white, size: 32),
      ),
    );
  }

  Widget _buildMacBox(BuildContext context, DeviceProvider provider) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Power ON (Wake-on-LAN)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Enter TV MAC once (example: AA:BB:CC:DD:EE:FF). Needed to turn ON when TV is OFF.',
            style: TextStyle(
              color: Color(0xFF9090B0),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _macController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'AA:BB:CC:DD:EE:FF',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF12121F),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final mac = _macController.text.trim();
                    await provider.setMacAddress(mac);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('MAC saved')),
                      );
                    }
                  },
                  child: const Text('Save MAC'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final mac = _macController.text.trim();
                    if (mac.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Enter MAC first')),
                      );
                      return;
                    }
                    try {
                      await WakeOnLan.wake(macAddress: mac);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Wake packet sent')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('WOL failed: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('Test Wake'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if ((provider.macAddress ?? '').isEmpty)
            const Text(
              'MAC not saved yet. Power ON won’t work when TV is OFF.',
              style: TextStyle(color: Color(0xFFFFB347), fontSize: 11),
            ),
        ],
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
              color: Color(0xFF9090B0), fontSize: 10, letterSpacing: 1),
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
        _buildIconLabelButton(
          icon: Icons.mic_off_rounded,
          label: 'MUTE',
          onTap: () => provider.sendCommand(TvCommand.mute),
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
              color: Color(0xFF9090B0), fontSize: 10, letterSpacing: 1),
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