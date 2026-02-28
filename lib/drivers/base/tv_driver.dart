import '../../domain/entities/tv_command.dart';

enum DriverState { disconnected, connecting, connected, error }

abstract class TvDriver {
  DriverState get state;
  Stream<DriverState> get stateStream;

  Future<void> connect();
  Future<void> sendCommand(TvCommand command);
  Future<void> disconnect();

  // IMPORTANT: some of your build errors indicate isConnected is expected.
  bool get isConnected => state == DriverState.connected;
}
