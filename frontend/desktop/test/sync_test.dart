import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlucid/eeg/eeg_source.dart';
import 'package:openlucid/eeg/fake_moose.dart';
import 'package:openlucid/heart/heart_protocol.dart';
import 'package:openlucid/night/night_recorder.dart';
import 'package:openlucid/sync/diary_keeper_api.dart';
import 'package:openlucid/sync/night_upload.dart';

class _Source implements EegSource {
  final eeg = StreamController<EegChunk>.broadcast(sync: true);
  final moose = FakeMoose(seed: 4);
  @override
  String get name => 'test';
  @override
  List<String> get channels => const ['TP9', 'AF7', 'AF8', 'TP10'];
  @override
  double get sampleRate => 256;
  @override
  double get motionRate => 0;
  @override
  Stream<EegChunk> get chunks => eeg.stream;
  @override
  Stream<MotionChunk> get motion => const Stream.empty();
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
}

/// Records a 65-second night with a heart strap, the way the app does, and returns its folder.
Future<Directory> recordNight(Directory root) async {
  final source = _Source();
  final recorder = await NightRecorder.start(
    source: source,
    root: root,
    subjectId: 'sync1',
    mainsHz: 50,
    deviceInfo: const {'manufacturer': 'InteraXon', 'model': 'Muse S Gen 2 (MS-02)'},
    now: DateTime(2026, 11, 17, 23, 30),
  );
  recorder.heartLink('OpenLucid heart strap connected', type: 'heart_connected', device: 'Polar H10 TEST');
  for (var s = 0; s < 65; s++) {
    source.eeg.add(EegChunk(source.moose.generate(256)));
    await Future<void>.delayed(Duration.zero);
    // A beat per second; second 20 sends an impossible 3500 ms interval (kept in the file, not sent).
    final rr = s == 20 ? 3500.0 : 1000 + 30 * sin(s * 1.3);
    recorder.addHeart(HeartSample(heartRate: 60, rrMs: [rr], sensorContact: true), device: 'Polar H10 TEST');
  }
  await recorder.stop();
  return Directory('${root.path}/sub-sync1/ses-202611172330');
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('openlucid-sync-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a night on disk becomes the Diary Keeper\'s night, epochs (with heart) and events', () async {
    final pkg = await NightPackage.read(await recordNight(tmp));

    expect(pkg.clientId, 'sub-sync1_ses-202611172330');
    expect(pkg.night['device_name'], 'Muse S Gen 2 (MS-02)');
    expect(pkg.night['channels'], ['TP9', 'AF7', 'AF8', 'TP10']);
    expect(pkg.night['sample_rate'], 256);
    expect(pkg.night['heart_device'], 'Polar H10 TEST');
    expect(DateTime.parse(pkg.night["started_at"] as String).isAtSameMomentAs(DateTime(2026, 11, 17, 23, 30)), isTrue);
    expect(DateTime.parse(pkg.night['ended_at'] as String).isAfter(DateTime(2026, 11, 17, 23, 31)), isTrue);

    expect(pkg.epochs.length, 2);
    final e0 = pkg.epochs.first;
    expect(e0['index'], 0);
    expect((e0['contact'] as Map).keys, containsAll(['AF7', 'AF8']));
    expect(e0['heart_rate'] as double, closeTo(60, 3));
    expect(e0['hrv_rmssd'], isNotNull);
    final rr = e0['rr_intervals'] as List<double>;
    expect(rr.every((v) => v > 200 && v < 3000), isTrue);
    expect(rr.length, inInclusiveRange(25, 31)); // the 3500 ms artifact isn't sent
    expect(DateTime.parse(pkg.epochs[1]["started_at"] as String).isAtSameMomentAs(DateTime(2026, 11, 17, 23, 30, 30)), isTrue);

    final types = pkg.events.map((e) => e['type']).toList();
    expect(types, containsAll(['lights_off', 'heart_connected', 'lights_on']));
    expect(pkg.events.map((e) => e['client_id']).toSet().length, pkg.events.length);
    expect(pkg.events.firstWhere((e) => e['type'] == 'heart_connected')['details'], {'value': 'Polar H10 TEST'});

    final names = pkg.files.map((f) => f.$1.path.split(RegExp(r'[\\/]')).last).toList();
    expect(names, containsAll(['sub-sync1_ses-202611172330_task-sleep_eeg.edf', 'epochs.tsv', 'heartbeats.tsv', 'heartbeats.json']));
    expect(pkg.files.firstWhere((f) => f.$1.path.endsWith('_eeg.edf')).$2, 'edf');
    // Everything is plain JSON the API can take.
    expect(() => jsonEncode([pkg.night, pkg.epochs, pkg.events]), returnsNormally);
  });

  test('uploading twice sends the files once, and refreshes an expired token', () async {
    final night = await recordNight(tmp);
    final uploaded = <String>[];
    var refreshes = 0;
    var firstCall = true;
    final client = MockClient((request) async {
      final path = request.url.path;
      // The first request finds the access token expired.
      if (firstCall && path != '/auth/refresh') {
        firstCall = false;
        return http.Response('{"detail":"expired"}', 401);
      }
      if (path == '/auth/refresh') {
        refreshes++;
        return http.Response(jsonEncode({'access_token': 'a2', 'refresh_token': 'r2', 'token_type': 'bearer'}), 200);
      }
      expect(request.headers['Authorization'], 'Bearer a2');
      if (path == '/nights' && request.method == 'POST') return http.Response('{"id":"n1"}', 201);
      if (path == '/nights/n1' && request.method == 'PATCH') return http.Response('{"id":"n1"}', 200);
      if (path == '/nights/n1/epochs') return http.Response('{"upserted":2}', 200);
      if (path == '/nights/n1/events') return http.Response('{"created":3,"existing":0}', 200);
      if (path == '/nights/n1/recordings' && request.method == 'GET') {
        return http.Response(jsonEncode({
          'items': [
            for (final name in uploaded)
              {'original_filename': name, 'size_bytes': File('${night.path}/openlucid/$name').existsSync() ? File('${night.path}/openlucid/$name').lengthSync() : -1},
          ],
          'total': uploaded.length,
        }), 200);
      }
      if (path == '/nights/n1/recordings' && request.method == 'POST') {
        final name = RegExp(r'filename="([^"]+)"').firstMatch(latin1.decode(request.bodyBytes))?.group(1);
        uploaded.add(name!);
        return http.Response('{}', 201);
      }
      return http.Response('{"detail":"unexpected $path"}', 500);
    });
    String? kept;
    final api = DiaryKeeperApi('http://keeper.test', client: client, refreshToken: 'r1', onTokens: (_, r) => kept = r);
    api.accessToken = 'old';

    final pkg = await NightPackage.read(night);
    expect(await pkg.upload(api), 'n1');
    expect(refreshes, 1);
    expect(kept, 'r2');
    expect(uploaded.length, pkg.files.length);
    final upload = jsonDecode(File('${night.path}/openlucid/upload.json').readAsStringSync()) as Map<String, dynamic>;
    expect(upload['night_id'], 'n1');

    // Second time: the files in openlucid/ are already there with the same size and are skipped.
    final before = uploaded.length;
    await pkg.upload(api);
    final again = uploaded.sublist(before);
    expect(again.where((n) => ['epochs.tsv', 'heartbeats.tsv', 'heartbeats.json', 'EEG L.edf', 'EEG R.edf'].contains(n)), isEmpty);
  });

  // Against a real Diary Keeper: OPENLUCID_DIARY_KEEPER_URL=http://127.0.0.1:8765 flutter test test/sync_test.dart
  final real = Platform.environment['OPENLUCID_DIARY_KEEPER_URL'];
  test('end to end against a running Diary Keeper', () async {
    final api = DiaryKeeperApi(real!);
    final version = await api.version();
    final email = 'sync-${DateTime.now().microsecondsSinceEpoch}@example.org';
    await api.register(email, 'a long test password', consentVersion: version['consent_version'] as String);
    final pkg = await NightPackage.read(await recordNight(tmp));
    final id = await pkg.upload(api);
    final id2 = await pkg.upload(api); // repeat: same night, nothing doubled
    expect(id2, id);
    final epochs = await http.get(Uri.parse('$real/nights/$id/epochs'), headers: {'Authorization': 'Bearer ${api.accessToken}'});
    final items = (jsonDecode(epochs.body) as Map<String, dynamic>)['items'] as List;
    expect(items.length, 2);
    expect((items.first as Map)['heart_rate'], isNotNull);
    expect(((items.first as Map)['rr_intervals'] as List).length, greaterThan(20));
    final summary = jsonDecode((await http.get(Uri.parse('$real/nights/$id/summary'), headers: {'Authorization': 'Bearer ${api.accessToken}'})).body) as Map<String, dynamic>;
    expect((summary['heart'] as Map)['epochs'], 2);
    expect(summary['recordings'], pkg.files.length);
    final events = jsonDecode((await http.get(Uri.parse('$real/nights/$id/events'), headers: {'Authorization': 'Bearer ${api.accessToken}'})).body) as Map<String, dynamic>;
    expect(events['total'], pkg.events.length);
  }, skip: real == null ? 'Set OPENLUCID_DIARY_KEEPER_URL to run against a real Diary Keeper' : false);
}
