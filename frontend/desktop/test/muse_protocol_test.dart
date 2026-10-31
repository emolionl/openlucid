import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlucid/eeg/muse_protocol.dart';

/// Builds a 20-byte packet the way the Muse does: counter, then pairs of 12-bit samples in 3 bytes.
Uint8List packet(int counter, List<int> raw) {
  final bytes = <int>[counter >> 8, counter & 0xff];
  for (var i = 0; i < raw.length; i += 2) {
    bytes
      ..add(raw[i] >> 4)
      ..add(((raw[i] & 0x0f) << 4) | (raw[i + 1] >> 8))
      ..add(raw[i + 1] & 0xff);
  }
  return Uint8List.fromList(bytes);
}

void main() {
  test('commands are length-prefixed and end with a newline', () {
    expect(museCommand('d'), [2, 0x64, 0x0a]);
    expect(museCommand('p21'), [4, 0x70, 0x32, 0x31, 0x0a]);
  });

  test('decodes the counter and 12 samples into microvolts', () {
    final raw = [2048, 4095, 0, 2049, 2047, 3000, 1000, 2048, 2048, 2048, 2048, 2048];
    final decoded = decodeMuseEegPacket(packet(513, raw));

    expect(decoded.counter, 513);
    expect(decoded.microvolts, hasLength(12));
    expect(decoded.microvolts[0], 0); // 2048 is the middle: zero microvolts
    expect(decoded.microvolts[1], closeTo(999.51, 0.01)); // the top of the range
    expect(decoded.microvolts[2], -1000); // the bottom
    expect(decoded.microvolts[3], closeTo(0.488, 0.001)); // one unit up
  });

  test('refuses packets of the wrong size', () {
    expect(() => decodeMuseEegPacket(Uint8List(19)), throwsFormatException);
  });

  test('puts the four channels of one counter back together', () {
    final assembler = MusePacketAssembler(4);
    final p = MusePacket(7, List.filled(12, 1.0));

    expect(assembler.add(0, p), isNull);
    expect(assembler.add(2, p), isNull);
    expect(assembler.add(1, p), isNull);
    final complete = assembler.add(3, p);

    expect(complete, hasLength(4));
    expect(assembler.dropped, 0);
  });

  test('counts packets that never got complete', () {
    final assembler = MusePacketAssembler(4);
    for (var counter = 0; counter < 20; counter++) {
      assembler.add(0, MusePacket(counter, List.filled(12, 0.0))); // only one channel ever arrives
    }
    expect(assembler.dropped, 12);
  });
}
