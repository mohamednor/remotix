// lib/presentation/screens/pin_entry_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../drivers/lg/lg_webos_driver.dart';

class PinEntryScreen extends StatefulWidget {
  final LgWebOsDriver driver;

  const PinEntryScreen({super.key, required this.driver});

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  static const _bg = Color(0xFF12121F);
  static const _accent = Color(0xFF6C63FF);

  Future<void> _submit() async {
    final pin = _controller.text.trim();
    if (pin.isEmpty) {
      setState(() => _error = 'أدخل الـ PIN الظاهر على التلفزيون');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      await widget.driver.submitPin(pin);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'PIN خاطئ، حاول مرة أخرى';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: const Text(
          'إدخال PIN',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // أيقونة
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.tv_rounded,
                color: _accent,
                size: 44,
              ),
            ),

            const SizedBox(height: 32),

            const Text(
              'أدخل رمز PIN',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              'ظهر رمز على شاشة التلفزيون\nأدخله هنا للاقتران',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9090B0),
                fontSize: 14,
                height: 1.6,
              ),
            ),

            const SizedBox(height: 40),

            // حقل الـ PIN
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 8,
              textAlign: TextAlign.center,
              autofocus: true,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '00000000',
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.15),
                  fontSize: 32,
                  letterSpacing: 8,
                ),
                filled: true,
                fillColor: const Color(0xFF1E1E2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _accent, width: 2),
                ),
                errorText: _error,
                errorStyle: const TextStyle(color: Color(0xFFFF6584)),
              ),
              onSubmitted: (_) => _submit(),
            ),

            const SizedBox(height: 32),

            // زر التأكيد
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  disabledBackgroundColor: _accent.withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'تأكيد',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
