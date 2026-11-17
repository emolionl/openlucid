import 'package:flutter/material.dart';

import '../app/heart_strap.dart';

/// The heart-rate strap on the Tonight screen: connect it, and see heart rate and HRV live.
/// Optional; the night is recorded with or without it.
class HeartCard extends StatelessWidget {
  const HeartCard({super.key, required this.heart, required this.compact});

  final HeartStrap heart;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: heart,
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        final connected = heart.connected;
        final busy = heart.busy;
        final live = heart.live;

        final Widget action;
        if (connected) {
          action = FilledButton.tonalIcon(
            key: const Key('heartDisconnect'),
            onPressed: busy ? null : heart.stop,
            icon: const Icon(Icons.link_off_rounded),
            label: const Text('Disconnect'),
          );
        } else if (heart.choice == HeartChoice.fakeHeart) {
          action = FilledButton.icon(
            key: const Key('heartConnect'),
            onPressed: busy ? null : heart.connectFake,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Connect Fake Heart'),
          );
        } else {
          action = FilledButton.icon(
            key: const Key('heartScan'),
            onPressed: busy || heart.scanning ? null : heart.startScan,
            icon: heart.scanning
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.bluetooth_searching_rounded),
            label: Text(heart.scanning ? 'Searching...' : 'Find my strap'),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.favorite_rounded, size: 20, color: connected ? const Color(0xFFFF6B81) : null),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(connected ? heart.source!.name : 'Heart (optional)', style: text.titleMedium),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!connected) ...[
                  SegmentedButton<HeartChoice>(
                    segments: const [
                      ButtonSegment(value: HeartChoice.fakeHeart, label: Text('Fake Heart'), icon: Icon(Icons.science_outlined)),
                      ButtonSegment(value: HeartChoice.polar, label: Text('Polar H10'), icon: Icon(Icons.bluetooth)),
                    ],
                    selected: {heart.choice},
                    onSelectionChanged: busy ? null : (s) => heart.choose(s.first),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    heart.choice == HeartChoice.fakeHeart
                        ? 'A simulated heart: try heart rate and HRV without a strap.'
                        : 'A Polar H10 chest strap, or any strap with standard Bluetooth heart rate. Wet the electrodes and wear it first.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  Row(
                    children: [
                      _Number(label: 'Heart rate', value: heart.heartRate?.toString() ?? '–', unit: 'bpm', big: true),
                      const SizedBox(width: 20),
                      _Number(label: 'HRV (RMSSD, last minute)', value: live.rmssd?.toStringAsFixed(0) ?? '–', unit: 'ms'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (heart.sensorContact == false) 'The strap doesn\'t feel your skin.',
                      if (live.beats > 0) '${live.cleanBeats} of ${live.beats} beats clean in the last minute.',
                      if (live.rmssd == null && live.cleanBeats < 10) 'HRV appears after about 10 clean beats.',
                      if (heart.source!.battery != null) 'Battery ${heart.source!.battery}%.',
                    ].join(' '),
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ],
                Wrap(spacing: 8, runSpacing: 8, children: [action]),
                if (heart.status != 'No heart-rate strap.') ...[
                  const SizedBox(height: 8),
                  Text(heart.status, key: const Key('heartStatus'), style: text.bodySmall),
                ],
                if (!connected && heart.choice == HeartChoice.polar && heart.found.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: compact ? 140 : 220),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final device in heart.found)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.monitor_heart_outlined),
                            title: Text(device.name ?? 'Heart-rate strap'),
                            subtitle: Text(device.deviceId, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: busy ? null : () => heart.connectStrap(device),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Number extends StatelessWidget {
  const _Number({required this.label, required this.value, required this.unit, this.big = false});

  final String label;
  final String value;
  final String unit;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.bodySmall),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: big ? text.headlineMedium : text.titleLarge),
            const SizedBox(width: 4),
            Text(unit, style: text.bodySmall),
          ],
        ),
      ],
    );
  }
}
