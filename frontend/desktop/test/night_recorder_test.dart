import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlucid/eeg/eeg_source.dart';
import 'package:openlucid/eeg/fake_moose.dart';
import 'package:openlucid/heart/heart_protocol.dart';
import 'package:openlucid/night/edf_writer.dart';
import 'package:openlucid/night/night_recorder.dart';

/// A source the test feeds by hand: no timers, so a "night" of minutes takes milliseconds.
class HandFedSource implements EegSource {
  final eeg = StreamController<EegChunk>.broadcast(sync: true);
  final motionController = StreamController<MotionChunk>.broadcast(sync: true);
  final moose = FakeMoose(seed: 2);

  @override
  String get name => 'Hand-fed test source';
  @override
  List<String> get channels => const ['TP9', 'AF7', 'AF8', 'TP10'];
  @override
  double get sampleRate => 256;
  @override
  double get motionRate => 52;
  @override
  Stream<EegChunk> get chunks => eeg.stream;
  @override
  Stream<MotionChunk> get motion => motionController.stream;
  @override
  Stream<bool> get connection => const Stream.empty();
  @override
  int get droppedPackets => 0;
  @override
  int get duplicatePackets => 0;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}

  /// Sends [seconds] of Fake Moose data (EEG and movement).
  /// With [realTime], one second of data per second, like a real headband.
  Future<void> feed(int seconds, {bool realTime = false}) async {
    for (var s = 0; s < seconds; s++) {
      if (realTime && s > 0) await Future<void>.delayed(const Duration(seconds: 1));
      eeg.add(EegChunk(moose.generate(256)));
      final (accel, gyro) = moose.generateMotion(52);
      motionController
        ..add(MotionChunk(MotionKind.accelerometer, accel))
        ..add(MotionChunk(MotionKind.gyroscope, gyro));
      await Future<void>.delayed(Duration.zero); // let the recorder write
    }
  }
}

