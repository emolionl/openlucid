import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_ble/universal_ble.dart';

import '../eeg/eeg_source.dart';
import '../eeg/fake_moose.dart';
import '../eeg/muse_source.dart';
import '../night/night_recorder.dart';
import '../ui/live_plot.dart';
import 'keep_awake.dart';
import 'settings.dart';

enum DeviceChoice { fakeMoose, muse }

/// Everything about the headband connection. Lives as long as the app, so switching tabs never disconnects.
class Headband extends ChangeNotifier {
  Headband(this.settings);

  final Settings settings;

  DeviceChoice choice = DeviceChoice.fakeMoose;
  final List<BleDevice> found = [];
  EegSource? source;
  SignalBuffer? buffer;
  String status = 'Not listening.';
  bool busy = false;
  double microvoltsPerLane = 200;

  StreamSubscription<BleDevice>? _scan;
  StreamSubscription<EegChunk>? _stream;

  /// The night being recorded, if any.
  NightRecorder? night;
  bool keepingAwake = false;
  int reconnects = 0;
  bool connectionLost = false;
  Timer? _nightTicker;
  StreamSubscription<bool>? _connection;

  bool get listening => source != null;
  bool get recording => night != null;

  /// Tests point this at a temporary folder.
  @visibleForTesting
  static Future<Directory> Function()? nightsFolderOverride;

  /// Where nights are kept: Documents/OpenLucid/nights, one BIDS dataset.
  static Future<Directory> nightsFolder() async {
    final override = nightsFolderOverride;
    if (override != null) return override();
    final documents = await getApplicationDocumentsDirectory();
    final s = Platform.pathSeparator;
    return Directory('${documents.path}${s}OpenLucid${s}nights');
  }
  bool get scanning => _scan != null;

  void choose(DeviceChoice value) {
    if (listening || busy) return;
    choice = value;
    status = 'Not listening.';
    notifyListeners();
  }

  void setScale(double microvolts) {
    microvoltsPerLane = microvolts;
    notifyListeners();
  }

