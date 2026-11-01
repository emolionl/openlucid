import 'package:flutter_test/flutter_test.dart';
import 'package:openlucid/eeg/eye_check.dart';
import 'package:openlucid/eeg/fake_moose.dart';

/// Records Fake Moose for the whole eye check, doing what each prompt asks if [obey] is true.
(List<double>, List<double>) record({required bool obey, int seed = 3}) {
  final moose = FakeMoose(seed: seed)..scripted = true;
  final af7 = <double>[], af8 = <double>[];
  final total = (eyeCheckSeconds * 256).round();
  var next = 0;
  for (var n = 0; n < total; n++) {
    while (next < eyeCheckSteps.length && eyeCheckSteps[next].at * 256 <= n) {
      if (obey) {
        switch (eyeCheckSteps[next].action) {
          case EyeAction.blink:
            moose.blink();
          case EyeAction.lookLeft:
            moose.look(-1);
          case EyeAction.lookRight:
            moose.look(1);
          case EyeAction.lookAhead:
            moose.look(0);
          case EyeAction.still:
            break;
        }
      }
      next++;
    }
    final sample = moose.generate(1);
    af7.add(sample[1][0]);
    af8.add(sample[2][0]);
  }
  return (af7, af8);
}

void main() {
  test('a cooperative Fake Moose passes the eye check', () {
    final (af7, af8) = record(obey: true);
    final result = evaluateEyeCheck(af7, af8, 256);

    expect(result.blinksSeen, 3);
    expect(result.looksSeen, 4);
    expect(result.directionsConsistent, isTrue);
    expect(result.passed, isTrue);
  });

  test('a Fake Moose that ignores the prompts fails it', () {
    final (af7, af8) = record(obey: false);
    final result = evaluateEyeCheck(af7, af8, 256);

    expect(result.blinksSeen, 0);
    expect(result.looksSeen, 0);
    expect(result.passed, isFalse);
  });

  test('works for different random seeds', () {
    for (var seed = 1; seed <= 5; seed++) {
      final (af7, af8) = record(obey: true, seed: seed);
      expect(evaluateEyeCheck(af7, af8, 256).passed, isTrue, reason: 'seed $seed');
    }
  });
}
