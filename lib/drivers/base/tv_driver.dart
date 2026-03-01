// lib/drivers/base/tv_driver.dart

import '../../domain/entities/tv_command.dart';

enum DriverState {
  disconnected,
  connecting,
  connected,
  error,
}

abstract class TvDriver {
  /// الحالة الحالية للاتصال
  DriverState get state;

  /// ستريم لمتابعة تغيرات الحالة (UI تعتمد عليه)
  Stream<DriverState> get stateStream;

  /// بدء الاتصال
  Future<void> connect();

  /// إرسال أمر للـ TV
  Future<void> sendCommand(TvCommand command);

  /// قطع الاتصال
  Future<void> disconnect();

  /// اختياري: لو حبيت تعمل cleanup من بره
  Future<void> dispose() async {
    await disconnect();
  }

  /// Helper موحد لكل الدرايفرز
  bool get isConnected => state == DriverState.connected;
}
