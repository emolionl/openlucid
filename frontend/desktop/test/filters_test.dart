import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlucid/eeg/filters.dart';
import 'package:openlucid/ui/live_plot.dart';

const fs = 256.0;

/// Feeds [seconds] of [signal] through a fresh filter and returns the RMS of the last second.
double rmsAfter(double Function(double t) signal, {double seconds = 6}) {
  final filter = DisplayFilter(fs);
  final out = <double>[];
  for (var n = 0; n < seconds * fs; n++) {
    out.add(filter.process(signal(n / fs)));
  }
  final last = out.sublist(out.length - fs.round());
  return sqrt(last.map((v) => v * v).reduce((a, b) => a + b) / last.length);
}

double rmsOfSine(double amplitude) => amplitude / sqrt2;

void main() {
  test('removes a large DC offset', () {
    expect(rmsAfter((t) => 800), lessThan(1));
  });

  test('keeps a 10 Hz alpha rhythm', () {
    expect(rmsAfter((t) => 20 * sin(2 * pi * 10 * t)), closeTo(rmsOfSine(20), 1.5));
  });

  test('removes 50 Hz mains hum', () {
    expect(rmsAfter((t) => 200 * sin(2 * pi * 50 * t)), lessThan(5));
  });

  test('alpha survives on top of hum and offset', () {
    final rms = rmsAfter((t) => 800 + 200 * sin(2 * pi * 50 * t) + 20 * sin(2 * pi * 10 * t));
    expect(rms, closeTo(rmsOfSine(20), 2));
  });

  test('contact rule of thumb', () {
    expect(contactFor(10), Contact.good);
    expect(contactFor(40), Contact.okay);
    expect(contactFor(300), Contact.poor);
  });
}
