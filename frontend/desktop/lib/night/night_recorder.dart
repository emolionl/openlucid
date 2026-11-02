import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../eeg/eeg_source.dart';
import '../eeg/filters.dart';
import '../ui/live_plot.dart' show contactScore;
import 'edf_writer.dart';

/// Summary of one 30-second epoch, as written to epochs.tsv.
class EpochSummary {
  EpochSummary({
    required this.index,
    required this.onset,
    required this.contact,
    required this.movement,
    required this.positionChanged,
    required this.quality,
    required this.gapSeconds,
  });

  final int index;
  final double onset;

  /// Contact score 0..1 per EEG channel (same score as the live view).
  final Map<String, double> contact;

  /// Mean rotation speed of the head in degrees per second (from the gyroscope); null without one.
  final double? movement;
  final bool positionChanged;

  /// good, okay, poor or gap.
  final String quality;
  final int gapSeconds;
}

/// Records a whole night to a BIDS-EEG folder, crash-safe, while the headband streams.
///
/// Layout (see docs/research/eeg-data-standards.md):
///   <root>/dataset_description.json
///   <root>/sub-<id>/ses-<yyyymmddhhmm>/eeg/sub-<id>_ses-<..>_task-sleep_eeg.edf  (+ .json, _channels.tsv, _events.tsv)
///   <root>/sub-<id>/ses-<..>/openlucid/epochs.tsv, EEG L.edf, EEG R.edf (Dreamento export)
class NightRecorder {
  NightRecorder._(this.source, this.folder, this.baseName, this.startedAt, this.mainsHz, this.deviceInfo);

  /// Movement above this mean rotation speed (degrees per second) during an epoch counts as movement.
  static const double movementThreshold = 5;

  /// A change in gravity direction of more than this many degrees counts as a change of position.
  static const double positionChangeDegrees = 30;

  final EegSource source;
  final Directory folder; // .../sub-x/ses-y
  final String baseName; // sub-x_ses-y_task-sleep
  final DateTime startedAt;
  final int mainsHz;
  final Map<String, String> deviceInfo;

  late final EdfWriter _edf;
  late final EdfWriter _dreamentoL;
  late final EdfWriter _dreamentoR;
  late final IOSink _epochsTsv;
  late final IOSink _eventsTsv;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _stopwatch = Stopwatch();

  // Buffers of samples not yet written into a 1-second record.
  late final List<List<double>> _eeg;
  final List<List<double>> _accel = List.generate(3, (_) => []);
  final List<List<double>> _gyro = List.generate(3, (_) => []);
  final List<double> _lastAccel = [0, 0, 0];
  final List<double> _lastGyro = [0, 0, 0];

  // Per-epoch accumulators.
  late final List<DisplayFilter> _filters;
  late final List<double> _sumSquares;
  int _epochSamples = 0;
  double _gyroSum = 0;
  int _gyroCount = 0;
  final List<double> _accelSum = [0, 0, 0];
  int _accelCount = 0;
  List<double>? _stableGravity;
  int _epochGapSeconds = 0;
  final Map<String, bool> _wasPoor = {};

  final List<EdfAnnotation> _pendingAnnotations = [];
  final List<EpochSummary> epochs = [];
  int eventCount = 0;
  bool _writing = false;
  bool _closed = false;

  int get recordsWritten => _edf.recordsWritten;
  Duration get elapsed => _stopwatch.elapsed;
  String get edfPath => '${folder.path}/eeg/${baseName}_eeg.edf';

  int get _eegRate => source.sampleRate.round();
  int get _motionRate => source.motionRate.round();
  bool get _hasMotion => _motionRate > 0;

