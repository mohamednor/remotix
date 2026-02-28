// lib/core/error/exceptions.dart

class NetworkException implements Exception {
  final String message;
  const NetworkException(this.message);
  @override
  String toString() => 'NetworkException: $message';
}

class ConnectionException implements Exception {
  final String message;
  const ConnectionException(this.message);
  @override
  String toString() => 'ConnectionException: $message';
}

class DriverException implements Exception {
  final String message;
  const DriverException(this.message);
  @override
  String toString() => 'DriverException: $message';
}
