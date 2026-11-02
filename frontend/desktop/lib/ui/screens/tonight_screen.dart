import 'package:flutter/material.dart';

import '../../app/headband.dart';
import '../../eeg/muse_source.dart';
import '../../night/night_recorder.dart';
import '../live_plot.dart';
import '../theme.dart';
import 'eye_check_screen.dart';

/// Where a 10-20 electrode sits, in everyday words.
const _whereIs = {
  'TP9': 'left ear',
  'AF7': 'left forehead',
  'AF8': 'right forehead',
  'TP10': 'right ear',
};

const _contactColors = {
  Contact.good: Color(0xFF4CAF50),
  Contact.okay: Color(0xFFFFC107),
  Contact.poor: Color(0xFFF44336),
};

const _contactWords = {
  Contact.good: 'Good',
  Contact.okay: 'Okay',
  Contact.poor: 'Poor',
};

/// Connect a headband, check the contact, watch the live signal.
class TonightScreen extends StatelessWidget {
  const TonightScreen({super.key, required this.headband});

  final Headband headband;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: headband,
      builder: (context, _) => LayoutBuilder(builder: (context, space) {
        final padding = windowSizeOf(context) == WindowSize.compact ? 12.0 : 24.0;

        // Side by side only when the signal still gets a generous width.
        final sideBySide = space.maxWidth >= 760;

        if (!sideBySide) {
          final stacked = [
            const _Header(),
            const SizedBox(height: 12),
            _HeadbandCard(headband: headband, compact: true),
            if (headband.listening) ...[
              const SizedBox(height: 12),
              _NightCard(headband: headband, compact: true),
            ],
            if (headband.buffer != null && !headband.recording) ...[
              const SizedBox(height: 12),
              _ContactStrip(buffer: headband.buffer!),
            ],
            const SizedBox(height: 12),
          ];
          // Short screens (a phone on its side): scroll, and give the signal a fixed height.
          if (space.maxHeight < 560) {
            return ListView(
              padding: EdgeInsets.all(padding),
              children: [...stacked, SizedBox(height: 300, child: _SignalCard(headband: headband))],
            );
          }
          return Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [...stacked, Expanded(child: _SignalCard(headband: headband))],
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.all(padding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 340,
                child: ListView(
                  children: [
                    const _Header(),
                    const SizedBox(height: 16),
                    _HeadbandCard(headband: headband, compact: false),
                    if (headband.listening) ...[
                      const SizedBox(height: 16),
                      _NightCard(headband: headband, compact: false),
                    ],
                    if (headband.buffer != null) ...[
                      const SizedBox(height: 16),
                      _ContactCard(buffer: headband.buffer!),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(child: _SignalCard(headband: headband)),
            ],
          ),
        );
      }),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Phones have no side rail with the logo, so the header carries it.
    final phone = windowSizeOf(context) == WindowSize.compact;
    return Row(
      children: [
        if (phone) ...[
          Image.asset('assets/logo-mark-256.png', width: 40, height: 40, semanticLabel: 'OpenLucid'),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tonight', style: text.headlineMedium),
              Text('Put on your headband and check the contact.', style: text.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeadbandCard extends StatelessWidget {
  const _HeadbandCard({required this.headband, required this.compact});

  final Headband headband;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final listening = headband.listening;
    final busy = headband.busy;

    final Widget action;
    if (listening) {
      action = FilledButton.tonalIcon(
        onPressed: busy || headband.recording ? null : headband.stop,
        icon: const Icon(Icons.stop_rounded),
        label: const Text('Stop'),
      );
    } else if (headband.choice == DeviceChoice.fakeMoose) {
      action = FilledButton.icon(
        onPressed: busy ? null : headband.listenToFakeMoose,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Start listening'),
      );
    } else {
      action = FilledButton.icon(
        onPressed: busy || headband.scanning ? null : headband.startScan,
        icon: headband.scanning
            ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.bluetooth_searching_rounded),
        label: Text(headband.scanning ? 'Searching...' : 'Find my Muse'),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!listening) ...[
              Text('Headband', style: text.titleMedium),
              const SizedBox(height: 12),
              SegmentedButton<DeviceChoice>(
                segments: const [
                  ButtonSegment(value: DeviceChoice.fakeMoose, label: Text('Fake Moose'), icon: Icon(Icons.science_outlined)),
                  ButtonSegment(value: DeviceChoice.muse, label: Text('Muse'), icon: Icon(Icons.bluetooth)),
                ],
                selected: {headband.choice},
                onSelectionChanged: busy ? null : (s) => headband.choose(s.first),
              ),
              const SizedBox(height: 8),
              Text(
                headband.choice == DeviceChoice.fakeMoose
                    ? 'A simulated headband: try everything without hardware.'
                    : 'Muse 2016, Muse 2 or Muse S. Close the Muse app on your phone first.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 12),
            ] else
              Row(
                children: [
                  const Icon(Icons.sensors, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(headband.source!.name, style: text.titleMedium)),
                ],
              ),
            if (listening) const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                action,
                if (listening)
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute<void>(
                              fullscreenDialog: true,
                              builder: (_) => EyeCheckScreen(source: headband.source!, buffer: headband.buffer),
                            )),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Eye check'),
                  ),
                if (listening && headband.source is MuseSource)
                  TextButton.icon(
                    onPressed: busy ? null : headband.saveRaw,
                    icon: const Icon(Icons.save_alt, size: 18),
                    label: const Text('Save 10 s raw data'),
                  ),
              ],
            ),
            if (headband.status != 'Not listening.') ...[
              const SizedBox(height: 8),
              Text(headband.status, key: const Key('status'), style: text.bodySmall),
            ],
            if (!listening && headband.choice == DeviceChoice.muse && headband.found.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: compact ? 140 : 260),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final device in headband.found)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.headphones),
                        title: Text(device.name ?? 'Muse'),
                        subtitle: Text(device.deviceId, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: busy ? null : () => headband.listenToMuse(device),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Start a night, or follow the one being recorded.
class _NightCard extends StatelessWidget {
  const _NightCard({required this.headband, required this.compact});

  final Headband headband;

  /// Phones: just a button, or one line while recording, so the live signal keeps its room.
  final bool compact;

  Future<void> _confirmStop(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop the night?'),
        content: const Text('The recording ends and the files are written. You can start a new night afterwards.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep recording')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Stop the night')),
        ],
      ),
    );
    if (sure == true) await headband.stopNight();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final night = headband.night;
    final busy = headband.busy;

    if (night == null && compact) {
      return FilledButton.icon(
        key: const Key('startNight'),
        onPressed: busy ? null : headband.startNight,
        icon: const Icon(Icons.bedtime_outlined),
        label: const Text('Start night'),
      );
    }

    if (night == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Night', style: text.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Records the whole night on this computer: brain signal and movement, in the formats sleep '
                'research uses (EDF+, BIDS). Keep the laptop plugged in and close to the bed.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const Key('startNight'),
                  onPressed: busy ? null : headband.startNight,
                  icon: const Icon(Icons.bedtime_outlined),
                  label: const Text('Start night'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final seconds = night.recordsWritten;
    String clock(int s) => '${s ~/ 3600}:${((s ~/ 60) % 60).toString().padLeft(2, '0')}';
    final epochs = night.epochs;
    final last = epochs.isEmpty ? null : epochs.last;
    final moved = epochs.where((e) => (e.movement ?? 0) > NightRecorder.movementThreshold).length;
    final turned = epochs.where((e) => e.positionChanged).length;
    final good = epochs.where((e) => e.quality == 'good').length;
    final dot = Icon(Icons.fiber_manual_record, size: 14, color: headband.connectionLost ? Colors.orange : Colors.red);
    final stopButton = FilledButton.tonalIcon(
      key: const Key('stopNight'),
      onPressed: busy ? null : () => _confirmStop(context),
      icon: const Icon(Icons.wb_sunny_outlined),
      label: const Text('Stop night'),
    );

    if (compact) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              dot,
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headband.connectionLost
                      ? 'Reconnecting... ${clock(seconds)}'
                      : '${clock(seconds)} · ${epochs.length} epochs · $turned turns',
                  key: const Key('nightClock'),
                  style: text.bodyMedium,
                ),
              ),
              stopButton,
            ],
          ),
        ),
      );
    }

    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: text.bodyMedium)),
              Text(value, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                dot,
                const SizedBox(width: 8),
                Expanded(child: Text(headband.connectionLost ? 'Headband lost, reconnecting' : 'Recording', style: text.titleMedium)),
                Text(clock(seconds), key: const Key('nightClock'), style: text.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            row(Icons.timelapse, 'Epochs of 30 s', '${epochs.length}'),
            row(Icons.check_circle_outline, 'Good epochs', epochs.isEmpty ? '-' : '${(100 * good / epochs.length).round()}%'),
            row(Icons.directions_run, 'Epochs with movement', '$moved'),
            row(Icons.screen_rotation_alt, 'Changes of position', '$turned'),
            if (last != null) row(Icons.sensors, 'Last epoch', last.quality),
            if (headband.reconnects > 0) row(Icons.bluetooth_connected, 'Reconnected', '${headband.reconnects}x'),
            if (!headband.keepingAwake)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Could not keep this device awake: switch off sleep mode in its settings.',
                    style: text.bodySmall?.copyWith(color: Colors.orange)),
              ),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: stopButton),
          ],
        ),
      ),
    );
  }
}

