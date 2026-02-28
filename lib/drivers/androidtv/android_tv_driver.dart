import 'dart:async';
import '../base/tv_driver.dart';
import '../../domain/entities/tv_command.dart';
import '../../core/error/exceptions.dart';

class AndroidTvDriver implements TvDriver {
  final String ipAddress;

  final StreamController<DriverState> _stateController =
      StreamController<DriverState>.broadcast();

  DriverState _state = DriverState.disconnected;

  AndroidTvDriver(this.ipAddress);

  @override
  DriverState get state => _state;

  @override
  Stream<DriverState> get stateStream => _stateController.stream;

  void _setState(DriverState s) {
    _state = s;
    _stateController.add(s);
  }

  @override
  Future<void> connect() async {
    // Placeholder: Android TV محتاج ADB pairing/auth
    _setState(DriverState.error);
    throw const ConnectionException(
      'Android TV control requires ADB pairing/auth (not implemented yet).',
    );
  }

  @override
  Future<void> sendCommand(TvCommand command) async {
    throw const DriverException('Android TV driver not available yet.');
  }

  @override
  Future<void> disconnect() async {
    _setState(DriverState.disconnected);
  }
}