  /// Creates the folders and files and starts listening to [source] (which must already be streaming).
  static Future<NightRecorder> start({
    required EegSource source,
    required Directory root,
    required String subjectId,
    required int mainsHz,
    Map<String, String> deviceInfo = const {},
    DateTime? now,
  }) async {
    final startTime = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final session = '${startTime.year}${two(startTime.month)}${two(startTime.day)}${two(startTime.hour)}${two(startTime.minute)}';
    final folder = Directory('${root.path}/sub-$subjectId/ses-$session');
    await Directory('${folder.path}/eeg').create(recursive: true);
    await Directory('${folder.path}/openlucid').create(recursive: true);
    await _writeDatasetDescription(root);

    final recorder = NightRecorder._(
      source,
      folder,
      'sub-${subjectId}_ses-${session}_task-sleep',
      startTime,
      mainsHz,
      deviceInfo,
    );
    await recorder._open();
    return recorder;
  }

  Future<void> _open() async {
    final eegSignals = [
      for (final ch in source.channels)
        EdfSignal(
          label: 'EEG $ch-Fpz',
          physicalDimension: 'uV',
          physicalMin: -1000,
          physicalMax: 1000,
          samplesPerRecord: _eegRate,
          transducer: 'dry electrode',
          prefiltering: 'none',
        ),
    ];
    final motionSignals = !_hasMotion
        ? <EdfSignal>[]
        : [
            for (final axis in ['X', 'Y', 'Z'])
              EdfSignal(label: 'Accel $axis', physicalDimension: 'g', physicalMin: -2, physicalMax: 2, samplesPerRecord: _motionRate),
            for (final axis in ['X', 'Y', 'Z'])
              EdfSignal(label: 'Gyro $axis', physicalDimension: 'deg/s', physicalMin: -245, physicalMax: 245, samplesPerRecord: _motionRate),
          ];
    _edf = await EdfWriter.create(edfPath, signals: [...eegSignals, ...motionSignals], start: startedAt);

    // Dreamento opens ZMax recordings as one EDF per signal: "EEG L.edf" and "EEG R.edf".
    EdfSignal single(String ch) => EdfSignal(
          label: 'EEG $ch-Fpz',
          physicalDimension: 'uV',
          physicalMin: -1000,
          physicalMax: 1000,
          samplesPerRecord: _eegRate,
        );
    _dreamentoL = await EdfWriter.create('${folder.path}/openlucid/EEG L.edf', signals: [single('AF7')], start: startedAt);
    _dreamentoR = await EdfWriter.create('${folder.path}/openlucid/EEG R.edf', signals: [single('AF8')], start: startedAt);

    _eeg = List.generate(source.channels.length, (_) => []);
    _filters = List.generate(source.channels.length, (_) => DisplayFilter(source.sampleRate, mainsHz: mainsHz.toDouble()));
    _sumSquares = List.filled(source.channels.length, 0);

    _epochsTsv = File('${folder.path}/openlucid/epochs.tsv').openWrite();
    _epochsTsv.writeln([
      'epoch',
      'onset',
      for (final ch in source.channels) 'contact_$ch',
      'movement_deg_s',
      'position_changed',
      'quality',
      'gap_seconds',
    ].join('\t'));
    _eventsTsv = File('${folder.path}/eeg/${baseName}_events.tsv').openWrite();
    _eventsTsv.writeln('onset\tduration\ttrial_type\tvalue');

    _stopwatch.start();
    addEvent('Lights off', type: 'lights_off');
    _subscriptions
      ..add(source.chunks.listen(_onEeg))
      ..add(source.motion.listen(_onMotion));
  }

  /// Records an event now: in events.tsv and as an EDF+ annotation.
  void addEvent(String text, {required String type, String value = 'n/a', double? duration}) {
    final onset = _edf.recordsWritten * 1.0 + _eegBuffered / max(1, _eegRate);
    _pendingAnnotations.add(EdfAnnotation(onset, text, duration: duration));
    _eventsTsv.writeln('${onset.toStringAsFixed(3)}\t${duration?.toStringAsFixed(3) ?? 'n/a'}\t$type\t$value');
    eventCount++;
  }

  int get _eegBuffered => _eeg.isEmpty ? 0 : _eeg.first.length;

