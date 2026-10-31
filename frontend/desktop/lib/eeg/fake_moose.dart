import 'dart:async';
import 'dart:math';

import 'eeg_source.dart';

/// Fake Moose: a simulated Muse, for everyone without a headband (and for tests).
///
/// It is not a real recording. It produces signals that *look* like a relaxed, awake person
/// with closed eyes: background noise, a 10 Hz alpha rhythm, a blink now and then on the
/// forehead channels, and once in a while a slow look left and right, mirrored on AF7 and AF8.
class FakeMoose implements EegSource {
  FakeMoose({int seed = 7}) : _random = Random(seed);

  @override
  String get name => 'Fake Moose';

  @override
  List<String> get channels => const ['TP9', 'AF7', 'AF8', 'TP10'];

  @override
  double get sampleRate => 256;

  @override
  int get droppedPackets => 0;

  final Random _random;
  final _chunks = StreamController<EegChunk>.broadcast();
  final _drift = List.filled(4, 0.0);
  Timer? _timer;
  Stopwatch? _clock;
  int _sampleIndex = 0;
  int _nextBlink = 3 * 256;
  int _nextLook = 9 * 256;

  @override
  Stream<EegChunk> get chunks => _chunks.stream;

  @override
  Future<void> start() async {
    _clock = Stopwatch()..start();
    // Like the real Muse: a packet of 12 samples about 21 times per second.
    _timer = Timer.periodic(const Duration(milliseconds: 47), (_) {
      final due = (_clock!.elapsedMicroseconds * sampleRate / 1e6).floor() - _sampleIndex;
      if (due > 0) _chunks.add(EegChunk(generate(due)));
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _clock?.stop();
  }

  /// The next [count] samples of every channel, in microvolts.
  List<List<double>> generate(int count) {
    final out = List.generate(4, (_) => List<double>.filled(count, 0));
    for (var i = 0; i < count; i++) {
      final t = _sampleIndex / sampleRate;
      final alpha = 8 * sin(2 * pi * 10 * t) * (0.6 + 0.4 * sin(2 * pi * 0.1 * t));
      final blink = _blinkAt(_sampleIndex);
      final look = _lookAt(_sampleIndex);
      for (var ch = 0; ch < 4; ch++) {
        // Slowly wandering background: a random walk that keeps getting pulled back to zero.
        _drift[ch] = 0.97 * _drift[ch] + 2.5 * (_random.nextDouble() - 0.5);
        final noise = 3 * (_random.nextDouble() - 0.5);
        final isForehead = ch == 1 || ch == 2;
        out[ch][i] = _drift[ch] + noise + (isForehead ? 0.5 * alpha + blink : alpha) + (ch == 1 ? look : ch == 2 ? -look : 0);
      }
      _sampleIndex++;
    }
    return out;
  }

  /// A blink: one smooth hump of about 120 µV lasting 0.3 s, every few seconds.
  double _blinkAt(int n) {
    if (n >= _nextBlink + 77) _nextBlink = n + (3 + _random.nextInt(5)) * 256;
    final k = n - _nextBlink;
    if (k < 0 || k >= 77) return 0;
    return 120 * sin(pi * k / 77);
  }

  /// A slow look to one side and back: AF7 goes up while AF8 goes down. The eyeball is a tiny battery.
  double _lookAt(int n) {
    if (n >= _nextLook + 256) _nextLook = n + (8 + _random.nextInt(8)) * 256;
    final k = n - _nextLook;
    if (k < 0 || k >= 256) return 0;
    return 60 * sin(2 * pi * k / 256);
  }
}
