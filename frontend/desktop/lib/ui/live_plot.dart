import 'dart:math';

import 'package:flutter/material.dart';

import '../eeg/eeg_source.dart';
import '../eeg/filters.dart';

/// How good the contact of one electrode looks, judged from the last second of filtered signal.
///
/// A rough rule of thumb, not a medical measurement: relaxed EEG on the skin is usually a few
/// to a few tens of microvolts; an electrode in the air or barely touching swings far more.
enum Contact { good, okay, poor }

/// The goal: relaxed EEG on well-touching sensors wiggles this much or less (RMS, after the viewing filter).
const double contactTargetMicrovolts = 25;

/// At or above this, the sensor is as good as not touching.
const double contactLostMicrovolts = 150;

/// Contact quality from 0 (no contact) to 1 (on target), on a logarithmic scale:
/// 25 µV or less is 100%, 50 µV about 61%, 100 µV about 23%, 150 µV or more 0%.
double contactScore(double rmsMicrovolts) {
  if (rmsMicrovolts <= contactTargetMicrovolts) return 1;
  final span = log(contactLostMicrovolts / contactTargetMicrovolts);
  return (1 - log(rmsMicrovolts / contactTargetMicrovolts) / span).clamp(0, 1).toDouble();
}

Contact contactFor(double rmsMicrovolts) {
  final score = contactScore(rmsMicrovolts);
  if (score >= 0.8) return Contact.good;
  if (score >= 0.4) return Contact.okay;
  return Contact.poor;
}

/// Keeps the last few seconds of every channel, filtered for viewing.
class SignalBuffer extends ChangeNotifier {
  SignalBuffer({required this.channels, required this.sampleRate, this.seconds = 5, double mainsHz = 50})
      : _data = List.generate(channels.length, (_) => List<double>.filled((sampleRate * seconds).round(), 0)),
        _filters = List.generate(channels.length, (_) => DisplayFilter(sampleRate, mainsHz: mainsHz));

  final List<String> channels;
  final double sampleRate;
  final double seconds;
  final List<List<double>> _data;
  final List<DisplayFilter> _filters;
  int _writeAt = 0;
  int _received = 0;
  final Stopwatch _clock = Stopwatch()..start();
  final List<(int, int)> _arrivals = []; // (milliseconds, total samples so far)

  int get capacity => _data.first.length;

  void add(EegChunk chunk) {
    for (var i = 0; i < chunk.length; i++) {
      for (var ch = 0; ch < channels.length; ch++) {
        _data[ch][_writeAt] = _filters[ch].process(chunk.samples[ch][i]);
      }
      _writeAt = (_writeAt + 1) % capacity;
      _received++;
    }
    final now = _clock.elapsedMilliseconds;
    _arrivals.add((now, _received));
    while (_arrivals.length > 2 && now - _arrivals.first.$1 > 3000) {
      _arrivals.removeAt(0);
    }
    notifyListeners();
  }

  /// Samples per second actually arriving, over the last three seconds. Should match [sampleRate].
  double? get measuredRate {
    if (_arrivals.length < 2) return null;
    final (t0, n0) = _arrivals.first;
    final (t1, n1) = _arrivals.last;
    if (t1 - t0 < 1000) return null;
    return (n1 - n0) * 1000 / (t1 - t0);
  }

  /// Sample [i] of channel [ch], oldest first.
  double at(int ch, int i) => _data[ch][(_writeAt + i) % capacity];

  /// Root-mean-square of the last second: the typical size of the wiggles, in microvolts.
  /// Null during the first two seconds, while the filters settle.
  double? rms(int ch) {
    if (_received < 2 * sampleRate) return null;
    final n = sampleRate.round();
    var sum = 0.0;
    for (var i = capacity - n; i < capacity; i++) {
      final v = at(ch, i);
      sum += v * v;
    }
    return sqrt(sum / n);
  }
}

/// Draws each channel in its own lane, like a sleep lab's paper strip.
class LivePlot extends StatelessWidget {
  const LivePlot({super.key, required this.buffer, this.microvoltsPerLane = 200});

  final SignalBuffer buffer;

  /// How many microvolts fit in one lane, top to bottom. Larger values are clipped.
  final double microvoltsPerLane;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _LivePlotPainter(buffer, microvoltsPerLane, colors.primary, colors.onSurfaceVariant),
      size: Size.infinite,
    );
  }
}

class _LivePlotPainter extends CustomPainter {
  _LivePlotPainter(this.buffer, this.range, this.lineColor, this.labelColor) : super(repaint: buffer);

  final SignalBuffer buffer;
  final double range;
  final Color lineColor;
  final Color labelColor;

  static const _contactColors = {
    Contact.good: Color(0xFF4CAF50),
    Contact.okay: Color(0xFFFFC107),
    Contact.poor: Color(0xFFF44336),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final lanes = buffer.channels.length;
    final laneHeight = size.height / lanes;
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final step = max(1, (buffer.capacity / size.width).floor());

    for (var ch = 0; ch < lanes; ch++) {
      final middle = laneHeight * (ch + 0.5);
      final path = Path();
      for (var i = 0; i < buffer.capacity; i += step) {
        final x = size.width * i / buffer.capacity;
        final value = buffer.at(ch, i).clamp(-range / 2, range / 2);
        final y = middle - value / range * laneHeight;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(path, line);

      final rms = buffer.rms(ch);
      final label = rms == null ? buffer.channels[ch] : '${buffer.channels[ch]}  ${rms.toStringAsFixed(0)} µV';
      if (rms != null) {
        canvas.drawCircle(Offset(10, laneHeight * ch + 12), 5, Paint()..color = _contactColors[contactFor(rms)]!);
      }
      TextPainter(
        text: TextSpan(text: label, style: TextStyle(color: labelColor, fontSize: 12)),
        textDirection: TextDirection.ltr,
      )
        ..layout()
        ..paint(canvas, Offset(rms == null ? 4 : 20, laneHeight * ch + 4));
    }

  }

  @override
  bool shouldRepaint(_LivePlotPainter old) => old.buffer != buffer || old.range != range;
}