  void startScan() {
    found.clear();
    status = 'Looking for a Muse... Switch it on: it blinks while it waits.';
    _scan = MuseSource.scan().listen(
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
    if (!listening) {
      status = found.isEmpty ? 'No Muse found. Is it switched on and nearby?' : 'Tap your Muse to connect.';
      notifyListeners();
    }
  }

  Future<void> listenToFakeMoose() => _listen(FakeMoose());

  Future<void> listenToMuse(BleDevice device) => _listen(MuseSource(device.deviceId, deviceName: device.name));

  Future<void> _listen(EegSource newSource) async {
    await stopScan();
    busy = true;
    status = 'Connecting to ${newSource.name}...';
    notifyListeners();
    try {
      final newBuffer = SignalBuffer(
        channels: newSource.channels,
        sampleRate: newSource.sampleRate,
        mainsHz: settings.mainsHz.toDouble(),
      );
      _stream = newSource.chunks.listen(newBuffer.add);
      await newSource.start();
      source = newSource;
      buffer = newBuffer;
      status = 'Connected to ${newSource.name}.';
      // Watch the link from the moment we're connected, not just once a night starts recording —
      // otherwise a drop during the pre-night contact check goes unnoticed and nothing reconnects.
      reconnects = 0;
      connectionLost = false;
      _connection = newSource.connection.listen(_onConnection);
    } catch (error) {
      await _stream?.cancel();
      status = 'Could not connect: $error';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Starts recording a night from the headband that is already streaming.
  Future<void> startNight() async {
    final current = source;
    if (current == null || recording) return;
    busy = true;
    notifyListeners();
    try {
      final muse = current is MuseSource ? current : null;
      night = await NightRecorder.start(
        source: current,
        root: await nightsFolder(),
        subjectId: settings.subjectId,
        mainsHz: settings.mainsHz,
        deviceInfo: {
          'manufacturer': muse != null ? 'InteraXon' : 'OpenLucid (simulated)',
          'model': muse != null ? 'Muse S Gen 2 (MS-02)' : current.name,
          if (muse?.firmware != null) 'firmware': '${muse!.firmware} preset ${muse.preset ?? 'n/a'}',
        },
      );
      keepingAwake = KeepAwake.enable();
      // Connection watching already started in _listen(); just keep the counters from carrying over
      // a pre-night reconnect into tonight's event log.
      reconnects = 0;
      _nightTicker = Timer.periodic(const Duration(seconds: 5), (_) => notifyListeners());
      status = 'Recording the night. Sleep well.';
    } catch (error) {
      night = null;
      status = 'Could not start the night: $error';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Stops the night and writes the files. Returns the folder of the night.
  Future<String?> stopNight() async {
    final current = night;
    if (current == null) return null;
    busy = true;
    notifyListeners();
    _nightTicker?.cancel();
    _nightTicker = null;
    // Connection watching is not night-specific anymore (see _listen()); leave it running so a
    // disconnect right after stopping still gets picked up for the live view.
    try {
      await current.stop();
      status = 'Night saved: ${current.folder.path}';
    } catch (error) {
      status = 'Problem while saving the night: $error';
    } finally {
      night = null;
      KeepAwake.disable();
      keepingAwake = false;
      busy = false;
      notifyListeners();
    }
    return current.folder.path;
  }

  // A lost Bluetooth link is not the end, whether or not a night is being recorded: mark it (if a
  // night is running, the recorder fills the missing seconds as a marked gap, so the night stays
  // one continuous file) and keep trying to connect again until stop() is called.
  void _onConnection(bool connected) {
    final muse = source;
    if (connected || connectionLost || muse is! MuseSource) return;
    connectionLost = true;
    night?.addEvent('OpenLucid disconnected', type: 'disconnected');
    status = 'Lost the headband. Trying to connect again...';
    notifyListeners();
    _reconnectLoop(muse);
  }

  Future<void> _reconnectLoop(MuseSource muse) async {
    while (source == muse && connectionLost) {
      await Future<void>.delayed(const Duration(seconds: 10));
      if (source != muse) return;
      try {
        await muse.reconnect();
        connectionLost = false;
        reconnects++;
        night?.addEvent('OpenLucid reconnected', type: 'reconnected');
        status = recording ? 'Connected again. Recording the night.' : 'Connected again.';
      } catch (_) {
        status = 'Lost the headband. Still trying to connect again...';
      }
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final current = source;
    if (current == null) return;
    if (recording) await stopNight();
    busy = true;
    notifyListeners();
    await _connection?.cancel();
    _connection = null;
    connectionLost = false;
    await current.stop();
    await _stream?.cancel();
    source = null;
    buffer = null;
    busy = false;
    status = 'Stopped. Lost packets during that session: ${current.droppedPackets}.';
    notifyListeners();
  }

  /// Debugging aid: saves 10 seconds of raw Bluetooth notifications to Documents/OpenLucid.
  Future<void> saveRaw() async {
    final muse = source;
    if (muse is! MuseSource) return;
    busy = true;
    status = 'Recording 10 seconds of raw data... keep still.';
    notifyListeners();
    try {
      final lines = await muse.captureRaw(const Duration(seconds: 10));
      final documents = await getApplicationDocumentsDirectory();
      final folder = Directory('${documents.path}${Platform.pathSeparator}OpenLucid')..createSync(recursive: true);
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final file = File('${folder.path}${Platform.pathSeparator}raw-$stamp.csv');
      await file.writeAsString('${lines.join('\n')}\n');
      final museStatus = muse.statusText.isEmpty ? '' : '\nMuse status: ${muse.statusText}';
      status = 'Saved ${lines.length - 1} notifications to ${file.path}$museStatus';
    } catch (error) {
      status = 'Could not save: $error';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    night?.stop();
    KeepAwake.disable();
    _nightTicker?.cancel();
    _connection?.cancel();
    _scan?.cancel();
    _stream?.cancel();
    source?.stop();
    super.dispose();
  }
}
