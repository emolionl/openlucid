import 'dart:async';
import 'dart:math';

import 'package:universal_ble/universal_ble.dart';

import 'heart_protocol.dart';

/// Anything that produces heartbeats: a chest strap, or a simulation.
///
/// Like EegSource for headbands: adding another strap means writing one class.
abstract class HeartSource {
  /// Human-friendly name, shown in the app and saved with the night ("Polar H10 A1B2C3D4").
  String get name;

  /// Every notification from the strap, between [start] and [stop].
  Stream<HeartSample> get samples;

  /// True while connected, false when the link drops.
  Stream<bool> get connection;

  /// Battery level in percent, if the strap reported it.
  int? get battery;

  Future<void> start();

  /// After the link dropped: connect again. The [samples] stream stays the same.
  Future<void> reconnect();

  Future<void> stop();
}

/// A Polar H10 (or any strap with the standard Heart Rate service) over Bluetooth Low Energy.
///
/// The H10 can hold two Bluetooth connections at once, so it works next to a Polar watch or the
/// Polar app; it only advertises while it's worn (the electrodes need skin, and a little moisture).
class PolarH10Source implements HeartSource {
  PolarH10Source(this.deviceId, {String? deviceName}) : name = deviceName ?? 'Heart rate strap';

  final String deviceId;

  @override
  final String name;

  @override
  int? battery;

  final _samples = StreamController<HeartSample>.broadcast();
  StreamSubscription<List<int>>? _notifications;

  @override
  Stream<HeartSample> get samples => _samples.stream;

  @override
  Stream<bool> get connection => UniversalBle.connectionStream(deviceId);

  /// Finds straps nearby: devices named "Polar ..." or advertising the Heart Rate service, plus
  /// straps the system is already connected to (those don't advertise).
  static Stream<BleDevice> scan() {
    final controller = StreamController<BleDevice>();
    final seen = <String>{};
    StreamSubscription<BleDevice>? results;
    bool isStrap(BleDevice d) =>
        (d.name ?? '').toLowerCase().contains('polar') ||
        d.services.map((s) => s.toLowerCase()).any((s) => s == heartRateService || s == '180d');
    controller
      ..onListen = () async {
        try {
          await UniversalBle.requestPermissions();
        } catch (_) {
          // Desktop platforms don't need runtime permissions.
        }
        try {
          for (final device in await UniversalBle.getSystemDevices(withServices: [heartRateService])) {
            if (seen.add(device.deviceId)) controller.add(device);
          }
        } catch (_) {
          // Not every platform can list system devices; the scan below still works.
        }
        results = UniversalBle.scanStream.listen((device) {
          if (isStrap(device) && seen.add(device.deviceId)) controller.add(device);
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
    if (await UniversalBle.getConnectionState(deviceId) != BleConnectionState.connected) {
      await UniversalBle.connect(deviceId, timeout: const Duration(seconds: 20));
    }
    await UniversalBle.discoverServices(deviceId);
    await _notifications?.cancel();
    _notifications = UniversalBle.characteristicValueStream(deviceId, heartRateMeasurement).listen((bytes) {
      final sample = decodeHeartRateMeasurement(bytes);
      if (sample != null) _samples.add(sample);
    });
    await UniversalBle.subscribeNotifications(deviceId, heartRateService, heartRateMeasurement);
    try {
      final level = await UniversalBle.read(deviceId, batteryService, batteryLevel);
      if (level.isNotEmpty) battery = level.first;
    } catch (_) {
      // Battery level is nice to have.
    }
  }

  @override
  Future<void> reconnect() => start();

  @override
  Future<void> stop() async {
    await _notifications?.cancel();
    _notifications = null;
    try {
      await UniversalBle.unsubscribe(deviceId, heartRateService, heartRateMeasurement);
    } catch (_) {
      // Already gone (out of range, strap taken off).
    }
    await UniversalBle.disconnect(deviceId);
  }
}

/// Fake Heart: a simulated strap, for trying everything without one (and for tests).
///
/// Beats at about 60 per minute with a gentle breathing rhythm in the intervals (heart rate rises
/// a little on each breath in, which is where most short-term HRV comes from), and now and then a
/// missed beat, so the artifact handling has something to do.
class FakeHeart implements HeartSource {
  FakeHeart({int seed = 11, this.realTime = true}) : _random = Random(seed);

  final Random _random;

  /// Tests set this to false and call [beat] themselves.
  final bool realTime;

  @override
  String get name => 'Fake Heart';

  @override
  int? get battery => 100;

  final _samples = StreamController<HeartSample>.broadcast();
  final _connection = StreamController<bool>.broadcast();
  Timer? _timer;
  double _t = 0;

  @override
  Stream<HeartSample> get samples => _samples.stream;

  @override
  Stream<bool> get connection => _connection.stream;

  /// The next interval, in ms.
  double nextInterval() {
    final breathing = 60 * sin(2 * pi * _t / 4.5); // one breath every 4.5 s
    var rr = 1000 + breathing + _random.nextDouble() * 20 - 10;
    if (_random.nextDouble() < 0.01) rr *= 2; // a missed beat
    _t += rr / 1000;
    return rr;
  }

  /// One notification with one beat.
  HeartSample beat({DateTime? at}) {
    final rr = nextInterval();
    final sample = HeartSample(heartRate: (60000 / rr).round(), rrMs: [rr], sensorContact: true, receivedAt: at);
    _samples.add(sample);
    return sample;
  }

  void _schedule() {
    _timer = Timer(const Duration(milliseconds: 1000), () {
      beat();
      _schedule();
    });
  }

  @override
  Future<void> start() async {
    _connection.add(true);
    if (realTime) _schedule();
  }

  @override
  Future<void> reconnect() => start();

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _connection.add(false);
  }
}
