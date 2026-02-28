import '../base/tv_driver.dart';
import '../../domain/entities/tv_command.dart';
import '../../core/error/exceptions.dart';

class AndroidTvDriver implements TvDriver {
  final String ipAddress;

  AndroidTvDriver(this.ipAddress);

  @override
  DriverState get state => DriverState.error;

  @override
  Stream<DriverState> get stateStream => const Stream.empty();

  @override
  Future<void> connect() async {
    throw const ConnectionException(
      'Android TV يحتاج Pairing/Wireless Debugging (ADB) علشان التحكم يشتغل.'
    );
  }

  @override
  Future<void> sendCommand(TvCommand command) async {
    throw const DriverException('Android TV غير مدعوم حالياً بدون Pairing.');
  }

  @override
  Future<void> disconnect() async {}
}
