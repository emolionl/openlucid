import 'dart:async';
import 'dart:math';

import 'eeg_source.dart';

/// Fake Moose: a simulated Muse, for everyone without a headband (and for tests).
///
/// It is not a real recording. It produces signals that *look* like a relaxed, awake person
/// with closed eyes: background noise, a 10 Hz alpha rhythm, a blink now and then on the
/// forehead channels, and once in a while a slow look left and right, mirrored on AF7 and AF8.
/// It also simulates head movement: gravity on the accelerometer, a quiet gyroscope, and now and
/// then turning over onto another side (a burst of rotation, then gravity in a new direction).
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

  @override
  int get duplicatePackets => 0;

  final Random _random;
  final _chunks = StreamController<EegChunk>.broadcast();
  final _drift = List.filled(4, 0.0);
  Timer? _timer;
  Stopwatch? _clock;
  int _sampleIndex = 0;
  int _nextBlink = 3 * 256;
  int _nextLook = 9 * 256;
  double _gaze = 0;
  double _gazeTarget = 0;
  int _gazeFrom = 0;

  /// Far in the future: no random event planned.
  static const _never = 1 << 40;

  /// When true, Fake Moose only blinks and looks when told to (used by the eye check).
  bool get scripted => _scripted;
  bool _scripted = false;
  set scripted(bool value) {
    _scripted = value;
    if (value) {
      _nextBlink = _never;
      _nextLook = _never;
      _nextTurn = _never;
    }
  }

  /// Blink, after a human-like reaction time of about 0.25 s.
  void blink() => _nextBlink = _sampleIndex + 64;

  /// Look to one side and keep looking there: -1 left, 1 right, 0 straight ahead.
  void look(int direction) {
    _gazeTarget = 60.0 * direction;
    _gazeFrom = _sampleIndex + 64;
  }

  @override
  Stream<EegChunk> get chunks => _chunks.stream;

  final _motion = StreamController<MotionChunk>.broadcast();

  @override
  Stream<MotionChunk> get motion => _motion.stream;

  @override
  double get motionRate => 52;

  final _connection = StreamController<bool>.broadcast();

  @override
  Stream<bool> get connection => _connection.stream;

  // Simulated head orientation: the direction gravity points in, as seen by the headband.
  static const _orientations = [
    [0.0, 0.0, 1.0], // on the back
    [1.0, 0.0, 0.0], // on one side
    [-1.0, 0.0, 0.0], // on the other side
  ];
  int _orientation = 0;
  List<double> _gravity = [0.0, 0.0, 1.0];
  int _motionIndex = 0;
  int _turnUntil = -1; // motion sample index until which the head is turning
  int _nextTurn = 52 * 60 * 8; // first turn after about 8 minutes

  /// Turn over onto another side now (takes about 2 seconds).
  void turnOver() {
    _orientation = (_orientation + 1 + _random.nextInt(_orientations.length - 1)) % _orientations.length;
    _turnUntil = _motionIndex + 104;
  }

  /// The next [count] movement samples: (accelerometer [axis][i] in g, gyroscope [axis][i] in degrees/s).
  (List<List<double>>, List<List<double>>) generateMotion(int count) {
    final accel = List.generate(3, (_) => List<double>.filled(count, 0));
    final gyro = List.generate(3, (_) => List<double>.filled(count, 0));
    for (var i = 0; i < count; i++) {
      if (!_scripted && _motionIndex >= _nextTurn) {
        turnOver();
        _nextTurn = _motionIndex + 52 * 60 * (6 + _random.nextInt(10));
      }
      final turning = _motionIndex < _turnUntil;
      final target = _orientations[_orientation];
      for (var axis = 0; axis < 3; axis++) {
        // While turning, gravity swings towards the new direction; otherwise it stays put.
        _gravity[axis] += (target[axis] - _gravity[axis]) * (turning ? 0.05 : 0.0);
        accel[axis][i] = _gravity[axis] + 0.01 * (_random.nextDouble() - 0.5);
        gyro[axis][i] = (turning ? 60.0 : 0.0) * (axis == 1 ? 1 : 0.3) + 0.4 * (_random.nextDouble() - 0.5);
      }
      _motionIndex++;
    }
    return (accel, gyro);
  }

  @override
  Future<void> start() async {
    _clock = Stopwatch()..start();
    // Like the real Muse: a packet of 12 samples about 21 times per second.
    _timer = Timer.periodic(const Duration(milliseconds: 47), (_) {
      final due = (_clock!.elapsedMicroseconds * sampleRate / 1e6).floor() - _sampleIndex;
      if (due > 0) _chunks.add(EegChunk(generate(due)));
      final dueMotion = (_clock!.elapsedMicroseconds * motionRate / 1e6).floor() - _motionIndex;
      if (dueMotion > 0) {
        final (accel, gyro) = generateMotion(dueMotion);
        _motion
          ..add(MotionChunk(MotionKind.accelerometer, accel))
          ..add(MotionChunk(MotionKind.gyroscope, gyro));
      }
    });
    _connection.add(true);
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _clock?.stop();
    _connection.add(false);
  }

  /// The next [count] samples of every channel, in microvolts.
  List<List<double>> generate(int count) {
    final out = List.generate(4, (_) => List<double>.filled(count, 0));
    for (var i = 0; i < count; i++) {
      final t = _sampleIndex / sampleRate;
      final alpha = 8 * sin(2 * pi * 10 * t) * (0.6 + 0.4 * sin(2 * pi * 0.1 * t));
      final blink = _blinkAt(_sampleIndex);
      if (_sampleIndex >= _gazeFrom) _gaze += (_gazeTarget - _gaze) * 0.08; // eyes move in about 50 ms
      final look = _lookAt(_sampleIndex) + _gaze;
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
    if (n >= _nextBlink + 77) _nextBlink = _scripted ? _never : n + (3 + _random.nextInt(5)) * 256;
    final k = n - _nextBlink;
    if (k < 0 || k >= 77) return 0;
    return 120 * sin(pi * k / 77);
  }

  /// A slow look to one side and back: AF7 goes up while AF8 goes down. The eyeball is a tiny battery.
  double _lookAt(int n) {
    if (n >= _nextLook + 256) _nextLook = _scripted ? _never : n + (8 + _random.nextInt(8)) * 256;
    final k = n - _nextLook;
    if (k < 0 || k >= 256) return 0;
    return 60 * sin(2 * pi * k / 256);
  }
}
