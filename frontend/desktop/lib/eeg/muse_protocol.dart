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

/// The commands that start a stream, in order.
const List<String> museStartSequence = ['h', 'p21', 's', 'd'];

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
