import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'diary_keeper_api.dart';

/// RR intervals the Diary Keeper accepts (backend: epochs.rr_intervals). The strap's raw stream can
/// hold values outside this (artifacts); they stay in heartbeats.tsv, which is uploaded as a file too.
const double uploadMinRrMs = 200;
const double uploadMaxRrMs = 3000;
const int uploadMaxRrPerEpoch = 200;

/// One night as saved on this device (its BIDS session folder), turned into what the Diary Keeper
/// stores. Read from the files, not from memory, so any earlier night can be uploaded too, and the
/// upload can simply be repeated: the night, its epochs and events are matched by their ids.
class NightPackage {
  NightPackage._(this.folder, this.clientId, this.night, this.epochs, this.events, this.files);

  final Directory folder;

  /// The same for this night on every upload: "sub-<id>_ses-<yyyymmddhhmm>".
  final String clientId;
  final Map<String, dynamic> night;
  final List<Map<String, dynamic>> epochs;
  final List<Map<String, dynamic>> events;

  /// Files to upload: (file, kind).
  final List<(File, String)> files;

  String? get heartDevice => night['heart_device'] as String?;

  static String _name(String path) => path.split(RegExp(r'[\\/]')).last;

  static Future<NightPackage> read(Directory session) async {
    final sessionName = _name(session.path);
    final subjectName = _name(session.parent.path);
    final base = '${subjectName}_${sessionName}_task-sleep';
    final eegDir = '${session.path}/eeg';
    final ownDir = '${session.path}/openlucid';
    final edf = File('$eegDir/${base}_eeg.edf');
    if (!await edf.exists()) throw StateError('No EEG file in ${session.path}.');

    final startedAt = await _edfStart(edf);
    final sidecar = await _json(File('$eegDir/${base}_eeg.json'));
    final heartMeta = await _json(File('$ownDir/heartbeats.json'));
    final duration = (sidecar['RecordingDuration'] as num?)?.toDouble();

    // EEG channels in 10-20 names ("EEG AF7-Fpz" -> "AF7").
    final channels = <String>[];
    final channelsTsv = File('$eegDir/${base}_channels.tsv');
    if (await channelsTsv.exists()) {
      for (final row in _tsv(await channelsTsv.readAsLines())) {
        if (row['type'] == 'EEG') channels.add(row['name']!.replaceFirst(RegExp(r'^EEG '), '').replaceFirst(RegExp(r'-\w+$'), ''));
      }
    }

    // Every beat, by the epoch it fell in.
    final rrByEpoch = <int, List<double>>{};
    final beatsTsv = File('$ownDir/heartbeats.tsv');
    if (await beatsTsv.exists()) {
      for (final row in _tsv(await beatsTsv.readAsLines())) {
        final onset = double.tryParse(row['onset'] ?? '');
        final rr = double.tryParse(row['rr_ms'] ?? '');
        if (onset == null || rr == null || !rr.isFinite || rr <= uploadMinRrMs || rr >= uploadMaxRrMs) continue;
        final list = rrByEpoch.putIfAbsent(max(0, onset ~/ 30), () => []);
        if (list.length < uploadMaxRrPerEpoch) list.add(double.parse(rr.toStringAsFixed(3)));
      }
    }

    final epochs = <Map<String, dynamic>>[];
    final epochsTsv = File('$ownDir/epochs.tsv');
    if (await epochsTsv.exists()) {
      for (final row in _tsv(await epochsTsv.readAsLines())) {
        final index = int.tryParse(row['epoch'] ?? '');
        if (index == null) continue;
        final onset = double.tryParse(row['onset'] ?? '') ?? index * 30.0;
        final contact = <String, double>{
          for (final e in row.entries)
            if (e.key.startsWith('contact_') && double.tryParse(e.value) != null) e.key.substring(8): double.parse(e.value),
        };
        double? number(String key) => double.tryParse(row[key] ?? '');
        final rr = rrByEpoch[index];
        epochs.add({
          'index': index,
          'started_at': _iso(startedAt.add(Duration(milliseconds: (onset * 1000).round()))),
          if (contact.isNotEmpty) 'contact': contact,
          if (const {'good', 'okay', 'poor', 'gap'}.contains(row['quality'])) 'quality': row['quality'],
          if (_inRange(number('heart_rate_bpm'), 20, 250)) 'heart_rate': number('heart_rate_bpm'),
          if (_inRange(number('hrv_rmssd_ms'), 0, 1000)) 'hrv_rmssd': number('hrv_rmssd_ms'),
          if (_inRange(number('hrv_sdnn_ms'), 0, 1000)) 'hrv_sdnn': number('hrv_sdnn_ms'),
          if (rr != null && rr.isNotEmpty) 'rr_intervals': rr,
        });
      }
    }

    final events = <Map<String, dynamic>>[];
    final eventsTsv = File('$eegDir/${base}_events.tsv');
    if (await eventsTsv.exists()) {
      var line = 0;
      for (final row in _tsv(await eventsTsv.readAsLines())) {
        line++;
        final onset = double.tryParse(row['onset'] ?? '');
        final type = row['trial_type'] ?? '';
        if (onset == null || type.isEmpty) continue;
        final duration = double.tryParse(row['duration'] ?? '');
        final value = row['value'];
        events.add({
          // The line in events.tsv: stable, because the file is only ever appended to.
          'client_id': 'ev-$line',
          'at': _iso(startedAt.add(Duration(milliseconds: (onset * 1000).round()))),
          'type': type.length > 40 ? type.substring(0, 40) : type,
          if (duration != null || (value != null && value != 'n/a'))
            'details': {
              if (duration != null) 'duration': duration,
              if (value != null && value != 'n/a') 'value': value,
            },
        });
      }
    }

    final night = <String, dynamic>{
      'client_id': '${subjectName}_$sessionName',
      'started_at': _iso(startedAt),
      'device_name': _cut((sidecar['ManufacturersModelName'] as String?) ?? 'unknown', 100),
      if (sidecar['DeviceSoftwareVersion'] is String) 'device_firmware': _cut(sidecar['DeviceSoftwareVersion'] as String, 100),
      'channels': channels,
      'sample_rate': (sidecar['SamplingFrequency'] as num?)?.toDouble() ?? 256,
      if (heartMeta['Device'] is String) 'heart_device': _cut(heartMeta['Device'] as String, 100),
      if (duration != null) 'ended_at': _iso(startedAt.add(Duration(milliseconds: (duration * 1000).round()))),
    };

    final files = <(File, String)>[
      (edf, 'edf'),
      for (final name in ['${base}_eeg.json', '${base}_channels.tsv', '${base}_events.tsv']) (File('$eegDir/$name'), 'other'),
      for (final name in ['EEG L.edf', 'EEG R.edf']) (File('$ownDir/$name'), 'edf'),
      for (final name in ['epochs.tsv', 'heartbeats.tsv', 'heartbeats.json']) (File('$ownDir/$name'), 'other'),
    ];
    final existing = <(File, String)>[];
    for (final f in files) {
      if (await f.$1.exists()) existing.add(f);
    }
    return NightPackage._(session, night['client_id'] as String, night, epochs, events, existing);
  }

