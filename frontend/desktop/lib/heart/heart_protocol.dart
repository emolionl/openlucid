/// The standard Bluetooth Heart Rate service, as used by the Polar H10 chest strap (and most other
/// heart-rate straps). Pure functions only, so it can be tested without a strap.
///
/// What OpenLucid reads from it: the heart rate and every beat-to-beat (RR) interval. The same
/// approach as the mybliss-hrv app; Polar's own protocol (PMD, for raw ECG and the strap's
/// accelerometer) is not used.
library;

const String heartRateService = '0000180d-0000-1000-8000-00805f9b34fb';
const String heartRateMeasurement = '00002a37-0000-1000-8000-00805f9b34fb';
const String batteryService = '0000180f-0000-1000-8000-00805f9b34fb';
const String batteryLevel = '00002a19-0000-1000-8000-00805f9b34fb';

/// One notification from the strap: usually one beat, sometimes none or a few.
class HeartSample {
  HeartSample({required this.heartRate, required this.rrMs, this.sensorContact, DateTime? receivedAt})
      : receivedAt = receivedAt ?? DateTime.now();

  /// Beats per minute, as the strap computes it (averaged over a few beats).
  final int heartRate;

  /// Beat-to-beat intervals in milliseconds, oldest first. Exact to 1/1024 s, as sent by the strap.
  final List<double> rrMs;

  /// Whether the strap feels skin: true, false, or null when the strap doesn't say.
  final bool? sensorContact;

  final DateTime receivedAt;
}

/// Decodes a Heart Rate Measurement (0x2A37) notification. Returns null for a malformed one.
///
/// Layout, little-endian:
///   byte 0      flags: bit 0 = heart rate is 16 bits, bits 1-2 = sensor contact,
///               bit 3 = energy expended present, bit 4 = RR intervals present
///   byte 1(-2)  heart rate
///   (2 bytes)   energy expended, if flagged
///   2 bytes ×n  RR intervals, in units of 1/1024 s
HeartSample? decodeHeartRateMeasurement(List<int> bytes, {DateTime? receivedAt}) {
  if (bytes.length < 2) return null;
  final flags = bytes[0];
  final wide = flags & 0x01 != 0;
  final contactSupported = flags & 0x04 != 0;
  final contactDetected = flags & 0x02 != 0;
  final hasEnergy = flags & 0x08 != 0;
  final hasRr = flags & 0x10 != 0;

  var i = 1;
  final int heartRate;
  if (wide) {
    if (bytes.length < 3) return null;
    heartRate = bytes[1] | (bytes[2] << 8);
    i = 3;
  } else {
    heartRate = bytes[1];
    i = 2;
  }
  if (hasEnergy) i += 2;

  final rr = <double>[];
  if (hasRr) {
    while (i + 1 < bytes.length) {
      final units = bytes[i] | (bytes[i + 1] << 8);
      rr.add(units * 1000 / 1024);
      i += 2;
    }
  }
  return HeartSample(
    heartRate: heartRate,
    rrMs: rr,
    sensorContact: contactSupported ? contactDetected : null,
    receivedAt: receivedAt,
  );
}