  void _onEeg(EegChunk chunk) {
    for (var ch = 0; ch < _eeg.length; ch++) {
      _eeg[ch].addAll(chunk.samples[ch]);
    }
    _drain();
  }

  void _onMotion(MotionChunk chunk) {
    final target = chunk.kind == MotionKind.accelerometer ? _accel : _gyro;
    for (var axis = 0; axis < 3; axis++) {
      target[axis].addAll(chunk.samples[axis]);
    }
  }

  // Contact and movement are measured on exactly the samples that go into a record, so each
  // 30-second summary describes the same seconds as the file, even when data arrived in a burst.
  void _measure(List<List<double>> eegRecord, List<List<double>> accel, List<List<double>> gyro) {
    for (var ch = 0; ch < eegRecord.length; ch++) {
      for (final v in eegRecord[ch]) {
        final f = _filters[ch].process(v);
        _sumSquares[ch] += f * f;
      }
    }
    _epochSamples += eegRecord.isEmpty ? 0 : eegRecord.first.length;
    if (gyro.isNotEmpty) {
      for (var i = 0; i < gyro.first.length; i++) {
        final x = gyro[0][i], y = gyro[1][i], z = gyro[2][i];
        _gyroSum += sqrt(x * x + y * y + z * z);
        _gyroCount++;
      }
    }
    if (accel.isNotEmpty) {
      for (var i = 0; i < accel.first.length; i++) {
        for (var axis = 0; axis < 3; axis++) {
          _accelSum[axis] += accel[axis][i];
        }
        _accelCount++;
      }
    }
  }

  /// Writes every complete second that is buffered. Also fills gaps after a dropout, so the file
  /// stays continuous (EDF+C) and in step with the clock.
  Future<void> _drain() async {
    if (_writing || _closed) return;
    _writing = true;
    try {
      // A gap: the clock ran ahead of the data by more than 2 seconds (headband dropped out).
      final behind = _stopwatch.elapsed.inSeconds - _edf.recordsWritten - _eegBuffered ~/ max(1, _eegRate);
      if (behind > 2) {
        final gapStart = _edf.recordsWritten.toDouble();
        _pendingAnnotations.add(EdfAnnotation(gapStart, 'OpenLucid gap', duration: behind.toDouble()));
        _eventsTsv.writeln('${gapStart.toStringAsFixed(3)}\t$behind\tgap\tn/a');
        eventCount++;
        for (var s = 0; s < behind; s++) {
          await _writeRecord(gap: true);
        }
      }
      while (_eegBuffered >= _eegRate) {
        await _writeRecord(gap: false);
      }
    } finally {
      _writing = false;
    }
  }

  List<double> _take(List<double> buffer, int count, double fallback) {
    final out = <double>[];
    final n = min(count, buffer.length);
    out.addAll(buffer.sublist(0, n));
    buffer.removeRange(0, n);
    while (out.length < count) {
      out.add(out.isEmpty ? fallback : out.last);
    }
    return out;
  }

