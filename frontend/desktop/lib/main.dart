import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:universal_ble/universal_ble.dart';

import 'eeg/eeg_source.dart';
import 'eeg/fake_moose.dart';
import 'eeg/muse_source.dart';
import 'ui/live_plot.dart';

/// Where the Diary Keeper (the backend) lives. On a phone, change this to the laptop's IP address.
const String diaryKeeperUrl = 'http://localhost:8000';

void main() {
  runApp(const OpenLucidApp());
}

class OpenLucidApp extends StatelessWidget {
  const OpenLucidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenLucid',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

enum DeviceChoice { fakeMoose, muse }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Checkpoint 00: the Diary Keeper
  String _reply = 'Not asked yet.';
  bool _asking = false;

  // Checkpoint 01: the headband
  DeviceChoice _choice = DeviceChoice.fakeMoose;
  final List<BleDevice> _found = [];
  StreamSubscription<BleDevice>? _scan;
  EegSource? _source;
  SignalBuffer? _buffer;
  StreamSubscription<EegChunk>? _stream;
  String _status = 'Not listening.';
  bool _busy = false;
  double _microvoltsPerLane = 200;

  Future<void> _wave() async {
    setState(() => _asking = true);
    try {
      final response = await http.get(Uri.parse('$diaryKeeperUrl/health')).timeout(const Duration(seconds: 5));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      setState(() => _reply = '${body['message']} (${body['time']})');
    } catch (_) {
      setState(() => _reply = 'No answer. Is the Diary Keeper running? Start the backend first.');
    } finally {
      setState(() => _asking = false);
    }
  }

  void _startScan() {
    _found.clear();
    setState(() => _status = 'Looking for a Muse... (switch it on, it blinks while it waits)');
    _scan = MuseSource.scan().listen(
      (device) => setState(() => _found.add(device)),
      onError: (Object error) => setState(() => _status = 'Bluetooth problem: $error'),
    );
    Future.delayed(const Duration(seconds: 15), _stopScan);
  }

  Future<void> _stopScan() async {
    await _scan?.cancel();
    _scan = null;
    if (mounted && _source == null) {
      setState(() => _status = _found.isEmpty ? 'No Muse found. Is it on and nearby?' : 'Pick your Muse below.');
    }
  }

  Future<void> _listen(EegSource source) async {
    await _stopScan();
    setState(() {
      _busy = true;
      _status = 'Connecting to ${source.name}...';
    });
    try {
      final buffer = SignalBuffer(channels: source.channels, sampleRate: source.sampleRate);
      _stream = source.chunks.listen(buffer.add);
      await source.start();
      setState(() {
        _source = source;
        _buffer = buffer;
        _status = '${source.name}: ${source.channels.length} channels at ${source.sampleRate.round()} Hz';
      });
    } catch (error) {
      await _stream?.cancel();
      setState(() => _status = 'Could not connect: $error');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _stopListening() async {
    final source = _source;
    if (source == null) return;
    setState(() => _busy = true);
    await source.stop();
    await _stream?.cancel();
    setState(() {
      _source = null;
      _buffer = null;
      _busy = false;
      _status = 'Stopped. Missing packets during that session: ${source.droppedPackets}.';
    });
  }

  @override
  void dispose() {
    _scan?.cancel();
    _stream?.cancel();
    _source?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final listening = _source != null;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('OpenLucid', style: text.headlineMedium),
              const SizedBox(height: 4),
              const Text('Hello. I will listen to your night.'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _asking ? null : _wave,
                    icon: const Icon(Icons.waving_hand),
                    label: const Text('Wave at the Diary Keeper'),
                  ),
                  Text(_reply, key: const Key('reply')),
                ],
              ),
              const Divider(height: 32),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<DeviceChoice>(
                    segments: const [
                      ButtonSegment(value: DeviceChoice.fakeMoose, label: Text('Fake Moose'), icon: Icon(Icons.science)),
                      ButtonSegment(value: DeviceChoice.muse, label: Text('Muse'), icon: Icon(Icons.bluetooth)),
                    ],
                    selected: {_choice},
                    onSelectionChanged: listening || _busy ? null : (s) => setState(() => _choice = s.first),
                  ),
                  if (listening)
                    FilledButton.icon(
                      onPressed: _busy ? null : _stopListening,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    )
                  else if (_choice == DeviceChoice.fakeMoose)
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _listen(FakeMoose()),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start listening'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _busy || _scan != null ? null : _startScan,
                      icon: const Icon(Icons.search),
                      label: const Text('Find my Muse'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(_status, key: const Key('status')),
              if (listening)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Scale per lane:'),
                      DropdownButton<double>(
                        value: _microvoltsPerLane,
                        items: [
                          for (final uv in const [50.0, 100.0, 200.0, 500.0, 1000.0])
                            DropdownMenuItem(value: uv, child: Text('${uv.round()} µV')),
                        ],
                        onChanged: (uv) => setState(() => _microvoltsPerLane = uv!),
                      ),
                      const Text('Filtered for viewing: 0.5–40 Hz, 50 Hz hum removed. Dot = contact (green good, red poor).'),
                    ],
                  ),
                ),
              if (!listening && _choice == DeviceChoice.muse)
                for (final device in _found)
                  ListTile(
                    leading: const Icon(Icons.headphones),
                    title: Text(device.name ?? 'Muse'),
                    subtitle: Text(device.deviceId),
                    onTap: _busy ? null : () => _listen(MuseSource(device.deviceId, deviceName: device.name)),
                  ),
              const SizedBox(height: 12),
              Expanded(
                child: _buffer == null
                    ? const Center(child: Text('The live signal appears here.'))
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: LivePlot(buffer: _buffer!, microvoltsPerLane: _microvoltsPerLane),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
