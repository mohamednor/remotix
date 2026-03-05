// lib/presentation/screens/debug_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// شاشة debug — بتفتح WebSocket مباشرة وتعرض كل رسالة
/// استخدمها عشان تشوف إيه اللي التلفزيون بيبعته بالظبط
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final _ipController = TextEditingController(text: '192.168.1.');
  final _pinController = TextEditingController();
  final List<_LogEntry> _logs = [];
  WebSocket? _socket;
  bool _connected = false;
  bool _connecting = false;
  int _msgId = 0;

  static const _bg = Color(0xFF0D0D1A);
  static const _accent = Color(0xFF6C63FF);

  void _log(String text, {Color color = Colors.white70}) {
    setState(() {
      _logs.insert(0, _LogEntry(
        time: DateTime.now(),
        text: text,
        color: color,
      ));
      if (_logs.length > 100) _logs.removeLast();
    });
  }

  Future<void> _connect() async {
    if (_connecting) return;
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;

    setState(() => _connecting = true);
    _log('⏳ Connecting to ws://$ip:3000...', color: Colors.orange);

    try {
      final ws = await WebSocket.connect('ws://$ip:3000')
          .timeout(const Duration(seconds: 5));

      _socket = ws;
      setState(() { _connected = true; _connecting = false; });
      _log('✅ Socket open', color: Colors.greenAccent);

      ws.listen(
        (data) {
          _log('◀ RX: $data', color: const Color(0xFF43E97B));
          // حاول تعرض الـ JSON بشكل مقروء
          try {
            final j = jsonDecode(data as String);
            final pretty = const JsonEncoder.withIndent('  ').convert(j);
            _log('   $pretty', color: const Color(0xFF9090B0));
          } catch (_) {}
        },
        onError: (e) {
          _log('❌ Error: $e', color: Colors.redAccent);
          setState(() => _connected = false);
        },
        onDone: () {
          _log('🔌 Closed', color: Colors.orange);
          setState(() => _connected = false);
        },
      );

      // ابعت register فوراً
      _sendRegister();

    } catch (e) {
      _log('❌ Connect failed: $e', color: Colors.redAccent);
      setState(() { _connected = false; _connecting = false; });
    }
  }

  void _sendRegister() {
    final payload = {
      'id': 'reg_0',
      'type': 'register',
      'payload': {
        'forcePairing': false,
        'pairingType': 'PIN',
        'manifest': {
          'manifestVersion': 1,
          'appVersion': '1.1',
          'signed': {
            'created': '20260305',
            'appId': 'com.remotix.app',
            'vendorId': 'com.remotix',
            'localizedAppNames': {'': 'Remotix'},
            'localizedVendorNames': {'': 'Remotix'},
            'permissions': [
              'CONTROL_POWER',
              'CONTROL_INPUT_TEXT',
              'CONTROL_MOUSE_AND_KEYBOARD',
              'READ_RUNNING_APPS',
              'SEARCH',
            ],
          },
        },
      },
    };
    _tx(payload);
    _log('▶ TX: register (PIN)', color: const Color(0xFF6C63FF));
  }

  void _sendPin() {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) return;
    _tx({
      'id': 'pin_${++_msgId}',
      'type': 'request',
      'uri': 'ssap://pairing/setPin',
      'payload': {'pin': pin},
    });
    _log('▶ TX: setPin($pin)', color: const Color(0xFF6C63FF));
  }

  void _sendVolumeUp() {
    _tx({
      'id': 'cmd_${++_msgId}',
      'type': 'request',
      'uri': 'ssap://audio/volumeUp',
      'payload': {},
    });
    _log('▶ TX: volumeUp', color: const Color(0xFF6C63FF));
  }

  void _tx(Map<String, dynamic> payload) {
    final s = _socket;
    if (s == null || s.readyState != WebSocket.open) {
      _log('⚠️ TX skipped — not connected', color: Colors.orange);
      return;
    }
    final j = jsonEncode(payload);
    s.add(j);
  }

  Future<void> _disconnect() async {
    await _socket?.close();
    _socket = null;
    setState(() => _connected = false);
    _log('🔌 Disconnected', color: Colors.orange);
  }

  @override
  void dispose() {
    _socket?.close();
    _ipController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('WebSocket Debug',
            style: TextStyle(color: Colors.white, fontSize: 15)),
        actions: [
          if (_connected)
            IconButton(
              icon: const Icon(Icons.link_off, color: Colors.redAccent),
              onPressed: _disconnect,
            ),
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white54, size: 18),
            tooltip: 'Copy logs',
            onPressed: () {
              final text = _logs.map((e) => '${e.timeStr} ${e.text}').join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── IP + Connect ──
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'TV IP',
                      labelStyle: const TextStyle(color: Color(0xFF9090B0)),
                      filled: true,
                      fillColor: const Color(0xFF1E1E2E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _connected ? _disconnect : (_connecting ? null : _connect),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _connected ? Colors.redAccent : _accent,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  child: _connecting
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_connected ? 'Disconnect' : 'Connect',
                          style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),

          // ── PIN ──
          if (_connected)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pinController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'PIN from TV',
                        labelStyle: const TextStyle(color: Color(0xFF9090B0)),
                        filled: true,
                        fillColor: const Color(0xFF1E1E2E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _sendPin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB347),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    child: const Text('Send PIN',
                        style: TextStyle(color: Colors.black)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _sendVolumeUp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF43E97B),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    child: const Text('Vol+',
                        style: TextStyle(color: Colors.black)),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),
          const Divider(color: Color(0xFF2A2A3E), height: 1),

          // ── Logs ──
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text('Connect to TV to see messages',
                        style: TextStyle(color: Color(0xFF9090B0))))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _logs.length,
                    itemBuilder: (_, i) {
                      final e = _logs[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '${e.timeStr} ',
                                style: const TextStyle(
                                    color: Color(0xFF555570), fontSize: 10),
                              ),
                              TextSpan(
                                text: e.text,
                                style: TextStyle(
                                    color: e.color, fontSize: 11,
                                    fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LogEntry {
  final DateTime time;
  final String text;
  final Color color;

  _LogEntry({required this.time, required this.text, required this.color});

  String get timeStr =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}';
}
