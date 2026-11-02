import 'dart:typed_data';

/// The Muse Bluetooth protocol (Muse 2016, Muse 2, Muse S), as documented by the
/// open-source projects muse-lsl and muse-js. Pure functions only, so it can be tested without a headband.

const String museService = '0000fe8d-0000-1000-8000-00805f9b34fb';
const String museControl = '273e0001-4c4d-454d-96be-f03bac821358';

/// EEG characteristics, in the order the app uses them.
const Map<String, String> museEegCharacteristics = {
  'TP9': '273e0003-4c4d-454d-96be-f03bac821358',
  'AF7': '273e0004-4c4d-454d-96be-f03bac821358',
  'AF8': '273e0005-4c4d-454d-96be-f03bac821358',
  'TP10': '273e0006-4c4d-454d-96be-f03bac821358',
};

/// Movement sensors (muse-lsl constants): 3 axes, 3 samples per packet, 52 Hz.
const String museAccelerometer = '273e000a-4c4d-454d-96be-f03bac821358';
const String museGyroscope = '273e0009-4c4d-454d-96be-f03bac821358';
const double museMotionRate = 52;
const double museAccelerometerScale = 0.0000610352; // g per unit
const double museGyroscopeScale = 0.0074768; // degrees per second per unit

const double museSampleRate = 256;
const int museSamplesPerPacket = 12;

/// One raw unit of the Muse's 12-bit converter, in microvolts.
const double museMicrovoltsPerUnit = 0.48828125;

/// Commands are sent as: [length + 1, ...ASCII letters, newline].
/// 'h' = halt, 'p21' = preset with 4 EEG channels, 's' = status, 'd' = start streaming.
Uint8List museCommand(String command) {
  final letters = command.codeUnits;
  return Uint8List.fromList([letters.length + 1, ...letters, 0x0a]);
}

/// Presets to try, in order, until the Muse accepts one ("rc":0). p21 is the classic four-channel EEG
/// preset (Muse 2, Muse S); the others cover firmware that refuses it. Learned from a Flutter app that
/// runs on a Muse S (mybliss-hrv).
const List<String> musePresets = ['p21', 'p50', 'p1106', 'p1098', 'p53', 'p23'];

/// The Muse needs a moment between commands; sent back to back, some get lost.
const Duration museCommandGap = Duration(milliseconds: 250);

/// How long to wait for the Muse to answer a preset command.
const Duration musePresetAnswerTime = Duration(milliseconds: 600);

/// The Muse answers commands with small JSON pieces on the control channel, such as {"rc":0}.
/// Returns the last result code in [text]: 0 means accepted, anything else means refused. Null if none yet.
int? lastMuseResultCode(String text) {
  final matches = RegExp(r'"rc"\s*:\s*(\d+)').allMatches(text);
  return matches.isEmpty ? null : int.parse(matches.last.group(1)!);
}

/// The firmware version from the Muse's answer to 'v6', such as "1.3.4". Null if not found.
String? museFirmware(String text) => RegExp(r'"fw"\s*:\s*"([^"]+)"').firstMatch(text)?.group(1);

class MusePacket {
  MusePacket(this.counter, this.microvolts);

  /// Increases by one for every packet; wraps around after 65535.
  final int counter;
  final List<double> microvolts;
}

/// Decodes one 20-byte EEG notification: a 2-byte counter, then 12 samples of 12 bits each.
MusePacket decodeMuseEegPacket(Uint8List data) {
  if (data.length != 20) {
    throw FormatException('A Muse EEG packet has 20 bytes, got ${data.length}.');
  }
  final counter = (data[0] << 8) | data[1];
  final microvolts = <double>[];
  for (var i = 2; i < 20; i += 3) {
    final first = (data[i] << 4) | (data[i + 1] >> 4);
    final second = ((data[i + 1] & 0x0f) << 8) | data[i + 2];
    microvolts
      ..add(museMicrovoltsPerUnit * (first - 0x800))
      ..add(museMicrovoltsPerUnit * (second - 0x800));
  }
  return MusePacket(counter, microvolts);
}

/// The Muse sends each channel as its own notification. This puts the four channels of the same
/// packet counter back together, counts packets that never got complete, and ignores packets
/// that arrive twice (which happens when an old Bluetooth subscription is still alive).
class MusePacketAssembler {
  MusePacketAssembler(this.channelCount);

  final int channelCount;
  final Map<int, List<List<double>?>> _pending = {};
  final List<int> _recentlyEmitted = [];
  int dropped = 0;
  int duplicates = 0;

  /// Returns all four channels once the last one of a counter arrives, otherwise null.
  List<List<double>>? add(int channel, MusePacket packet) {
    if (_recentlyEmitted.contains(packet.counter)) {
      duplicates++;
      return null;
    }
    final slots = _pending.putIfAbsent(packet.counter, () => List.filled(channelCount, null));
    if (slots[channel] != null) {
      duplicates++;
      return null;
    }
    slots[channel] = packet.microvolts;
    if (slots.any((s) => s == null)) {
      _forgetStale();
      return null;
    }
    _pending.remove(packet.counter);
    _recentlyEmitted.add(packet.counter);
    if (_recentlyEmitted.length > 64) _recentlyEmitted.removeAt(0);
    return slots.cast<List<double>>();
  }

  /// A handful of half-finished packets is normal; more means some notifications were lost.
  void _forgetStale() {
    while (_pending.length > 8) {
      _pending.remove(_pending.keys.first);
      dropped++;
    }
  }
}

class MuseMotionPacket {
  MuseMotionPacket(this.counter, this.samples);

  final int counter;

  /// samples[axis][i], 3 axes by 3 samples, already scaled (g or degrees per second).
  final List<List<double>> samples;
}

/// Decodes one 20-byte accelerometer or gyroscope notification: a 2-byte counter, then
/// 3 samples of (x, y, z), each a signed 16-bit big-endian number, multiplied by [scale].
MuseMotionPacket decodeMuseMotionPacket(Uint8List data, double scale) {
  if (data.length != 20) {
    throw FormatException('A Muse movement packet has 20 bytes, got ${data.length}.');
  }
  final view = ByteData.sublistView(data);
  final counter = view.getUint16(0, Endian.big);
  final samples = List.generate(3, (_) => List<double>.filled(3, 0));
  for (var i = 0; i < 3; i++) {
    for (var axis = 0; axis < 3; axis++) {
      samples[axis][i] = view.getInt16(2 + (i * 3 + axis) * 2, Endian.big) * scale;
    }
  }
  return MuseMotionPacket(counter, samples);
}
