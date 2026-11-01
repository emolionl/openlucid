import 'package:flutter/material.dart';

import '../../app/headband.dart';
import '../../eeg/muse_source.dart';
import '../live_plot.dart';
import '../theme.dart';

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
            if (headband.buffer != null) ...[
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tonight', style: text.headlineMedium),
        Text('Put on your headband and check the contact.', style: text.bodyMedium),
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
        onPressed: busy ? null : headband.stop,
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
                  Text(buffer.channels[ch], style: Theme.of(context).textTheme.labelMedium),
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
                Text('Contact', style: text.titleMedium),
                const SizedBox(height: 8),
                for (var ch = 0; ch < buffer.channels.length; ch++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        _Dot(readings[ch]),
                        const SizedBox(width: 10),
                        SizedBox(width: 44, child: Text(buffer.channels[ch], style: text.labelLarge)),
                        Expanded(child: Text(_whereIs[buffer.channels[ch]] ?? '', style: text.bodySmall)),
                        Text(
                          readings[ch] == null
                              ? 'settling...'
                              : '${_contactWords[contactFor(readings[ch]!)]} · ${readings[ch]!.round()} µV',
                          style: text.bodySmall,
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
