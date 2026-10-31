import 'package:flutter_test/flutter_test.dart';
import 'package:openlucid/eeg/fake_moose.dart';

void main() {
  test('looks like a Muse: four channels at 256 Hz', () {
    final moose = FakeMoose();
    expect(moose.channels, ['TP9', 'AF7', 'AF8', 'TP10']);
    expect(moose.sampleRate, 256);
  });

  test('produces the number of samples asked for, in a believable range', () {
    final samples = FakeMoose().generate(256 * 20);

    expect(samples, hasLength(4));
    for (final channel in samples) {
      expect(channel, hasLength(256 * 20));
      expect(channel.every((v) => v.abs() < 300), isTrue);
    }
  });

  test('blinks show up on the forehead channels, not behind the ears', () {
    final samples = FakeMoose().generate(256 * 20);
    double peak(List<double> xs) => xs.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);

    expect(peak(samples[1]), greaterThan(80)); // AF7
    expect(peak(samples[0]), lessThan(80)); // TP9
  });

  test('the same seed gives the same night', () {
    expect(FakeMoose(seed: 1).generate(100), FakeMoose(seed: 1).generate(100));
  });
}
