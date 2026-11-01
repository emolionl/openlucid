import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_ble/universal_ble.dart';

import '../eeg/eeg_source.dart';
import '../eeg/fake_moose.dart';
import '../eeg/muse_source.dart';
import '../ui/live_plot.dart';
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

  bool get listening => source != null;
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
    } catch (error) {
      await _stream?.cancel();
      status = 'Could not connect: $error';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final current = source;
    if (current == null) return;
    busy = true;
    notifyListeners();
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
    _scan?.cancel();
    _stream?.cancel();
    source?.stop();
    super.dispose();
  }
}
