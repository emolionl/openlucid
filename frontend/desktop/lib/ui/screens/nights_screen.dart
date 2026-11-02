import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/headband.dart';
import '../../night/edf_writer.dart';
import '../theme.dart';
import 'empty_state.dart';

/// One recorded night on this device, read back from its BIDS folder.
class NightOnDisk {
  NightOnDisk(this.folder, this.started, this.epochs, this.quality, this.bytes, this.repaired);

  final Directory folder;
  final DateTime started;
  final int epochs;
  final Map<String, int> quality;
  final int bytes;
  final bool repaired;

  Duration get length => Duration(seconds: epochs * 30);

  /// Reads every ses-* folder under [root]. A night that was cut off (crash, power loss) still has
  /// "-1" as its record count; it is repaired here, except the night that is being recorded now.
  static Future<List<NightOnDisk>> list(Directory root, {String? recordingFolder}) async {
    if (!await root.exists()) return [];
    String last(String path) => path.split(RegExp(r'[\\/]')).last;
    String normal(String path) => Directory(path).absolute.path.replaceAll('\\', '/');
    final nights = <NightOnDisk>[];
    await for (final subject in root.list()) {
      if (subject is! Directory || !last(subject.path).startsWith('sub-')) continue;
      await for (final session in subject.list()) {
        if (session is! Directory) continue;
        final match = RegExp(r'^ses-(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)$').firstMatch(last(session.path));
        if (match == null) continue;
        final g = [for (var i = 1; i <= 5; i++) int.parse(match.group(i)!)];
        final started = DateTime(g[0], g[1], g[2], g[3], g[4]);

        var repaired = false;
        var bytes = 0;
        final recordingNow = recordingFolder != null && normal(recordingFolder) == normal(session.path);
        await for (final file in session.list(recursive: true)) {
          if (file is! File) continue;
          bytes += await file.length();
          if (!recordingNow && file.path.endsWith('.edf')) {
            final head = await file.openRead(236, 244).expand((b) => b).toList();
            if (String.fromCharCodes(head).trim() == '-1') {
              await EdfWriter.repairRecordCount(file.path);
              repaired = true;
            }
          }
        }

        final quality = <String, int>{};
        var epochs = 0;
        final tsv = File('${session.path}/openlucid/epochs.tsv');
        if (await tsv.exists()) {
          for (final line in (await tsv.readAsLines()).skip(1)) {
            final cells = line.split('\t');
            if (cells.length < 3) continue;
            epochs++;
            final q = cells[cells.length - 2];
            quality[q] = (quality[q] ?? 0) + 1;
          }
        }
        nights.add(NightOnDisk(session, started, epochs, quality, bytes, repaired));
      }
    }
    nights.sort((a, b) => b.started.compareTo(a.started));
    return nights;
  }
}

/// The nights recorded on this device, newest first.
class NightsScreen extends StatefulWidget {
  const NightsScreen({super.key, required this.headband});

  final Headband headband;

  @override
  State<NightsScreen> createState() => _NightsScreenState();
}

class _NightsScreenState extends State<NightsScreen> {
  late Future<(Directory, List<NightOnDisk>)> _nights = _load();

  Future<(Directory, List<NightOnDisk>)> _load() async {
    final root = await Headband.nightsFolder();
    return (root, await NightOnDisk.list(root, recordingFolder: widget.headband.night?.folder.path));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final padding = windowSizeOf(context) == WindowSize.compact ? 12.0 : 24.0;
    return FutureBuilder(
      future: _nights,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return snapshot.hasError
              ? Center(child: Text('Could not read the nights: ${snapshot.error}'))
              : const Center(child: CircularProgressIndicator());
        }
        final (root, nights) = snapshot.data!;
        if (nights.isEmpty) {
          return const EmptyState(
            title: 'No nights yet',
            icon: Icons.nights_stay_outlined,
            message: 'Start a night on the Tonight screen. Every night you record shows up here.',
            comingIn: 'The sleep skyline comes after the first nights',
          );
        }
        final recording = widget.headband.night?.folder.path;
        return ListView(
          padding: EdgeInsets.all(padding),
          children: [
            Row(
              children: [
                Expanded(child: Text('Nights', style: text.headlineMedium)),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => setState(() => _nights = _load()),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Text('Kept on this device in ${root.path}', style: text.bodySmall),
            const SizedBox(height: 12),
            for (final night in nights) _NightTile(night: night, recording: recording == night.folder.path),
          ],
        );
      },
    );
  }
}

class _NightTile extends StatelessWidget {
  const _NightTile({required this.night, required this.recording});

  final NightOnDisk night;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = night.started;
    String two(int n) => n.toString().padLeft(2, '0');
    final when = '${s.year}-${two(s.month)}-${two(s.day)} ${two(s.hour)}:${two(s.minute)}';
    final h = night.length.inHours, m = night.length.inMinutes % 60;
    final good = night.epochs == 0 ? 0 : (100 * (night.quality['good'] ?? 0) / night.epochs).round();
    final mb = (night.bytes / 1e6).toStringAsFixed(1);
    return Card(
      child: ListTile(
        leading: Icon(recording ? Icons.fiber_manual_record : Icons.bedtime_outlined, color: recording ? Colors.red : null),
        title: Text(when, style: text.titleMedium),
        subtitle: Text([
          recording ? 'recording now' : '${h}h ${two(m)}m',
          '${night.epochs} epochs, $good% good',
          '$mb MB',
          if (night.repaired) 'repaired after an interruption',
        ].join(' · ')),
        trailing: Platform.isWindows
            ? IconButton(
                tooltip: 'Open the folder',
                icon: const Icon(Icons.folder_open),
                onPressed: () => Process.run('explorer', [night.folder.path]),
              )
            : null,
      ),
    );
  }
}