String header(File f, int from, int to) => ascii.decode(f.readAsBytesSync().sublist(from, to)).trim();

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('openlucid-night-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('EDF writer: header fields and record size are right, and a cut-off file can be repaired', () async {
    final path = '${tmp.path}/t.edf';
    final w = await EdfWriter.create(path, start: DateTime(2026, 11, 2, 23, 5, 9), signals: const [
      EdfSignal(label: 'EEG AF7-Fpz', physicalDimension: 'uV', physicalMin: -1000, physicalMax: 1000, samplesPerRecord: 256),
    ]);
    await w.writeRecord([List.filled(256, 0)], annotations: const [EdfAnnotation(0.5, 'OpenLucid cue')]);
    await w.writeRecord([List.filled(256, 1000)]);
    await w.flush();

    final f = File(path);
    expect(header(f, 0, 8), '0');
    expect(header(f, 8, 88), 'X X X X'); // anonymous patient
    expect(header(f, 88, 168), startsWith('Startdate 02-NOV-2026'));
    expect(header(f, 168, 176), '02.11.26');
    expect(header(f, 176, 184), '23.05.09');
    expect(header(f, 192, 236), 'EDF+C');
    expect(header(f, 236, 244), '-1'); // still recording
    expect(f.lengthSync(), 256 * 3 + 2 * (256 * 2 + 120));

    // Pretend the app crashed: never closed. The repair counts complete records.
    expect(await EdfWriter.repairRecordCount(path), 2);
    expect(header(f, 236, 244), '2');
    await w.close();
  });

  test('a recorded night becomes a BIDS-EEG folder with EDF+, sidecars, epochs and events', () async {
    final source = HandFedSource();
    final recorder = await NightRecorder.start(
      source: source,
      root: tmp,
      subjectId: 'abc123',
      mainsHz: 50,
      deviceInfo: const {'manufacturer': 'InteraXon', 'model': 'Muse S Gen 2 (MS-02)'},
      now: DateTime(2026, 11, 2, 23, 0),
    );
    await source.feed(65); // two full epochs and a bit
    source.moose.turnOver();
    await source.feed(60);
    await recorder.stop();

    final eegDir = '${tmp.path}/sub-abc123/ses-202611022300/eeg';
    final base = '$eegDir/sub-abc123_ses-202611022300_task-sleep';
    expect(File('${tmp.path}/dataset_description.json').existsSync(), isTrue);
    for (final suffix in ['_eeg.edf', '_eeg.json', '_channels.tsv', '_events.tsv']) {
      expect(File('$base$suffix').existsSync(), isTrue, reason: suffix);
    }

    final edf = File('$base\_eeg.edf');
    expect(int.parse(header(edf, 236, 244)), greaterThanOrEqualTo(125)); // records written and counted
    expect(header(edf, 252, 256), '11'); // 4 EEG + 3 accel + 3 gyro + annotations

    final sidecar = jsonDecode(File('$base\_eeg.json').readAsStringSync()) as Map<String, dynamic>;
    for (final key in ['EEGReference', 'SamplingFrequency', 'PowerLineFrequency', 'SoftwareFilters', 'TaskName']) {
      expect(sidecar.containsKey(key), isTrue, reason: 'BIDS requires $key');
    }
    expect(sidecar['TaskName'], 'sleep');
    expect(sidecar['EEGReference'], 'Fpz');

    final channels = File('$base\_channels.tsv').readAsLinesSync();
    expect(channels.first, startsWith('name\ttype\tunits'));
    expect(channels.where((l) => l.contains('\tMISC\t')).length, 6);

    final events = File('$base\_events.tsv').readAsStringSync();
    expect(events, contains('lights_off'));
    expect(events, contains('lights_on'));
    expect(events, contains('position_change'));

    final epochsTsv = File('${tmp.path}/sub-abc123/ses-202611022300/openlucid/epochs.tsv').readAsLinesSync();
    expect(epochsTsv.length, 1 + 4); // header + 4 complete epochs (125 s)
    expect(recorder.epochs.where((e) => e.positionChanged), isNotEmpty);

    for (final name in ['EEG L.edf', 'EEG R.edf']) {
      expect(File('${tmp.path}/sub-abc123/ses-202611022300/openlucid/$name').existsSync(), isTrue);
    }

    // OPENLUCID_KEEP_NIGHT=<folder> keeps this night so tools/check_night.py (MNE) can open it.
    final keep = Platform.environment['OPENLUCID_KEEP_NIGHT'];
    if (keep != null) {
      for (final entity in tmp.listSync(recursive: true).whereType<File>()) {
        final target = File('$keep/${entity.path.substring(tmp.path.length + 1)}');
        target.parent.createSync(recursive: true);
        entity.copySync(target.path);
      }
    }
  });

  test('a still head with a gyroscope offset is not movement; a turn is', () async {
    // The first real night: the Muse gyroscope reads about (-5.6, -2.1, -3.1) deg/s while lying still.
    final source = HandFedSource();
    final recorder = await NightRecorder.start(source: source, root: tmp, subjectId: 'still', mainsHz: 50);
    Future<void> second(double Function(int i) gyroX) async {
      source.eeg.add(EegChunk(source.moose.generate(256)));
      source.motionController
        ..add(MotionChunk(MotionKind.accelerometer, [List.filled(52, 0.36), List.filled(52, 0.12), List.filled(52, 0.92)]))
        ..add(MotionChunk(MotionKind.gyroscope, [
          [for (var i = 0; i < 52; i++) gyroX(i)],
          List.filled(52, -2.1),
          List.filled(52, -3.1),
        ]));
      await Future<void>.delayed(Duration.zero);
    }

    for (var s = 0; s < 30; s++) {
      await second((i) => -5.6 + (i.isEven ? 0.1 : -0.1)); // still, with a little sensor noise
    }
    for (var s = 0; s < 30; s++) {
      await second((i) => -5.6 + 30 * sin(2 * pi * i / 52)); // turning the head back and forth
    }
    await recorder.stop();

    expect(recorder.epochs, hasLength(2));
    expect(recorder.epochs[0].movement, lessThan(NightRecorder.movementThreshold));
    expect(recorder.epochs[1].movement, greaterThan(NightRecorder.movementThreshold));
  });

  test('a dropout becomes a marked gap, so the file stays in step with the clock', () async {
    final source = HandFedSource();
    final recorder = await NightRecorder.start(source: source, root: tmp, subjectId: 'gap', mainsHz: 50);
    await source.feed(3, realTime: true);
    await Future<void>.delayed(const Duration(seconds: 6)); // the headband is silent for ~6 s
    await source.feed(2, realTime: true);
    await recorder.stop();

    final events = File(recorder.edfPath.replaceFirst('_eeg.edf', '_events.tsv')).readAsStringSync();
    expect(events, contains('\tgap\t'));
    expect(recorder.recordsWritten, greaterThanOrEqualTo(3 + 3 + 2)); // data + filled-in gap seconds
  });

  test('heartbeats from a strap go into heartbeats.tsv and give each epoch its heart rate and HRV', () async {
    final source = HandFedSource();
    final recorder = await NightRecorder.start(source: source, root: tmp, subjectId: 'h1', mainsHz: 50, now: DateTime(2026, 11, 17, 23, 0));
    recorder.heartLink('OpenLucid heart strap connected', type: 'heart_connected', device: 'Polar H10 TEST');
    // 65 seconds, one beat per second with a small breathing rhythm; one missed beat at second 40.
    for (var s = 0; s < 65; s++) {
      await source.feed(1);
      final rr = s == 40 ? 2000.0 : 1000 + 40 * sin(s * 1.4);
      recorder.addHeart(HeartSample(heartRate: 60, rrMs: [rr], sensorContact: true), device: 'Polar H10 TEST');
    }
    // A notification with no RR (the strap does that) adds nothing.
    recorder.addHeart(HeartSample(heartRate: 60, rrMs: const []), device: 'Polar H10 TEST');
    await recorder.stop();

    final night = '${tmp.path}/sub-h1/ses-202611172300';
    final beats = File('$night/openlucid/heartbeats.tsv').readAsLinesSync();
    expect(beats.first, 'onset\trr_ms\theart_rate_bpm\tclean\tsensor_contact');
    expect(beats.length, 1 + 65);
    expect(recorder.heartBeats, 65);
    expect(beats.where((l) => l.split('\t')[3] == '0').length, 1); // the missed beat
    final onsets = beats.skip(1).map((l) => double.parse(l.split('\t').first)).toList();
    for (var i = 1; i < onsets.length; i++) {
      expect(onsets[i], greaterThan(onsets[i - 1]), reason: 'beats in time order');
    }
    final meta = jsonDecode(File('$night/openlucid/heartbeats.json').readAsStringSync()) as Map<String, dynamic>;
    expect(meta['Device'], 'Polar H10 TEST');

    expect(recorder.epochs.length, 2);
    final first = recorder.epochs.first;
    expect(first.heart, isNotNull);
    expect(first.heart!.heartRate, closeTo(60, 3));
    expect(first.heart!.rmssd, isNotNull);
    expect(first.rrMs.length, inInclusiveRange(28, 31));
    final second = recorder.epochs[1];
    expect(second.heart!.cleanBeats, second.heart!.beats - 1);
    // Every beat is in at most one epoch.
    expect(first.rrMs.length + second.rrMs.length, lessThanOrEqualTo(65));

    final epochsTsv = File('$night/openlucid/epochs.tsv').readAsLinesSync();
    final head = epochsTsv.first.split('\t');
    expect(head, containsAll(['heart_rate_bpm', 'hrv_rmssd_ms', 'hrv_sdnn_ms', 'beats', 'clean_beats']));
    final row = epochsTsv[1].split('\t');
    expect(double.parse(row[head.indexOf('heart_rate_bpm')]), closeTo(60, 3));

    final events = File(recorder.edfPath.replaceFirst('_eeg.edf', '_events.tsv')).readAsStringSync();
    expect(events, contains('heart_connected'));
  });

  test('a night without a strap writes no heartbeat file and n/a for heart in the epochs', () async {
    final source = HandFedSource();
    final recorder = await NightRecorder.start(source: source, root: tmp, subjectId: 'h2', mainsHz: 50, now: DateTime(2026, 11, 17, 23, 0));
    await source.feed(31);
    await recorder.stop();
    final night = '${tmp.path}/sub-h2/ses-202611172300';
    expect(File('$night/openlucid/heartbeats.tsv').existsSync(), isFalse);
    expect(recorder.epochs.single.heart, isNull);
    final epochsTsv = File('$night/openlucid/epochs.tsv').readAsLinesSync();
    final head = epochsTsv.first.split('\t');
    expect(epochsTsv[1].split('\t')[head.indexOf('heart_rate_bpm')], 'n/a');
  });
}
