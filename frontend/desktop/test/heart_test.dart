import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlucid/app/heart_strap.dart';
import 'package:openlucid/heart/heart_protocol.dart';
import 'package:openlucid/heart/heart_source.dart';
import 'package:openlucid/heart/hrv.dart';

List<Beat> clean(List<double> rr) => [for (final r in rr) Beat(r, clean: true)];

void main() {
  group('Heart Rate Measurement (0x2A37)', () {
    test('8-bit heart rate with two RR intervals, in 1/1024 s', () {
      // flags 0x16: RR present, contact supported and detected; HR 62; RR 1024 and 980 units.
      final s = decodeHeartRateMeasurement([0x16, 62, 0x00, 0x04, 0xD4, 0x03])!;
      expect(s.heartRate, 62);
      expect(s.rrMs, [1000.0, closeTo(957.03, 0.01)]);
      expect(s.sensorContact, isTrue);
    });

    test('16-bit heart rate, energy expended skipped, no RR', () {
      final s = decodeHeartRateMeasurement([0x09, 0x2C, 0x01, 0x10, 0x00])!;
      expect(s.heartRate, 300);
      expect(s.rrMs, isEmpty);
      expect(s.sensorContact, isNull); // contact not supported
    });

    test('contact supported but not detected', () {
      expect(decodeHeartRateMeasurement([0x04, 70])!.sensorContact, isFalse);
    });

    test('malformed notifications give null, a dangling RR byte is ignored', () {
      expect(decodeHeartRateMeasurement([]), isNull);
      expect(decodeHeartRateMeasurement([0x01, 0x2C]), isNull);
      expect(decodeHeartRateMeasurement([0x10, 60, 0x00, 0x04, 0x07])!.rrMs, [1000.0]);
    });
  });

  group('HRV', () {
    test('RMSSD, SDNN and heart rate on a known series', () {
      // Alternating 950/1050: successive differences are all 100 ms, so RMSSD = 100.
      final rr = [for (var i = 0; i < 20; i++) i.isEven ? 950.0 : 1050.0];
      final h = HrvSummary.of(clean(rr));
      expect(h.rmssd, closeTo(100, 1e-9));
      expect(h.heartRate, closeTo(60, 1e-9));
      expect(h.sdnn, closeTo(sqrt(20 * 2500 / 19), 1e-9));
    });

    test('too few clean beats: heart rate yes, HRV no', () {
      final h = HrvSummary.of(clean([1000, 1010, 990]));
      expect(h.heartRate, isNotNull);
      expect(h.rmssd, isNull);
      expect(h.sdnn, isNull);
    });

    test('differences across a rejected beat are not counted', () {
      final beats = [
        ...clean(List.filled(10, 1000)),
        const Beat(2000, clean: false), // a missed beat
        ...clean(List.filled(10, 1000)),
      ];
      final h = HrvSummary.of(beats);
      expect(h.cleanBeats, 20);
      expect(h.rmssd, 0); // without the rule, 1000 -> 2000 -> 1000 would make it huge
    });

    test('the cleaner rejects impossible intervals and sudden jumps', () {
      final c = RrCleaner();
      expect(c.add(1000).clean, isTrue);
      expect(c.add(250).clean, isFalse); // too short to be a beat
      expect(c.add(2100).clean, isFalse); // too long
      expect(c.add(1150).clean, isTrue); // 15% change: fine
      expect(c.add(1500).clean, isFalse); // 30% jump from 1150
      expect(c.add(1100).clean, isTrue);
      expect(c.add(double.nan).clean, isFalse);
    });

    test('after three rejections in a row the cleaner accepts the new rhythm', () {
      final c = RrCleaner();
      c.add(1000);
      expect([c.add(600).clean, c.add(610).clean, c.add(605).clean], [false, false, false]);
      expect(c.add(600).clean, isTrue);
    });

    test('after a reset nothing is compared with the beat before', () {
      final c = RrCleaner()..add(1000);
      c.reset();
      expect(c.add(600).clean, isTrue);
    });
  });

  test('Fake Heart breathes: HRV in a plausible range, and a missed beat now and then', () {
    final heart = FakeHeart(realTime: false, seed: 3);
    final cleaner = RrCleaner();
    final beats = [for (var i = 0; i < 600; i++) cleaner.add(heart.nextInterval())];
    final h = HrvSummary.of(beats);
    expect(h.heartRate, inInclusiveRange(55, 65));
    expect(h.rmssd, inInclusiveRange(20, 120));
    expect(beats.where((b) => !b.clean), isNotEmpty);
  });

  test('the strap controller shows live heart rate and HRV, and reports link events', () async {
    final strap = HeartStrap();
    final fake = FakeHeart(realTime: false);
    final events = <HeartLinkEvent>[];
    strap.events.listen(events.add);
    await strap.connectSource(fake);
    for (var i = 0; i < 30; i++) {
      fake.beat();
    }
    await Future<void>.delayed(Duration.zero);
    expect(strap.connected, isTrue);
    expect(strap.heartRate, isNotNull);
    expect(strap.live.rmssd, isNotNull);
    await strap.stop();
    await Future<void>.delayed(Duration.zero);
    expect(events, [HeartLinkEvent.connected, HeartLinkEvent.stopped]);
    expect(strap.heartRate, isNull);
    strap.dispose();
  });
}
