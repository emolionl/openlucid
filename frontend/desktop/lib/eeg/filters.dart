import 'dart:math';

/// Small digital filters for *displaying* EEG. Recordings always keep the raw, unfiltered signal.

/// One second-order filter section (a "biquad"), with the classic formulas from
/// Robert Bristow-Johnson's Audio EQ Cookbook.
class Biquad {
  Biquad._(this._b0, this._b1, this._b2, this._a1, this._a2);

  /// Lets through everything above [cutoff] Hz: removes the slow drift and the DC offset.
  factory Biquad.highPass(double cutoff, double sampleRate, {double q = 0.7071}) {
    final w = 2 * pi * cutoff / sampleRate;
    final alpha = sin(w) / (2 * q);
    final c = cos(w);
    return Biquad._normalized((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alpha, -2 * c, 1 - alpha);
  }

  /// Lets through everything below [cutoff] Hz: removes fast muscle buzz.
  factory Biquad.lowPass(double cutoff, double sampleRate, {double q = 0.7071}) {
    final w = 2 * pi * cutoff / sampleRate;
    final alpha = sin(w) / (2 * q);
    final c = cos(w);
    return Biquad._normalized((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + alpha, -2 * c, 1 - alpha);
  }

  /// Cuts out a narrow band around [frequency] Hz: the hum of the power grid (50 Hz in Europe, 60 Hz in the Americas).
  factory Biquad.notch(double frequency, double sampleRate, {double q = 10}) {
    final w = 2 * pi * frequency / sampleRate;
    final alpha = sin(w) / (2 * q);
    final c = cos(w);
    return Biquad._normalized(1, -2 * c, 1, 1 + alpha, -2 * c, 1 - alpha);
  }

  factory Biquad._normalized(double b0, double b1, double b2, double a0, double a1, double a2) =>
      Biquad._(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);

  final double _b0, _b1, _b2, _a1, _a2;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  double process(double x) {
    final y = _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }
}

/// The usual EEG viewing filter: 0.5–40 Hz, minus the mains hum.
class DisplayFilter {
  DisplayFilter(double sampleRate, {double mainsHz = 50})
      : _stages = [
          Biquad.highPass(0.5, sampleRate),
          Biquad.notch(mainsHz, sampleRate),
          Biquad.lowPass(40, sampleRate),
        ];

  final List<Biquad> _stages;

  double process(double x) {
    var y = x;
    for (final stage in _stages) {
      y = stage.process(y);
    }
    return y;
  }
}
