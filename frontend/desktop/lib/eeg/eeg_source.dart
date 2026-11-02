import 'dart:async';

/// A small batch of new EEG samples, in microvolts.
///
/// `samples[channel][i]` is sample `i` of that channel; every channel has the same number of samples.
class EegChunk {
  EegChunk(this.samples, {DateTime? receivedAt}) : receivedAt = receivedAt ?? DateTime.now();

  final List<List<double>> samples;
  final DateTime receivedAt;

  int get length => samples.isEmpty ? 0 : samples.first.length;
}

enum MotionKind { accelerometer, gyroscope }

/// A small batch of movement samples: `samples[axis][i]` for the x, y and z axes.
/// Accelerometer values are in g (1 g = gravity), gyroscope values in degrees per second.
class MotionChunk {
  MotionChunk(this.kind, this.samples, {DateTime? receivedAt}) : receivedAt = receivedAt ?? DateTime.now();

  final MotionKind kind;
  final List<List<double>> samples;
  final DateTime receivedAt;

  int get length => samples.isEmpty ? 0 : samples.first.length;
}

/// Anything that produces EEG: a real headband, a file being replayed, or a simulation.
///
/// The rest of the app only talks to this interface, so adding a new device
/// (OpenBCI, ZMax, BrainBit, ...) means writing one new class, nothing else.
abstract class EegSource {
  /// Human-friendly name, shown in the app.
  String get name;

  /// Electrode names in 10-20 notation, in the same order as [EegChunk.samples].
  List<String> get channels;

  /// Samples per second, per channel.
  double get sampleRate;

  /// New samples as they arrive. Only emits between [start] and [stop].
  Stream<EegChunk> get chunks;

  /// Movement samples (accelerometer and gyroscope), if the device has them. Empty stream otherwise.
  Stream<MotionChunk> get motion;

  /// Movement samples per second, per axis (0 if the device has no movement sensors).
  double get motionRate;

  /// True while connected, false when the link drops. Used to reconnect during a night.
  Stream<bool> get connection;

  /// How many packets went missing so far (Bluetooth hiccups, slipping headbands, ...).
  int get droppedPackets;

  /// How many packets arrived twice and were ignored (for example a leftover Bluetooth subscription).
  int get duplicatePackets;

  Future<void> start();

  Future<void> stop();
}
