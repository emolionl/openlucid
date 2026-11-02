import 'dart:async';

import 'package:universal_ble/universal_ble.dart';

import 'eeg_source.dart';
import 'muse_protocol.dart';

/// Moose, the real one: a Muse headband over Bluetooth Low Energy.
class MuseSource implements EegSource {
  MuseSource(this.deviceId, {String? deviceName}) : _name = deviceName ?? 'Muse';

  final String deviceId;
  final String _name;

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

  final _motion = StreamController<MotionChunk>.broadcast();

  @override
  Stream<MotionChunk> get motion => _motion.stream;

  @override
  double get motionRate => museMotionRate;

  @override
  Stream<bool> get connection => UniversalBle.connectionStream(deviceId);

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

    // The Muse answers commands (like 's' for status) on the control characteristic, as small text pieces.
    _subscriptions.add(
      UniversalBle.characteristicValueStream(deviceId, museControl).listen((bytes) {
        _capture(-1, bytes);
        if (bytes.isNotEmpty) {
          final length = bytes[0].clamp(0, bytes.length - 1);
          statusText += String.fromCharCodes(bytes.sublist(1, 1 + length));
        }
      }),
    );
    try {
      await UniversalBle.subscribeNotifications(deviceId, museService, museControl);
    } catch (_) {
      // Status replies are nice to have, not needed for streaming.
    }

    // Choose a preset first, with pauses, and check the Muse's answer: sent back to back without
    // waiting, commands can get lost, and the Muse quietly keeps streaming in its own default mode.
    await _send('h');
    await Future.delayed(museCommandGap);
    await _send('v6');
    await Future.delayed(museCommandGap);
    firmware = museFirmware(statusText);
    for (final candidate in musePresets) {
      final before = statusText.length;
      await _send(candidate);
      await Future.delayed(musePresetAnswerTime);
      final answer = lastMuseResultCode(statusText.substring(before));
      if (answer == 0) {
        preset = candidate;
        break;
      }
      // No answer at all means the control channel isn't talking to us; keep the classic preset.
      if (answer == null) {
        preset = '$candidate (not confirmed)';
        break;
      }
      await _send('h');
      await Future.delayed(museCommandGap);
    }

    final characteristics = museEegCharacteristics.values.toList();
    for (var channel = 0; channel < characteristics.length; channel++) {
      _subscriptions.add(
        UniversalBle.characteristicValueStream(deviceId, characteristics[channel]).listen((bytes) {
          _capture(channel, bytes);
          if (bytes.length != 20) return;
          final complete = _assembler.add(channel, decodeMuseEegPacket(bytes));
          if (complete != null) _chunks.add(EegChunk(complete));
        }),
      );
      await UniversalBle.subscribeNotifications(deviceId, museService, characteristics[channel]);
    }

    // Movement sensors: same 20-byte packets, 3 samples of x, y, z. Optional: a headband without them still works.
    for (final (uuid, kind, scale) in [
      (museAccelerometer, MotionKind.accelerometer, museAccelerometerScale),
      (museGyroscope, MotionKind.gyroscope, museGyroscopeScale),
    ]) {
      _subscriptions.add(
        UniversalBle.characteristicValueStream(deviceId, uuid).listen((bytes) {
          if (bytes.length != 20) return;
          _motion.add(MotionChunk(kind, decodeMuseMotionPacket(bytes, scale).samples));
        }),
      );
      try {
        await UniversalBle.subscribeNotifications(deviceId, museService, uuid);
      } catch (_) {
        // This model doesn't offer the sensor; the night is recorded without it.
      }
    }

    await _send('s');
    await Future.delayed(museCommandGap);
    await _send('d');
  }

  /// Firmware version reported by the headband, if it answered.
  String? firmware;

  /// The preset the headband accepted, such as "p21".
  String? preset;

  @override
  String get name => [
        _name,
        if (firmware != null) 'firmware $firmware',
        if (preset != null) preset,
      ].join(' · ');

  /// After the Bluetooth link dropped (out of range, the band slipped off a charging laptop's reach):
  /// connects again and repeats the start sequence. The chunk streams stay the same, so whoever
  /// listens (the night recorder) just sees a pause.
  Future<void> reconnect() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    statusText = '';
    await start();
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

  /// Everything the Muse said on its control channel since connecting (JSON pieces).
  String statusText = '';

  // Raw capture, for debugging: every notification exactly as it arrived.
  final Stopwatch _captureClock = Stopwatch();
  List<String>? _captureLines;
  Duration _captureLength = Duration.zero;
  Completer<List<String>>? _captureDone;

  /// Records every Bluetooth notification for [length], as CSV lines:
  /// milliseconds, channel (-1 = control, 0..3 = TP9, AF7, AF8, TP10), bytes in hex.
  Future<List<String>> captureRaw(Duration length) {
    _captureLines = ['ms,channel,hex'];
    _captureLength = length;
    _captureClock
      ..reset()
      ..start();
    _captureDone = Completer();
    return _captureDone!.future;
  }

  void _capture(int channel, List<int> bytes) {
    final lines = _captureLines;
    if (lines == null) return;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    lines.add('${_captureClock.elapsedMilliseconds},$channel,$hex');
    if (_captureClock.elapsed >= _captureLength) {
      _captureLines = null;
      _captureDone?.complete(lines);
    }
  }
}
