import 'dart:async';

import 'package:universal_ble/universal_ble.dart';

import 'eeg_source.dart';
import 'muse_protocol.dart';

/// Moose, the real one: a Muse headband over Bluetooth Low Energy.
class MuseSource implements EegSource {
  MuseSource(this.deviceId, {String? deviceName}) : name = deviceName ?? 'Muse';

  final String deviceId;

  @override
  final String name;

  @override
  List<String> get channels => museEegCharacteristics.keys.toList();

  @override
  double get sampleRate => museSampleRate;

  @override
  int get droppedPackets => _assembler.dropped;

  @override
  int get duplicatePackets => _assembler.duplicates;

  final _chunks = StreamController<EegChunk>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _assembler = MusePacketAssembler(museEegCharacteristics.length);

  @override
  Stream<EegChunk> get chunks => _chunks.stream;

  /// Finds headbands nearby. Muse devices advertise a name starting with "Muse".
  static Stream<BleDevice> scan() {
    final controller = StreamController<BleDevice>();
    final seen = <String>{};
    StreamSubscription<BleDevice>? results;
    controller
      ..onListen = () async {
        try {
          await UniversalBle.requestPermissions();
        } catch (_) {
          // Desktop platforms don't need runtime permissions.
        }
        // A Muse that is still connected (for example after a hot restart of the app, which keeps
        // the operating system's Bluetooth link open) stops advertising, so a scan won't see it.
        // Ask the system for headbands it is already connected to.
        try {
          for (final device in await UniversalBle.getSystemDevices(withServices: [museService])) {
            if (seen.add(device.deviceId)) controller.add(device);
          }
        } catch (_) {
          // Not every platform can list system devices; the scan below still works.
        }
        results = UniversalBle.scanStream.listen((device) {
          final name = device.name ?? '';
          if (name.toLowerCase().startsWith('muse') && seen.add(device.deviceId)) {
            controller.add(device);
          }
        });
        try {
          await UniversalBle.startScan();
        } catch (error) {
          controller.addError(error);
        }
      }
      ..onCancel = () async {
        await results?.cancel();
        await UniversalBle.stopScan();
      };
    return controller.stream;
  }

  @override
  Future<void> start() async {
    // Already connected (leftover link)? Then there is no "connected" event to wait for.
    if (await UniversalBle.getConnectionState(deviceId) != BleConnectionState.connected) {
      await UniversalBle.connect(deviceId, timeout: const Duration(seconds: 20));
    }
    await UniversalBle.discoverServices(deviceId);

    final characteristics = museEegCharacteristics.values.toList();
    for (var channel = 0; channel < characteristics.length; channel++) {
      _subscriptions.add(
        UniversalBle.characteristicValueStream(deviceId, characteristics[channel]).listen((bytes) {
          if (bytes.length != 20) return;
          final complete = _assembler.add(channel, decodeMuseEegPacket(bytes));
          if (complete != null) _chunks.add(EegChunk(complete));
        }),
      );
      await UniversalBle.subscribeNotifications(deviceId, museService, characteristics[channel]);
    }

    for (final command in museStartSequence) {
      await _send(command);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _send('h');
    } catch (_) {
      // Moose may already be gone (battery, out of range). Nothing to halt then.
    }
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await UniversalBle.disconnect(deviceId);
  }

  Future<void> _send(String command) =>
      UniversalBle.write(deviceId, museService, museControl, museCommand(command), withoutResponse: true);
}