  /// Sends the night to the Diary Keeper. Safe to repeat: nothing is duplicated, files already
  /// there (same name and size) are skipped. Returns the night's id on the server.
  Future<String> upload(DiaryKeeperApi api, {void Function(String)? progress}) async {
    progress?.call('Creating the night...');
    final create = Map<String, dynamic>.of(night)..remove('ended_at');
    final created = await api.createNight(create);
    final id = created['id'] as String;
    if (night['ended_at'] != null || night['heart_device'] != null) {
      await api.updateNight(id, {
        if (night['ended_at'] != null) 'ended_at': night['ended_at'],
        if (night['heart_device'] != null) 'heart_device': night['heart_device'],
      });
    }
    progress?.call('Sending ${epochs.length} epochs...');
    await api.putEpochs(id, epochs);
    progress?.call('Sending ${events.length} events...');
    await api.postEvents(id, events);

    final there = {for (final r in await api.recordings(id)) '${r['original_filename']}|${r['size_bytes']}'};
    var n = 0;
    for (final (file, kind) in files) {
      n++;
      final name = _name(file.path);
      if (there.contains('$name|${await file.length()}')) continue;
      progress?.call('Uploading file $n of ${files.length}: $name...');
      await api.uploadRecording(id, file, kind: kind, filename: name);
    }

    await File('${folder.path}/openlucid/upload.json').writeAsString(const JsonEncoder.withIndent('  ').convert({
      'server': api.baseUrl,
      'night_id': id,
      'uploaded_at': DateTime.now().toUtc().toIso8601String(),
      'epochs': epochs.length,
      'events': events.length,
    }));
    return id;
  }

  /// When this night was last uploaded, and where; null if never.
  static Future<Map<String, dynamic>?> lastUpload(Directory session) async {
    final f = File('${session.path}/openlucid/upload.json');
    return await f.exists() ? await _json(f) : null;
  }

  // ---- Reading the files ----

  /// The start time from the EDF header (local time, to the second).
  static Future<DateTime> _edfStart(File edf) async {
    final head = String.fromCharCodes(await edf.openRead(168, 184).expand((b) => b).toList());
    final m = RegExp(r'^(\d\d)\.(\d\d)\.(\d\d)(\d\d)\.(\d\d)\.(\d\d)$').firstMatch(head.trim());
    if (m == null) throw StateError('Unreadable start time in ${edf.path}.');
    final g = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
    // EDF years: 85-99 are 1985-1999, 00-84 are 2000-2084.
    return DateTime(g[2] >= 85 ? 1900 + g[2] : 2000 + g[2], g[1], g[0], g[3], g[4], g[5]);
  }

  static Future<Map<String, dynamic>> _json(File f) async {
    if (!await f.exists()) return {};
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Iterable<Map<String, String>> _tsv(List<String> lines) sync* {
    if (lines.isEmpty) return;
    final head = lines.first.split('\t');
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      final cells = line.split('\t');
      yield {for (var i = 0; i < head.length && i < cells.length; i++) head[i]: cells[i]};
    }
  }

  static bool _inRange(double? v, double lo, double hi) => v != null && v.isFinite && v >= lo && v <= hi;
  static String _iso(DateTime t) => t.toUtc().toIso8601String();
  static String _cut(String s, int n) => s.length > n ? s.substring(0, n) : s;
}
