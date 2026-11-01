import 'dart:math';

import 'package:flutter/material.dart';

import '../eeg/eeg_source.dart';
import '../eeg/filters.dart';

/// How good the contact of one electrode looks, judged from the last second of filtered signal.
///
/// A rough rule of thumb, not a medical measurement: relaxed EEG on the skin is usually a few
/// to a few tens of microvolts; an electrode in the air or barely touching swings far more.
enum Contact { good, okay, poor }

Contact contactFor(double rmsMicrovolts) {
  if (rmsMicrovolts < 25) return Contact.good;
  if (rmsMicrovolts < 60) return Contact.okay;
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

  int get capacity => _data.first.length;

  void add(EegChunk chunk) {
    for (var i = 0; i < chunk.length; i++) {
      for (var ch = 0; ch < channels.length; ch++) {
        _data[ch][_writeAt] = _filters[ch].process(chunk.samples[ch][i]);
      }
      _writeAt = (_writeAt + 1) % capacity;
      _received++;
    }
    notifyListeners();
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
