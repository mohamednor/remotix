// lib/core/network/ssdp_discovery.dart

import 'dart:async';
import 'dart:io';
import '../constants/app_constants.dart';
import '../utils/app_logger.dart';
import '../../data/models/device_model.dart';

class SsdpDiscovery {
  RawDatagramSocket? _socket;
  final StreamController<DeviceModel> _deviceController =
      StreamController<DeviceModel>.broadcast();

  Stream<DeviceModel> get deviceStream => _deviceController.stream;

  Future<List<DeviceModel>> discover() async {
    final devices = <String, DeviceModel>{};
    final completer = Completer<List<DeviceModel>>();

    try {
      // Close any previous socket
      _socket?.close();

      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
        reusePort: false,
      );

      _socket!.multicastHops = 4;
      _socket!.broadcastEnabled = true;

      AppLogger.i('SSDP: Socket bound on port ${_socket!.port}');

      final data = AppConstants.ssdpMSearchMessage.codeUnits;
      final target = InternetAddress(AppConstants.ssdpMulticastAddress);

      final sent = _socket!.send(data, target, AppConstants.ssdpPort);
      AppLogger.i('SSDP: M-SEARCH sent ($sent bytes) to '
          '${AppConstants.ssdpMulticastAddress}:${AppConstants.ssdpPort}');

      _socket!.listen(
        (RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            final datagram = _socket?.receive();
            if (datagram != null) {
              final response = String.fromCharCodes(datagram.data);
              AppLogger.d(
                  'SSDP: Response from ${datagram.address.address}');
              final device =
                  _parseResponse(response, datagram.address.address);
              if (device != null &&
                  !devices.containsKey(device.ipAddress)) {
                devices[device.ipAddress] = device;
                if (!_deviceController.isClosed) {
                  _deviceController.add(device);
                }
                AppLogger.i(
                    'SSDP: Found device ${device.name} '
                    '(${device.type}) @ ${device.ipAddress}');
              }
            }
          }
        },
        onError: (Object e) {
          AppLogger.e('SSDP socket error', e);
          if (!completer.isCompleted) {
            completer.complete(devices.values.toList());
          }
        },
        cancelOnError: true,
      );

      Timer(AppConstants.ssdpTimeout, () {
        _socket?.close();
        if (!completer.isCompleted) {
          AppLogger.i(
              'SSDP: Scan timeout - found ${devices.length} device(s)');
          completer.complete(devices.values.toList());
        }
      });
    } catch (e, st) {
      AppLogger.e('SSDP discover error', e, st);
      if (!completer.isCompleted) {
        completer.complete(<DeviceModel>[]);
      }
    }

    return completer.future;
  }

  DeviceModel? _parseResponse(String response, String ipAddress) {
    try {
      final lines = response.split('\r\n');
      String manufacturer = 'Unknown';
      String model = 'Unknown';
      String name = 'Smart TV';
      DeviceType type = DeviceType.unknown;

      for (final line in lines) {
        final lower = line.toLowerCase();

        // Detect LG webOS
        if (lower.contains('lg') || lower.contains('webos')) {
          manufacturer = 'LG';
          type = DeviceType.lgWebOs;
          name = 'LG Smart TV';
        }

        // Detect Samsung Tizen
        if (lower.contains('samsung') || lower.contains('tizen')) {
          manufacturer = 'Samsung';
          type = DeviceType.samsungTizen;
          name = 'Samsung Smart TV';
        }

        // Detect Android TV / Google TV
        if (lower.contains('android') ||
            lower.contains('googletv') ||
            lower.contains('google tv')) {
          manufacturer = 'Google';
          type = DeviceType.androidTv;
          name = 'Android TV';
        }

        // Extract model from Server header
        if (lower.startsWith('server:') ||
            lower.startsWith('x-user-agent:')) {
          final colonIdx = line.indexOf(':');
          if (colonIdx != -1 && colonIdx < line.length - 1) {
            model = line.substring(colonIdx + 1).trim();
          }
        }
      }

      return DeviceModel(
        name: name,
        ipAddress: ipAddress,
        manufacturer: manufacturer,
        model: model,
        type: type,
      );
    } catch (e) {
      AppLogger.e('SSDP: Failed to parse response from $ipAddress', e);
      return null;
    }
  }

  void dispose() {
    _socket?.close();
    _socket = null;
    if (!_deviceController.isClosed) {
      _deviceController.close();
    }
  }
}