  Future<void> _writeRecord({required bool gap}) async {
    final eegRecord = [
      for (var ch = 0; ch < _eeg.length; ch++) gap ? List<double>.filled(_eegRate, 0) : _take(_eeg[ch], _eegRate, 0),
    ];
    final motionRecord = <List<double>>[];
    final realAccel = <List<double>>[], realGyro = <List<double>>[];
    if (_hasMotion) {
      final hadAccel = _accel.first.isNotEmpty, hadGyro = _gyro.first.isNotEmpty;
      for (var axis = 0; axis < 3; axis++) {
        final a = _take(_accel[axis], _motionRate, _lastAccel[axis]);
        _lastAccel[axis] = a.last;
        motionRecord.add(a);
        if (hadAccel) realAccel.add(a);
      }
      for (var axis = 0; axis < 3; axis++) {
        final g = _take(_gyro[axis], _motionRate, _lastGyro[axis]);
        _lastGyro[axis] = g.last;
        motionRecord.add(g);
        if (hadGyro) realGyro.add(g);
      }
      // Movement samples beyond one second's worth pile up if the two clocks drift; keep at most 2 s.
      for (final buffer in [..._accel, ..._gyro]) {
        if (buffer.length > 2 * _motionRate) buffer.removeRange(0, buffer.length - _motionRate);
      }
    }

    // Annotations that fit go into this record; the rest wait for the next one.
    final now = <EdfAnnotation>[];
    while (_pendingAnnotations.isNotEmpty && _edf.annotationsFit([...now, _pendingAnnotations.first])) {
      now.add(_pendingAnnotations.removeAt(0));
    }
    await _edf.writeRecord([...eegRecord, ...motionRecord], annotations: now);
    final af7 = source.channels.indexOf('AF7'), af8 = source.channels.indexOf('AF8');
    if (af7 >= 0) await _dreamentoL.writeRecord([eegRecord[af7]]);
    if (af8 >= 0) await _dreamentoR.writeRecord([eegRecord[af8]]);
    if (gap) {
      _epochGapSeconds++;
    } else {
      _measure(eegRecord, realAccel, realGyro);
    }

    if (_edf.recordsWritten % 30 == 0) _closeEpoch();
    if (_edf.recordsWritten % 10 == 0) await _edf.flush();
  }

  void _closeEpoch() {
    final index = _edf.recordsWritten ~/ 30 - 1;
    final contact = <String, double>{};
    for (var ch = 0; ch < source.channels.length; ch++) {
      final rms = _epochSamples == 0 ? double.infinity : sqrt(_sumSquares[ch] / _epochSamples);
      contact[source.channels[ch]] = rms.isFinite ? contactScore(rms) : 0;
      _sumSquares[ch] = 0;
    }
    _epochSamples = 0;

    double? movement;
    if (_gyroCount > 0) movement = _gyroSum / _gyroCount;
    var positionChanged = false;
    if (_accelCount > 0) {
      final gravity = [for (final s in _accelSum) s / _accelCount];
      final stable = _stableGravity;
      if (stable == null) {
        _stableGravity = gravity;
      } else if (_angleDegrees(stable, gravity) > positionChangeDegrees) {
        positionChanged = true;
        _stableGravity = gravity;
      }
    }
    _gyroSum = 0;
    _gyroCount = 0;
    _accelSum.setAll(0, [0, 0, 0]);
    _accelCount = 0;

    final forehead = [contact['AF7'], contact['AF8']].whereType<double>().toList();
    final worst = forehead.isEmpty ? contact.values.fold(1.0, min) : forehead.reduce(min);
    final moving = (movement ?? 0) > movementThreshold;
    final quality = _epochGapSeconds >= 15
        ? 'gap'
        : worst < 0.4
            ? 'poor'
            : (worst < 0.8 || moving)
                ? 'okay'
                : 'good';

    final epoch = EpochSummary(
      index: index,
      onset: index * 30.0,
      contact: contact,
      movement: movement,
      positionChanged: positionChanged,
      quality: quality,
      gapSeconds: _epochGapSeconds,
    );
    epochs.add(epoch);
    _epochGapSeconds = 0;
    _epochsTsv.writeln([
      index,
      epoch.onset.toStringAsFixed(0),
      for (final ch in source.channels) contact[ch]!.toStringAsFixed(3),
      movement?.toStringAsFixed(2) ?? 'n/a',
      positionChanged ? 1 : 0,
      quality,
      epoch.gapSeconds,
    ].join('\t'));

    if (moving) addEvent('OpenLucid movement', type: 'movement', value: movement!.toStringAsFixed(1), duration: 30);
    if (positionChanged) addEvent('OpenLucid position change', type: 'position_change');
    for (final entry in contact.entries) {
      final poor = entry.value < 0.4;
      if (poor && !(_wasPoor[entry.key] ?? false)) {
        addEvent('OpenLucid contact lost', type: 'contact_lost', value: entry.key);
      }
      _wasPoor[entry.key] = poor;
    }
  }

