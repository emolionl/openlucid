import 'dart:math';

import 'filters.dart';

/// The eye check: a guided 18-second test that tells you whether your forehead sensors can see
/// your eyes. Blinks should show up clearly on both AF7 and AF8 (in which direction depends on the headband:
/// on a Muse S they often go opposite ways); looking left and right should move them
/// in opposite directions (the eyeball is a tiny battery: front positive, back negative).
///
/// That left-right pattern is exactly the signal a lucid dreamer sends from inside a dream,
/// so this check is the first step towards detecting it.

enum EyeAction { still, blink, lookLeft, lookRight, lookAhead }

class EyeCheckStep {
  const EyeCheckStep(this.at, this.action, this.prompt);

  /// Seconds after the start of the check.
  final double at;
  final EyeAction action;
  final String prompt;
}

const eyeCheckSteps = [
  EyeCheckStep(0, EyeAction.still, 'Keep your eyes still and look straight ahead'),
  EyeCheckStep(3, EyeAction.blink, 'Blink'),
  EyeCheckStep(5, EyeAction.blink, 'Blink'),
  EyeCheckStep(7, EyeAction.blink, 'Blink'),
  EyeCheckStep(9, EyeAction.still, 'Eyes still, straight ahead'),
  EyeCheckStep(11, EyeAction.lookLeft, 'Look left'),
  EyeCheckStep(12.5, EyeAction.lookRight, 'Look right'),
  EyeCheckStep(14, EyeAction.lookLeft, 'Look left'),
  EyeCheckStep(15.5, EyeAction.lookRight, 'Look right'),
  EyeCheckStep(17, EyeAction.lookAhead, 'Straight ahead'),
];

const double eyeCheckSeconds = 18.5;

class EyeCheckResult {
  EyeCheckResult({
    required this.blinksSeen,
    required this.blinksAsked,
    required this.looksSeen,
    required this.looksAsked,
    required this.directionsConsistent,
    required this.restingNoise,
  });

  final int blinksSeen;
  final int blinksAsked;
  final int looksSeen;
  final int looksAsked;

  /// Did "left" always move AF7 the same way, and "right" the other way?
  final bool directionsConsistent;

  /// How much the slow signal wiggled while your eyes were still (µV): the floor every event must rise above.
  final double restingNoise;

  bool get passed => blinksSeen >= blinksAsked - 1 && looksSeen >= looksAsked - 1 && directionsConsistent;
}

/// Judges a recording of AF7 and AF8 (microvolts, raw) made while following [eyeCheckSteps].
EyeCheckResult evaluateEyeCheck(List<double> af7, List<double> af8, double sampleRate) {
  // Eye signals are slow: keep roughly 0.1 to 8 Hz. The low edge has to be very low, because a held
  // gaze is a step that should not fade away before we have measured it.
  List<double> slow(List<double> x) {
    final hp = Biquad.highPass(0.1, sampleRate);
    final lp = Biquad.lowPass(8, sampleRate);
    // Raw EEG starts hundreds of microvolts away from zero. Feeding that jump into a slow filter
    // leaves a fading tail for seconds, so subtract the starting level first.
    final n = min(x.length, (0.5 * sampleRate).round());
    final start = n == 0 ? 0.0 : x.take(n).reduce((p, q) => p + q) / n;
    return [for (final v in x) lp.process(hp.process(v - start))];
  }

  final a = slow(af7), b = slow(af8);
  int at(double seconds) => (seconds * sampleRate).round().clamp(0, a.length);

  // Resting noise: eyes still, after the filters have settled.
  double rms(List<double> x, int from, int to) {
    if (to <= from) return 0;
    var sum = 0.0;
    for (var i = from; i < to; i++) {
      sum += x[i] * x[i];
    }
    return sqrt(sum / (to - from));
  }

  // Resting wiggle: the quieter of the two "eyes still" moments. The first one often isn't quiet yet,
  // because people are still settling in when the check starts.
  double restAt(double from, double to) => max(rms(a, at(from), at(to)), rms(b, at(from), at(to)));
  final noise = min(restAt(0.8, 2.8), restAt(9.2, 10.8));

  // The largest swing away from [base] in a window, keeping its sign.
  double peak(List<double> x, int from, int to, double base) {
    var best = 0.0;
    for (var i = from; i < to; i++) {
      if ((x[i] - base).abs() > best.abs()) best = x[i] - base;
    }
    return best;
  }

  double mean(List<double> x, int from, int to) {
    if (to <= from) return 0;
    var sum = 0.0;
    for (var i = from; i < to; i++) {
      sum += x[i];
    }
    return sum / (to - from);
  }

  var blinksAsked = 0, blinksSeen = 0, looksAsked = 0, looksSeen = 0;
  final leftSigns = <int>[], rightSigns = <int>[];
  final blinkFloor = max(40.0, 4 * noise);
  final lookFloor = max(20.0, 3 * noise);

  for (final step in eyeCheckSteps) {
    if (step.action == EyeAction.blink) {
      blinksAsked++;
      // People need a moment to react; a blink lasts about a third of a second. Measure the swing
      // against where the signal was just before the prompt, so a drifting sensor doesn't hide it.
      final pa = peak(a, at(step.at), at(step.at + 1.5), mean(a, at(step.at - 0.4), at(step.at)));
      final pb = peak(b, at(step.at), at(step.at + 1.5), mean(b, at(step.at - 0.4), at(step.at)));
      // Both sensors must respond clearly. The direction is not checked: it depends on where the
      // headband's reference sits (measured on a Muse S, 2026-11-01: AF7 +303 µV, AF8 -465 µV).
      if (min(pa.abs(), pb.abs()) > blinkFloor) blinksSeen++;
    } else if (step.action == EyeAction.lookLeft || step.action == EyeAction.lookRight) {
      looksAsked++;
      // Compare where the signal was just before the prompt with where it settles after it.
      final da = mean(a, at(step.at + 0.3), at(step.at + 0.9)) - mean(a, at(step.at - 0.4), at(step.at));
      final db = mean(b, at(step.at + 0.3), at(step.at + 0.9)) - mean(b, at(step.at - 0.4), at(step.at));
      if (da.sign != db.sign && min(da.abs(), db.abs()) > lookFloor) {
        looksSeen++;
        (step.action == EyeAction.lookLeft ? leftSigns : rightSigns).add(da.sign.toInt());
      }
    }
  }

  final consistent = leftSigns.toSet().length <= 1 &&
      rightSigns.toSet().length <= 1 &&
      (leftSigns.isEmpty || rightSigns.isEmpty || leftSigns.first != rightSigns.first) &&
      (leftSigns.isNotEmpty || rightSigns.isNotEmpty);

  return EyeCheckResult(
    blinksSeen: blinksSeen,
    blinksAsked: blinksAsked,
    looksSeen: looksSeen,
    looksAsked: looksAsked,
    directionsConsistent: consistent,
    restingNoise: noise,
  );
}
