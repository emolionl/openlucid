/// Heart rate variability from beat-to-beat (RR) intervals.
///
/// Raw RR intervals contain artifacts: a missed beat (the interval doubles), an extra or ectopic beat
/// (it suddenly halves), or noise when the strap moves on the skin. Those make HRV look far higher
/// than it is, so they are flagged first and left out of the numbers. Every interval is still saved
/// as received; only the metrics skip the flagged ones.
library;

import 'dart:math';

/// Intervals outside this range (30 to 200 beats per minute) are not heartbeats.
const double minRrMs = 300;
const double maxRrMs = 2000;

/// An interval that differs from the previous accepted one by more than this share is an artifact
/// (the common "20% rule" for RR series).
const double maxRrChange = 0.2;

/// Below this many clean intervals in an epoch, no HRV is reported for it.
const int minBeatsForHrv = 10;

/// One beat as recorded: the interval that ended at this beat and whether it counts.
class Beat {
  const Beat(this.rrMs, {required this.clean});

  final double rrMs;
  final bool clean;
}

/// Flags artifacts in a stream of RR intervals, one at a time, as they arrive.
class RrCleaner {
  double? _previous;

  /// Starts over, for example after the strap was off or the link dropped: the next interval has
  /// nothing to be compared with.
  void reset() => _previous = null;

  Beat add(double rrMs) {
    if (!rrMs.isFinite || rrMs < minRrMs || rrMs > maxRrMs) return Beat(rrMs, clean: false);
    final previous = _previous;
    final clean = previous == null || (rrMs - previous).abs() / previous <= maxRrChange;
    // Only accepted intervals become the reference, so one bad beat can't drag the next ones out.
    // But after a run of rejections the rhythm may really have changed: then start over from here.
    if (clean) {
      _previous = rrMs;
      _rejectedInARow = 0;
    } else if (++_rejectedInARow >= 3) {
      _previous = rrMs;
      _rejectedInARow = 0;
    }
    return Beat(rrMs, clean: clean);
  }

  int _rejectedInARow = 0;
}

/// Heart rate and HRV over a stretch of beats (one 30-second epoch, or a live window).
class HrvSummary {
  const HrvSummary({required this.beats, required this.cleanBeats, this.heartRate, this.rmssd, this.sdnn});

  /// All intervals, and the ones that counted.
  final int beats;
  final int cleanBeats;

  /// Mean heart rate in beats per minute, from the clean intervals.
  final double? heartRate;

  /// Root mean square of successive differences (ms): beat-to-beat variability, the usual short-term
  /// HRV measure. Only pairs of clean beats that followed each other directly count.
  final double? rmssd;

  /// Standard deviation of the clean intervals (ms).
  final double? sdnn;

  static HrvSummary of(List<Beat> beats) {
    final clean = [for (final b in beats) if (b.clean) b.rrMs];
    if (clean.isEmpty) return HrvSummary(beats: beats.length, cleanBeats: 0);
    final mean = clean.reduce((a, b) => a + b) / clean.length;
    final heartRate = 60000 / mean;
    if (clean.length < minBeatsForHrv) {
      return HrvSummary(beats: beats.length, cleanBeats: clean.length, heartRate: heartRate);
    }
    var squares = 0.0;
    var pairs = 0;
    for (var i = 1; i < beats.length; i++) {
      if (beats[i].clean && beats[i - 1].clean) {
        final d = beats[i].rrMs - beats[i - 1].rrMs;
        squares += d * d;
        pairs++;
      }
    }
    final variance = clean.map((r) => (r - mean) * (r - mean)).reduce((a, b) => a + b) / (clean.length - 1);
    return HrvSummary(
      beats: beats.length,
      cleanBeats: clean.length,
      heartRate: heartRate,
      rmssd: pairs >= minBeatsForHrv - 1 ? sqrt(squares / pairs) : null,
      sdnn: sqrt(variance),
    );
  }
}
