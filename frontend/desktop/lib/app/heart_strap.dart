import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import '../heart/heart_protocol.dart';
import '../heart/heart_source.dart';
import '../heart/hrv.dart';

enum HeartChoice { fakeHeart, polar }

/// What happened to the strap's connection; a night being recorded logs these as events.
enum HeartLinkEvent { connected, lost, reconnected, stopped }

/// The heart-rate strap (Polar H10), next to the headband. Optional: a night records fine without it,
/// and the strap can be connected or lost at any moment of the night.
///
/// Lives as long as the app, like [Headband], so switching tabs never disconnects.
class HeartStrap extends ChangeNotifier {
  HeartStrap();

  /// How much recent heartbeat the live numbers are about.
  static const liveWindow = Duration(seconds: 60);

  HeartChoice choice = HeartChoice.fakeHeart;
  final List<BleDevice> found = [];
  HeartSource? source;
  String status = 'No heart-rate strap.';
  bool busy = false;
  bool connectionLost = false;
  int reconnects = 0;

  /// Latest values, for the live view.
  int? heartRate;
  bool? sensorContact;
  final List<(DateTime, Beat)> _recent = [];
  final RrCleaner _cleaner = RrCleaner();

  final _samples = StreamController<HeartSample>.broadcast();
  final _events = StreamController<HeartLinkEvent>.broadcast();
  StreamSubscription<BleDevice>? _scan;
  StreamSubscription<HeartSample>? _stream;
  StreamSubscription<bool>? _connection;

  /// Every notification from the strap while connected (the night recorder listens here).
  Stream<HeartSample> get samples => _samples.stream;

  /// Connected, lost, reconnected, stopped.
  Stream<HeartLinkEvent> get events => _events.stream;

  bool get connected => source != null;
  bool get scanning => _scan != null;

  /// Heart rate and HRV over the last minute, from clean beats only.
  HrvSummary get live {
    final cutoff = DateTime.now().subtract(liveWindow);
    _recent.removeWhere((b) => b.$1.isBefore(cutoff));
    return HrvSummary.of([for (final b in _recent) b.$2]);
  }

  void choose(HeartChoice value) {
    if (connected || busy) return;
    choice = value;
    status = 'No heart-rate strap.';
    notifyListeners();
  }

  void startScan() {
    found.clear();
    status = 'Looking for a heart-rate strap... Put it on: a Polar H10 only wakes up on your skin.';
    _scan = PolarH10Source.scan().listen(
      (device) {
        found.add(device);
        notifyListeners();
      },
      onError: (Object error) {
        status = 'Bluetooth problem: $error';
        notifyListeners();
      },
    );
    notifyListeners();
    Future.delayed(const Duration(seconds: 15), stopScan);
  }

  Future<void> stopScan() async {
    final scan = _scan;
    if (scan == null) return;
    _scan = null;
    await scan.cancel();
    if (!connected) {
      status = found.isEmpty
          ? 'No strap found. Wet the electrodes a little, wear it, and try again.'
          : 'Tap your strap to connect.';
      notifyListeners();
    }
  }

  Future<void> connectFake() => _connect(FakeHeart());

  Future<void> connectStrap(BleDevice device) =>
      _connect(PolarH10Source(device.deviceId, deviceName: device.name ?? 'Polar H10'));

  /// For tests: use any source.
  @visibleForTesting
  Future<void> connectSource(HeartSource source) => _connect(source);

  Future<void> _connect(HeartSource newSource) async {
    await stopScan();
    busy = true;
    status = 'Connecting to ${newSource.name}...';
    notifyListeners();
    try {
      _stream = newSource.samples.listen(_onSample);
      await newSource.start();
      source = newSource;
      connectionLost = false;
      reconnects = 0;
      _cleaner.reset();
      _recent.clear();
      _connection = newSource.connection.listen(_onConnection);
      status = 'Connected to ${newSource.name}${newSource.battery != null ? ' · battery ${newSource.battery}%' : ''}.';
      _events.add(HeartLinkEvent.connected);
    } catch (error) {
      await _stream?.cancel();
      _stream = null;
      status = 'Could not connect: $error';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _onSample(HeartSample sample) {
    heartRate = sample.heartRate;
    sensorContact = sample.sensorContact;
    for (final rr in sample.rrMs) {
      _recent.add((sample.receivedAt, _cleaner.add(rr)));
    }
    _samples.add(sample);
    notifyListeners();
  }

  void _onConnection(bool isConnected) {
    final current = source;
    if (isConnected || connectionLost || current == null) return;
    connectionLost = true;
    heartRate = null;
    _cleaner.reset();
    _events.add(HeartLinkEvent.lost);
    status = 'Lost the strap. Trying to connect again...';
    notifyListeners();
    _reconnectLoop(current);
  }

  Future<void> _reconnectLoop(HeartSource current) async {
    while (source == current && connectionLost) {
      await Future<void>.delayed(const Duration(seconds: 10));
      if (source != current) return;
      try {
        await current.reconnect();
        connectionLost = false;
        reconnects++;
        _cleaner.reset();
        _events.add(HeartLinkEvent.reconnected);
        status = 'Connected again to ${current.name}.';
      } catch (_) {
        status = 'Lost the strap. Still trying to connect again...';
      }
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final current = source;
    if (current == null) return;
    busy = true;
    notifyListeners();
    unawaited(_connection?.cancel());
    _connection = null;
    source = null;
    connectionLost = false;
    try {
      await current.stop();
    } catch (_) {
      // Already gone.
    }
    await _stream?.cancel();
    _stream = null;
    heartRate = null;
    sensorContact = null;
    _recent.clear();
    _events.add(HeartLinkEvent.stopped);
    busy = false;
    status = 'Strap disconnected.';
    notifyListeners();
  }

  @override
  void dispose() {
    _scan?.cancel();
    _connection?.cancel();
    _stream?.cancel();
    source?.stop();
    _samples.close();
    _events.close();
    super.dispose();
  }
}
