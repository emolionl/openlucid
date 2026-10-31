import 'dart:math';

import 'package:flutter/material.dart';

import '../eeg/eeg_source.dart';

/// Keeps the last few seconds of every channel, for drawing.
class SignalBuffer extends ChangeNotifier {
  SignalBuffer({required this.channels, required this.sampleRate, this.seconds = 5})
      : _data = List.generate(channels.length, (_) => List<double>.filled((sampleRate * seconds).round(), 0));

  final List<String> channels;
  final double sampleRate;
  final double seconds;
  final List<List<double>> _data;
  int _writeAt = 0;

  int get capacity => _data.first.length;

  void add(EegChunk chunk) {
    for (var i = 0; i < chunk.length; i++) {
      for (var ch = 0; ch < channels.length; ch++) {
        _data[ch][_writeAt] = chunk.samples[ch][i];
      }
      _writeAt = (_writeAt + 1) % capacity;
    }
    notifyListeners();
  }

  /// Sample [i] of channel [ch], oldest first.
  double at(int ch, int i) => _data[ch][(_writeAt + i) % capacity];
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

      TextPainter(
        text: TextSpan(text: buffer.channels[ch], style: TextStyle(color: labelColor, fontSize: 12)),
        textDirection: TextDirection.ltr,
      )
        ..layout()
        ..paint(canvas, Offset(4, laneHeight * ch + 4));
    }
  }

  @override
  bool shouldRepaint(_LivePlotPainter old) => old.buffer != buffer || old.range != range;
}