  static double _angleDegrees(List<double> a, List<double> b) {
    double dot = 0, na = 0, nb = 0;
    for (var i = 0; i < 3; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0;
    return acos((dot / sqrt(na * nb)).clamp(-1.0, 1.0)) * 180 / pi;
  }

  /// Stops listening, writes the remaining annotations, closes the files and writes the BIDS sidecars.
  Future<void> stop() async {
    if (_closed) return;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    while (_writing) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await _drain(); // seconds that arrived while a write was busy
    addEvent('Lights on', type: 'lights_on');
    _closed = true;
    // Leftover annotations get one more (empty-signal) second so they're not lost.
    while (_pendingAnnotations.isNotEmpty) {
      _closed = false;
      await _writeRecord(gap: true);
      _closed = true;
    }
    _stopwatch.stop();
    await _edf.close();
    await _dreamentoL.close();
    await _dreamentoR.close();
    await _epochsTsv.close();
    await _eventsTsv.close();
    await _writeSidecars();
  }

  Future<void> _writeSidecars() async {
    final seconds = _edf.recordsWritten.toDouble();
    final eegJson = {
      'TaskName': 'sleep',
      'TaskDescription': 'An overnight recording at home with OpenLucid.',
      'SamplingFrequency': source.sampleRate,
      'PowerLineFrequency': mainsHz,
      'EEGReference': 'Fpz',
      'SoftwareFilters': 'n/a',
      'RecordingType': 'continuous',
      'RecordingDuration': seconds,
      'EEGChannelCount': source.channels.length,
      'EOGChannelCount': 0,
      'EMGChannelCount': 0,
      'MiscChannelCount': _hasMotion ? 6 : 0,
      'EEGPlacementScheme': '10-20 subset: ${source.channels.join(', ')}',
      'Manufacturer': deviceInfo['manufacturer'] ?? 'n/a',
      'ManufacturersModelName': deviceInfo['model'] ?? source.name,
      'SoftwareVersions': 'OpenLucid',
      if (deviceInfo['firmware'] != null) 'DeviceSoftwareVersion': deviceInfo['firmware'],
    };
    await File('${folder.path}/eeg/${baseName}_eeg.json').writeAsString(const JsonEncoder.withIndent('  ').convert(eegJson));

    final goodShare = <String, double>{};
    for (final ch in source.channels) {
      final scores = epochs.map((e) => e.contact[ch] ?? 0).toList();
      goodShare[ch] = scores.isEmpty ? 0 : scores.where((s) => s >= 0.8).length / scores.length;
    }
    final rows = <String>['name\ttype\tunits\treference\tsampling_frequency\tstatus\tstatus_description'];
    for (final ch in source.channels) {
      final share = goodShare[ch]!;
      rows.add('EEG $ch-Fpz\tEEG\tuV\tFpz\t${source.sampleRate}\t${share >= 0.5 ? 'good' : 'bad'}\t'
          'good contact in ${(share * 100).round()}% of epochs');
    }
    if (_hasMotion) {
      for (final axis in ['X', 'Y', 'Z']) {
        rows.add('Accel $axis\tMISC\tg\tn/a\t${source.motionRate}\tgood\taccelerometer');
      }
      for (final axis in ['X', 'Y', 'Z']) {
        rows.add('Gyro $axis\tMISC\tdeg/s\tn/a\t${source.motionRate}\tgood\tgyroscope');
      }
    }
    await File('${folder.path}/eeg/${baseName}_channels.tsv').writeAsString('${rows.join('\n')}\n');
  }

  static Future<void> _writeDatasetDescription(Directory root) async {
    final file = File('${root.path}/dataset_description.json');
    if (await file.exists()) return;
    await root.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'Name': 'OpenLucid nights',
      'BIDSVersion': '1.9.0',
      'DatasetType': 'raw',
      'GeneratedBy': [
        {'Name': 'OpenLucid', 'CodeURL': 'https://github.com/emolionl/openlucid'},
      ],
    }));
  }
}
