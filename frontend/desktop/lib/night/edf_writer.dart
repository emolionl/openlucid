import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One signal in an EDF file, e.g. "EEG AF7-Fpz" in microvolts at 256 samples per second.
class EdfSignal {
  const EdfSignal({
    required this.label,
    required this.physicalDimension,
    required this.physicalMin,
    required this.physicalMax,
    required this.samplesPerRecord,
    this.transducer = '',
    this.prefiltering = '',
  });

  final String label;
  final String physicalDimension;
  final double physicalMin;
  final double physicalMax;
  final int samplesPerRecord;
  final String transducer;
  final String prefiltering;
}

/// A time-stamped annotation: [onset] seconds after the start, optional [duration] in seconds.
class EdfAnnotation {
  const EdfAnnotation(this.onset, this.text, {this.duration});

  final double onset;
  final double? duration;
  final String text;
}

/// Writes an EDF+C (continuous) file while recording, one data record (normally 1 second) at a time.
///
/// Crash-safe: the header says "-1 records" until [close] writes the real number, so a file cut off by
/// a crash or power loss still holds every complete record; `repairRecordCount` fixes its header.
/// Format: EDF+ (Kemp & Olivan 2003), https://edfplus.info/specs/edfplus.html. Samples are 16-bit
/// little-endian integers, scaled linearly from [physicalMin, physicalMax] to [-32768, 32767].
class EdfWriter {
  EdfWriter._(this._file, this.signals, this.annotationBytesPerRecord, this.recordSeconds);

  static const int digitalMin = -32768;
  static const int digitalMax = 32767;

  final RandomAccessFile _file;
  final List<EdfSignal> signals;
  final int annotationBytesPerRecord;
  final double recordSeconds;
  int _records = 0;

  int get recordsWritten => _records;

  /// Creates [path] and writes the header. Patient and recording identification follow EDF+ and stay
  /// anonymous: no names, no birth dates.
  static Future<EdfWriter> create(
    String path, {
    required List<EdfSignal> signals,
    required DateTime start,
    String equipment = 'OpenLucid',
    double recordSeconds = 1,
    int annotationBytesPerRecord = 120,
  }) async {
    final file = await File(path).open(mode: FileMode.write);
    final writer = EdfWriter._(file, signals, annotationBytesPerRecord, recordSeconds);
    await file.writeFrom(writer._header(start, equipment, -1));
    return writer;
  }

  int get _signalCount => signals.length + 1; // + the "EDF Annotations" signal

  int get headerBytes => 256 * (_signalCount + 1);

  Uint8List _header(DateTime start, String equipment, int records) {
    final out = StringBuffer();
    void field(String value, int width) {
      final ascii = value.replaceAll(RegExp(r'[^\x20-\x7e]'), '_');
      out.write(ascii.length >= width ? ascii.substring(0, width) : ascii.padRight(width));
    }

    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    String two(int n) => n.toString().padLeft(2, '0');
    final startdate = '${two(start.day)}-${months[start.month - 1]}-${start.year}';

    field('0', 8);
    field('X X X X', 80); // patient: code, sex, birthdate, name, all unknown ("X") by design
    field('Startdate $startdate X X ${equipment.replaceAll(' ', '_')}', 80);
    field('${two(start.day)}.${two(start.month)}.${two(start.year % 100)}', 8);
    field('${two(start.hour)}.${two(start.minute)}.${two(start.second)}', 8);
    field('$headerBytes', 8);
    field('EDF+C', 44);
    field('$records', 8);
    field(_number(recordSeconds), 8);
    field('$_signalCount', 4);

    final all = [
      ...signals,
      EdfSignal(
        label: 'EDF Annotations',
        physicalDimension: '',
        physicalMin: -1,
        physicalMax: 1,
        samplesPerRecord: annotationBytesPerRecord ~/ 2,
      ),
    ];
    for (final s in all) {
      field(s.label, 16);
    }
    for (final s in all) {
      field(s.transducer, 80);
    }
    for (final s in all) {
      field(s.physicalDimension, 8);
    }
    for (final s in all) {
      field(_number(s.physicalMin), 8);
    }
    for (final s in all) {
      field(_number(s.physicalMax), 8);
    }
    for (final _ in all) {
      field('$digitalMin', 8);
    }
    for (final _ in all) {
      field('$digitalMax', 8);
    }
    for (final s in all) {
      field(s.prefiltering, 80);
    }
    for (final s in all) {
      field('${s.samplesPerRecord}', 8);
    }
    for (final _ in all) {
      field('', 32);
    }
    return Uint8List.fromList(ascii.encode(out.toString()));
  }