/// Phones: one row of four dots.
class _ContactStrip extends StatelessWidget {
  const _ContactStrip({required this.buffer});

  final SignalBuffer buffer;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: buffer,
      builder: (context, _) => Row(
        children: [
          for (var ch = 0; ch < buffer.channels.length; ch++)
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Dot(buffer.rms(ch)),
                  const SizedBox(width: 6),
                  Text(
                    buffer.rms(ch) == null
                        ? buffer.channels[ch]
                        : '${buffer.channels[ch]} ${(contactScore(buffer.rms(ch)!) * 100).round()}%',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Tablets and laptops: a little table with where each sensor sits and what to do about it.
class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.buffer});

  final SignalBuffer buffer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListenableBuilder(
          listenable: buffer,
          builder: (context, _) {
            final readings = [for (var ch = 0; ch < buffer.channels.length; ch++) buffer.rms(ch)];
            final anyPoor = readings.any((r) => r != null && contactFor(r) == Contact.poor);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Contact', style: text.titleMedium)),
                    Text('target: under ${contactTargetMicrovolts.round()} µV', style: text.bodySmall),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'How much each sensor wiggles while you sit still. Less is better: 100% is on target, '
                  '0% means it is not touching skin.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 8),
                for (var ch = 0; ch < buffer.channels.length; ch++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            _Dot(readings[ch]),
                            const SizedBox(width: 10),
                            SizedBox(width: 44, child: Text(buffer.channels[ch], style: text.labelLarge)),
                            Expanded(child: Text(_whereIs[buffer.channels[ch]] ?? '', style: text.bodySmall)),
                            Text(
                              readings[ch] == null
                                  ? 'settling...'
                                  : '${_contactWords[contactFor(readings[ch]!)]} · ${readings[ch]!.round()} µV · '
                                      '${(contactScore(readings[ch]!) * 100).round()}%',
                              style: text.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: readings[ch] == null ? 0 : contactScore(readings[ch]!),
                            minHeight: 6,
                            color: readings[ch] == null ? null : _contactColors[contactFor(readings[ch]!)],
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (anyPoor) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Red? Wipe the skin with a damp cloth, make sure no hair is under the sensor, '
                    'and give it a minute.',
                    style: text.bodySmall,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.rms);

  final double? rms;

  @override
  Widget build(BuildContext context) {
    final color = rms == null ? Theme.of(context).colorScheme.outline : _contactColors[contactFor(rms!)]!;
    return Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.headband});

  final Headband headband;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final buffer = headband.buffer;
    final source = headband.source;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                Text('Live signal', style: text.titleMedium),
                if (buffer != null)
                  DropdownButton<double>(
                    value: headband.microvoltsPerLane,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final uv in const [50.0, 100.0, 200.0, 500.0, 1000.0])
                        DropdownMenuItem(value: uv, child: Text('${uv.round()} µV')),
                    ],
                    onChanged: (uv) => headband.setScale(uv!),
                  ),
              ],
            ),
            if (buffer != null && source != null)
              ListenableBuilder(
                listenable: buffer,
                builder: (context, _) {
                  final rate = buffer.measuredRate;
                  return Text(
                    '${rate == null ? '…' : rate.round()} samples/s · '
                    'duplicates ${source.duplicatePackets} · lost ${source.droppedPackets} · '
                    'filtered 0.5–40 Hz for viewing',
                    style: text.bodySmall,
                  );
                },
              ),
            const SizedBox(height: 8),
            Expanded(
              child: buffer == null
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.show_chart_rounded, size: 48, color: Theme.of(context).colorScheme.outline),
                            const SizedBox(height: 8),
                            Text(
                              'Your brainwaves appear here once a headband is connected.',
                              textAlign: TextAlign.center,
                              style: text.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    )
                  : LivePlot(buffer: buffer, microvoltsPerLane: headband.microvoltsPerLane),
            ),
          ],
        ),
      ),
    );
  }
}
