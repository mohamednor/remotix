// lib/presentation/screens/device_scan_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';

class DeviceScanScreen extends StatefulWidget {
  const DeviceScanScreen({super.key});

  @override
  State<DeviceScanScreen> createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends State<DeviceScanScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _startScan() {
    context.read<DeviceProvider>().scanDevices().then((_) {
      if (!mounted) return;
      final provider = context.read<DeviceProvider>();
      if (provider.devices.isNotEmpty) {
        Navigator.of(context).pushReplacementNamed('/devices');
      }
    });
  }


  const SizedBox(height: 24),
const Text(
  'by: Mohamed Elshref',
  style: TextStyle(
    color: Color(0xFF9090B0),
    fontSize: 10, // صغير جدًا
  ),
), 

  
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeviceProvider>();
    final scanning = provider.scanState == ScanState.scanning;

    return Scaffold(
      backgroundColor: const Color(0xFF12121F),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    width: 140 + (_pulseController.value * 20),
                    height: 140 + (_pulseController.value * 20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF6C63FF)
                            .withOpacity(0.3 + _pulseController.value * 0.3),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF).withOpacity(0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF6C63FF),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.wifi_find_rounded,
                          color: Color(0xFF6C63FF),
                          size: 48,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),
              Text(
                scanning ? 'Scanning Network...' : 'Scan Complete',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                scanning
                    ? 'Looking for Smart TVs on your network'
                    : '${provider.devices.length} device(s) found',
                style: const TextStyle(
                  color: Color(0xFF9090B0),
                  fontSize: 14,
                ),
              ),
              if (scanning) ...[
                const SizedBox(height: 32),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF6C63FF),
                  ),
                ),
              ],
              if (provider.scanState == ScanState.done &&
                  provider.devices.isEmpty) ...[
                const SizedBox(height: 40),
                _buildRetryButton(context),
              ],
              if (provider.scanState == ScanState.error) ...[
                const SizedBox(height: 16),
                Text(
                  provider.errorMessage ?? 'Unknown error',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                _buildRetryButton(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRetryButton(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _startScan,
      icon: const Icon(Icons.refresh),
      label: const Text('Scan Again'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