  /// Writes one data record. [samples] has one list per signal, each exactly samplesPerRecord long.
  /// [annotations] are stored in this record's annotation block; they must fit (see [annotationsFit]).
  Future<void> writeRecord(List<List<double>> samples, {List<EdfAnnotation> annotations = const []}) async {
    if (samples.length != signals.length) {
      throw ArgumentError('Expected ${signals.length} signals, got ${samples.length}.');
    }
    final total = signals.fold<int>(0, (n, s) => n + s.samplesPerRecord) * 2 + annotationBytesPerRecord;
    final data = ByteData(total);
    var offset = 0;
    for (var i = 0; i < signals.length; i++) {
      final signal = signals[i];
      final values = samples[i];
      if (values.length != signal.samplesPerRecord) {
        throw ArgumentError('${signal.label}: expected ${signal.samplesPerRecord} samples, got ${values.length}.');
      }
      for (final value in values) {
        data.setInt16(offset, _digital(value, signal), Endian.little);
        offset += 2;
      }
    }
    final tal = _tal(_records * recordSeconds, annotations);
    for (var i = 0; i < tal.length; i++) {
      data.setUint8(offset + i, tal[i]);
    }
    await _file.writeFrom(data.buffer.asUint8List());
    _records++;
  }

  /// True if these annotations fit in one record's annotation block.
  bool annotationsFit(List<EdfAnnotation> annotations) =>
      _talBytes(0, annotations).length <= annotationBytesPerRecord;

  Future<void> flush() => _file.flush();

  /// Writes the real number of records into the header and closes the file.
  Future<void> close() async {
    await _file.setPosition(236);
    await _file.writeFrom(ascii.encode('$_records'.padRight(8)));
    await _file.flush();
    await _file.close();
  }

  int _digital(double value, EdfSignal s) {
    final clipped = value.isNaN ? 0.0 : value.clamp(s.physicalMin, s.physicalMax);
    final ratio = (clipped - s.physicalMin) / (s.physicalMax - s.physicalMin);
    return (digitalMin + ratio * (digitalMax - digitalMin)).round().clamp(digitalMin, digitalMax);
  }

  // Time-stamped Annotation Lists: "+onset\x14\x14\x00" keeps time for the record, then each annotation
  // as "+onset[\x15duration]\x14text\x14\x00". Unused bytes stay zero.
  Uint8List _tal(double recordOnset, List<EdfAnnotation> annotations) {
    final bytes = _talBytes(recordOnset, annotations);
    if (bytes.length > annotationBytesPerRecord) {
      throw ArgumentError('Annotations do not fit in one record (${bytes.length} > $annotationBytesPerRecord bytes).');
    }
    return bytes;
  }

  Uint8List _talBytes(double recordOnset, List<EdfAnnotation> annotations) {
    final out = BytesBuilder();
    out.add(ascii.encode('+${_number(recordOnset)}'));
    out.add([0x14, 0x14, 0x00]);
    for (final a in annotations) {
      out.add(ascii.encode('+${_number(a.onset)}'));
      if (a.duration != null) {
        out.addByte(0x15);
        out.add(ascii.encode(_number(a.duration!)));
      }
      out.addByte(0x14);
      out.add(utf8.encode(a.text));
      out.add([0x14, 0x00]);
    }
    return out.toBytes();
  }

  /// A number as short as possible, without exponent notation (EDF header fields are 8 characters).
  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    var text = value.toStringAsFixed(4);
    while (text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }

  /// Fixes the record count of a file whose recording was cut off (crash, power loss): counts the
  /// complete records after the header and writes that number into it. Returns the count.
  static Future<int> repairRecordCount(String path) async {
    final file = await File(path).open(mode: FileMode.append);
    try {
      await file.setPosition(0);
      final head = await file.read(256);
      final headerBytes = int.parse(ascii.decode(head.sublist(184, 192)).trim());
      final signalCount = int.parse(ascii.decode(head.sublist(252, 256)).trim());
      await file.setPosition(256);
      final signalHeader = await file.read(256 * signalCount);
      var recordBytes = 0;
      final samplesStart = 216 * signalCount;
      for (var i = 0; i < signalCount; i++) {
        final field = signalHeader.sublist(samplesStart + i * 8, samplesStart + i * 8 + 8);
        recordBytes += int.parse(ascii.decode(field).trim()) * 2;
      }
      final length = await file.length();
      final records = (length - headerBytes) ~/ recordBytes;
      await file.setPosition(236);
      await file.writeFrom(ascii.encode('$records'.padRight(8)));
      await file.truncate(headerBytes + records * recordBytes);
      return records;
    } finally {
      await file.close();
    }
  }
}
