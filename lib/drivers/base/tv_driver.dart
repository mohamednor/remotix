// lib/drivers/base/tv_driver.dart

import '../../domain/entities/tv_command.dart';

enum DriverState { disconnected, connecting, connected, error }

abstract class TvDriver {
  DriverState get state;
  Stream<DriverState> get stateStream;

  Future<void> connect();
  Future<void> sendCommand(TvCommand command);
  Future<void> disconnect();

  bool get isConnected => state == DriverState.connected;
}
