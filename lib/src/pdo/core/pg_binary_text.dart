import 'dart:convert';
import 'dart:typed_data';

/// The binary form of PostgreSQL types without a natural Dart type, as the
/// text the server prints for them (the type's output function): geometric
/// types, bit strings, tsvector, ranges, and arrays of these or of
/// user-defined types (enum[]). Also formats time, timetz, interval and
/// float8 values the way the server does.
///
/// The same file is in postgres_fork (`lib/src/pg_binary_text.dart`).
abstract final class PgBinaryText {
  static const oidBool = 16;
  static const oidInt2 = 21;
  static const oidInt4 = 23;
  static const oidInt8 = 20;
  static const oidText = 25;
  static const oidFloat8 = 701;
  static const oidNumeric = 1700;
  static const oidDate = 1082;
  static const oidTime = 1083;
  static const oidTimestamp = 1114;
  static const oidTimestamptz = 1184;
  static const oidInterval = 1186;
  static const oidTimetz = 1266;
  static const oidInet = 869;
  static const oidCidr = 650;
  static const oidMacaddr = 829;
  static const oidMacaddr8 = 774;
  static const oidMoney = 790;
  static const oidPoint = 600;
  static const oidLseg = 601;
  static const oidPath = 602;
  static const oidBox = 603;
  static const oidPolygon = 604;
  static const oidLine = 628;
  static const oidCircle = 718;
  static const oidBit = 1560;
  static const oidVarbit = 1562;
  static const oidTsvector = 3614;
  static const oidInt4range = 3904;
  static const oidNumrange = 3906;
  static const oidTsrange = 3908;
  static const oidTstzrange = 3910;
  static const oidDaterange = 3912;
  static const oidInt8range = 3926;

  /// Array type OID → element type OID, for the element types [scalar]
  /// formats (and numeric).
  static const arrayElements = <int, int>{
    1183: oidTime,
    1270: oidTimetz,
    1187: oidInterval,
    1041: oidInet,
    651: oidCidr,
    1040: oidMacaddr,
    775: oidMacaddr8,
    791: oidMoney,
    1017: oidPoint,
    1018: oidLseg,
    1019: oidPath,
    1020: oidBox,
    1027: oidPolygon,
    629: oidLine,
    719: oidCircle,
    1561: oidBit,
    1563: oidVarbit,
    3643: oidTsvector,
    3905: oidInt4range,
    3927: oidInt8range,
    3907: oidNumrange,
    3913: oidDaterange,
    3909: oidTsrange,
    3911: oidTstzrange,
    1231: oidNumeric,
  };

  /// Whether [scalar] or [array] formats [oid] (a cheap check before them).
  static bool formats(int oid) =>
      _scalarOids.contains(oid) ||
      _rangeElements.containsKey(oid) ||
      arrayElements.containsKey(oid);

  static const _scalarOids = {
    oidTime, oidTimetz, oidInterval, oidInet, oidCidr, oidMacaddr, //
    oidMacaddr8, oidMoney, oidNumeric, oidPoint, oidLine, oidLseg, oidBox,
    oidPath, oidPolygon, oidCircle, oidBit, oidVarbit, oidTsvector, oidDate,
    oidTimestamp, oidTimestamptz, oidInt2, oidInt4, oidInt8,
  };

  static const _rangeElements = <int, int>{
    oidInt4range: oidInt4,
    oidInt8range: oidInt8,
    oidNumrange: oidNumeric,
    oidDaterange: oidDate,
    oidTsrange: oidTimestamp,
    oidTstzrange: oidTimestamptz,
  };

  /// The server text of the binary value [bytes] of type [oid], or `null`
  /// when [oid] is not one of the types formatted here.
  ///
  /// `money` is the decimal amount with 2 fraction digits (`'12.34'`), not
  /// the lc_monetary text; a `tstzrange` bound is printed in UTC (`+00`):
  /// the server prints it in the session time zone.
  static String? scalar(int oid, Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    switch (oid) {
      case oidTime:
        return time(data.getInt64(0));
      case oidTimetz:
        return timetz(data.getInt64(0), data.getInt32(8));
      case oidInterval:
        return interval(data.getInt32(12), data.getInt32(8), data.getInt64(0));
      case oidInet:
      case oidCidr:
        return inet(bytes);
      case oidMacaddr:
      case oidMacaddr8:
        return [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')]
            .join(':');
      case oidMoney:
        return money(data.getInt64(0));
      case oidNumeric:
        return numeric(bytes);
      case oidPoint:
        return point(data.getFloat64(0), data.getFloat64(8));
      case oidLine:
        return '{${float8(data.getFloat64(0))},${float8(data.getFloat64(8))},'
            '${float8(data.getFloat64(16))}}';
      case oidLseg:
        return '[${_points(data, 0, 2)}]';
      case oidBox:
        return _points(data, 0, 2);
      case oidPath:
        final closed = bytes[0] != 0;
        final points = _points(data, 5, data.getInt32(1));
        return closed ? '($points)' : '[$points]';
      case oidPolygon:
        return '(${_points(data, 4, data.getInt32(0))})';
      case oidCircle:
        return '<${point(data.getFloat64(0), data.getFloat64(8))},'
            '${float8(data.getFloat64(16))}>';
      case oidBit:
      case oidVarbit:
        return _bits(data);
      case oidTsvector:
        return _tsvector(bytes);
      case oidDate:
        return date(data.getInt32(0));
      case oidTimestamp:
        return timestamp(data.getInt64(0));
      case oidTimestamptz:
        final text = timestamp(data.getInt64(0));
        return text.endsWith('infinity') ? text : _withUtcOffset(text);
      case oidInt2:
        return '${data.getInt16(0)}';
      case oidInt4:
        return '${data.getInt32(0)}';
      case oidInt8:
        return '${data.getInt64(0)}';
    }
    final element = _rangeElements[oid];
    if (element != null) return _range(bytes, element);
    return null;
  }

  /// The binary array [bytes] of type [oid] (an [arrayElements] key) as a
  /// list of element texts, nested by dimension, or `null` for other types.
  static List<Object?>? array(int oid, Uint8List bytes) {
    final elementOid = arrayElements[oid];
    if (elementOid == null) return null;
    final parsed = _parseArray(bytes);
    if (parsed == null) return null;
    return parsed.nested<String?>((value) => value == null
        ? null
        : scalar(parsed.elementOid, value) ?? utf8.decode(value));
  }

  /// A binary array whose element type is not known here (an enum[] or
  /// another array of a user-defined type) as the server's array literal
  /// (`'{ok,sad}'`), the elements decoded with [encoding]: the binary form
  /// of an enum, and of a domain over text, is its text. `null` when
  /// [bytes] is not a well-formed binary array.
  static String? arrayLiteral(Uint8List bytes, Encoding encoding) {
    final parsed = _parseArray(bytes);
    if (parsed == null) return null;
    try {
      return parsed.literal((value) =>
          scalar(parsed.elementOid, value) ?? encoding.decode(value));
    } on FormatException {
      return null;
    }
  }

  /// `HH:MM:SS[.ffffff]`, the fraction without trailing zeros.
  static String time(int microseconds) {
    final hours = microseconds ~/ Duration.microsecondsPerHour;
    var rest = microseconds - hours * Duration.microsecondsPerHour;
    final minutes = rest ~/ Duration.microsecondsPerMinute;
    rest -= minutes * Duration.microsecondsPerMinute;
    return '${_two(hours)}:${_two(minutes)}:${_seconds(rest)}';
  }

  /// [microseconds] since midnight and the zone in seconds west of UTC
  /// (the binary form): `10:20:30+03`, `10:20:30+05:30`.
  static String timetz(int microseconds, int zoneSecondsWest) =>
      '${time(microseconds)}${utcOffset(-zoneSecondsWest)}';

  /// `+03`, `-03:30`, `+05:30:15` for an offset east of UTC in seconds.
  static String utcOffset(int secondsEast) {
    final sign = secondsEast < 0 ? '-' : '+';
    final abs = secondsEast.abs();
    final hours = abs ~/ 3600;
    final minutes = (abs % 3600) ~/ 60;
    final seconds = abs % 60;
    final text = StringBuffer('$sign${_two(hours)}');
    if (minutes != 0 || seconds != 0) text.write(':${_two(minutes)}');
    if (seconds != 0) text.write(':${_two(seconds)}');
    return text.toString();
  }

  /// PostgreSQL's default interval output (IntervalStyle `postgres`):
  /// `1 year 2 mons 3 days 04:05:06.789`, `-1 days +02:00:00`, `00:00:00`.
  static String interval(int months, int days, int microseconds) {
    final text = StringBuffer();
    var isZero = true;
    var isBefore = false;
    void part(int value, String unit) {
      if (value == 0) return;
      text
        ..write(isZero ? '' : ' ')
        ..write(isBefore && value > 0 ? '+' : '')
        ..write('$value $unit${value != 1 ? 's' : ''}');
      isBefore = value < 0;
      isZero = false;
    }

    part(months ~/ 12, 'year');
    part(months.remainder(12), 'mon');
    part(days, 'day');
    if (isZero || microseconds != 0) {
      final hours = microseconds ~/ Duration.microsecondsPerHour;
      var rest = microseconds - hours * Duration.microsecondsPerHour;
      final minutes = rest ~/ Duration.microsecondsPerMinute;
      rest -= minutes * Duration.microsecondsPerMinute;
      final minus = microseconds < 0;
      text
        ..write(isZero ? '' : ' ')
        ..write(minus ? '-' : (isBefore ? '+' : ''))
        ..write('${_two(hours.abs())}:${_two(minutes.abs())}:')
        ..write(_seconds(rest.abs()));
    }
    return text.toString();
  }

  /// A float8 as PostgreSQL prints it (shortest exact digits; exponent
  /// notation below 1e-4 and from 1e15): `1`, `1.5`, `1e+15`, `1e-05`.
  static String float8(double value) {
    if (value.isNaN) return 'NaN';
    if (value == double.infinity) return 'Infinity';
    if (value == double.negativeInfinity) return '-Infinity';
    if (value == 0) return value.isNegative ? '-0' : '0';
    final exponential = value.abs().toStringAsExponential();
    final e = exponential.indexOf('e');
    final digits = exponential.substring(0, e).replaceAll('.', '');
    final exponent = int.parse(exponential.substring(e + 1));
    final sign = value < 0 ? '-' : '';
    if (exponent < -4 || exponent >= 15) {
      final mantissa =
          digits.length == 1 ? digits : '${digits[0]}.${digits.substring(1)}';
      final expSign = exponent < 0 ? '-' : '+';
      return '$sign${mantissa}e$expSign${_two(exponent.abs())}';
    }
    if (exponent < 0) {
      return '${sign}0.${'0' * (-exponent - 1)}$digits';
    }
    if (digits.length <= exponent + 1) {
      return '$sign$digits${'0' * (exponent + 1 - digits.length)}';
    }
    return '$sign${digits.substring(0, exponent + 1)}.'
        '${digits.substring(exponent + 1)}';
  }

  /// `(x,y)`.
  static String point(double x, double y) => '(${float8(x)},${float8(y)})';

  /// The decimal amount of a money value in its smallest unit (2 fraction
  /// digits): `'12.34'`, `'-0.05'`.
  static String money(int cents) {
    final negative = cents < 0;
    final abs = BigInt.from(cents).abs();
    final units = abs ~/ BigInt.from(100);
    final fraction = (abs % BigInt.from(100)).toString().padLeft(2, '0');
    return '${negative ? '-' : ''}$units.$fraction';
  }

  /// The decimal amount of a money value printed by the server
  /// (lc_monetary: `'R$ 1.234,56'`, `'-$0.05'`, `'($0.05)'`, `'12,34 €'`):
  /// `'1234.56'`, `'-0.05'`. The decimal separator is the last `.` or `,`
  /// followed by one or two digits.
  static String moneyFromText(String text) {
    final negative = text.contains('-') || text.trim().startsWith('(');
    var fraction = '';
    var end = text.length;
    final lastSeparator = text.lastIndexOf(RegExp(r'[.,]'));
    if (lastSeparator >= 0 &&
        RegExp(r'^[0-9]{1,2}[^0-9.,]*$')
            .hasMatch(text.substring(lastSeparator + 1))) {
      fraction =
          text.substring(lastSeparator + 1).replaceAll(RegExp(r'[^0-9]'), '');
      end = lastSeparator;
    }
    var units = text.substring(0, end).replaceAll(RegExp(r'[^0-9]'), '');
    units = units.replaceFirst(RegExp(r'^0+(?=.)'), '');
    if (units.isEmpty) units = '0';
    final cents = fraction.padRight(2, '0');
    final zero = RegExp(r'^0*$').hasMatch(units + cents);
    return '${negative && !zero ? '-' : ''}$units.$cents';
  }

  /// The text of a binary numeric (`numeric_out`).
  static String numeric(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final ndigits = data.getInt16(0);
    final weight = data.getInt16(2);
    final sign = data.getUint16(4);
    final dscale = data.getInt16(6);
    if (sign == 0xC000) return 'NaN';
    if (sign == 0xD000) return 'Infinity';
    if (sign == 0xF000) return '-Infinity';
    int digit(int index) =>
        index >= 0 && index < ndigits ? data.getInt16(8 + index * 2) : 0;
    final text = StringBuffer(sign == 0x4000 ? '-' : '');
    if (weight < 0) {
      text.write('0');
    } else {
      for (var i = 0; i <= weight; i++) {
        final group = '${digit(i)}';
        text.write(i == 0 ? group : group.padLeft(4, '0'));
      }
    }
    if (dscale > 0) {
      final fraction = StringBuffer();
      for (var i = weight + 1; fraction.length < dscale; i++) {
        fraction.write('${digit(i)}'.padLeft(4, '0'));
      }
      text
        ..write('.')
        ..write(fraction.toString().substring(0, dscale));
    }
    return text.toString();
  }

  /// `YYYY-MM-DD` (`YYYY-MM-DD BC`, `infinity`) of days since 2000-01-01.
  static String date(int days) {
    if (days == 0x7fffffff) return 'infinity';
    if (days == -0x80000000) return '-infinity';
    final d = DateTime.utc(2000, 1, 1 + days);
    return '${_year(d.year)}-${_two(d.month)}-${_two(d.day)}${_bc(d.year)}';
  }

  /// `YYYY-MM-DD HH:MM:SS[.ffffff]` of microseconds since 2000-01-01.
  static String timestamp(int microseconds) {
    if (microseconds == 0x7fffffffffffffff) return 'infinity';
    if (microseconds == -0x8000000000000000) return '-infinity';
    final day = microseconds >= 0
        ? microseconds ~/ Duration.microsecondsPerDay
        : -((-microseconds + Duration.microsecondsPerDay - 1) ~/
            Duration.microsecondsPerDay);
    final d = DateTime.utc(2000, 1, 1 + day);
    final ofDay = microseconds - day * Duration.microsecondsPerDay;
    return '${_year(d.year)}-${_two(d.month)}-${_two(d.day)} '
        '${time(ofDay)}${_bc(d.year)}';
  }

  /// `IPv4`, `IPv6` (compressed as PostgreSQL does) and `/bits` (always for
  /// cidr, when it is not the full length for inet).
  static String inet(Uint8List bytes) {
    final family = bytes[0];
    final bits = bytes[1];
    final isCidr = bytes[2] != 0;
    final length = bytes[3];
    final address = Uint8List.sublistView(bytes, 4, 4 + length);
    final String text;
    final int maxBits;
    if (family == 2) {
      maxBits = 32;
      text = address.join('.');
    } else {
      maxBits = 128;
      text = _ipv6(address);
    }
    return isCidr || bits != maxBits ? '$text/$bits' : text;
  }

  static String _ipv6(Uint8List address) {
    final words = [
      for (var i = 0; i < 8; i++) (address[i * 2] << 8) | address[i * 2 + 1],
    ];
    var bestBase = -1, bestLen = 0, curBase = -1, curLen = 0;
    for (var i = 0; i < 8; i++) {
      if (words[i] == 0) {
        if (curBase == -1) {
          curBase = i;
          curLen = 1;
        } else {
          curLen++;
        }
      } else if (curBase != -1) {
        if (bestBase == -1 || curLen > bestLen) {
          bestBase = curBase;
          bestLen = curLen;
        }
        curBase = -1;
      }
    }
    if (curBase != -1 && (bestBase == -1 || curLen > bestLen)) {
      bestBase = curBase;
      bestLen = curLen;
    }
    if (bestBase != -1 && bestLen < 2) bestBase = -1;
    final text = StringBuffer();
    for (var i = 0; i < 8; i++) {
      if (bestBase != -1 && i >= bestBase && i < bestBase + bestLen) {
        if (i == bestBase) text.write(':');
        continue;
      }
      if (i != 0) text.write(':');
      if (i == 6 &&
          bestBase == 0 &&
          (bestLen == 6 ||
              (bestLen == 7 && words[7] != 0x0001) ||
              (bestLen == 5 && words[5] == 0xffff))) {
        text.write(address.sublist(12).join('.'));
        return text.toString();
      }
      text.write(words[i].toRadixString(16));
    }
    if (bestBase != -1 && bestBase + bestLen == 8) text.write(':');
    return text.toString();
  }

  static String _points(ByteData data, int offset, int count) => [
        for (var i = 0; i < count; i++)
          point(data.getFloat64(offset + i * 16),
              data.getFloat64(offset + i * 16 + 8)),
      ].join(',');

  static String _bits(ByteData data) {
    final length = data.getInt32(0);
    final text = StringBuffer();
    for (var i = 0; i < length; i++) {
      final byte = data.getUint8(4 + i ~/ 8);
      text.write((byte >> (7 - i % 8)) & 1);
    }
    return text.toString();
  }

  static String _tsvector(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final count = data.getInt32(0);
    var offset = 4;
    final words = <String>[];
    for (var w = 0; w < count; w++) {
      final end = bytes.indexOf(0, offset);
      final lexeme = utf8.decode(bytes.sublist(offset, end));
      offset = end + 1;
      final positions = data.getUint16(offset);
      offset += 2;
      final word = StringBuffer("'")
        ..write(lexeme.replaceAll(r'\', r'\\').replaceAll("'", "''"))
        ..write("'");
      for (var p = 0; p < positions; p++) {
        final entry = data.getUint16(offset);
        offset += 2;
        word
          ..write(p == 0 ? ':' : ',')
          ..write(entry & 0x3fff)
          ..write(const ['', 'C', 'B', 'A'][entry >> 14]);
      }
      words.add(word.toString());
    }
    return words.join(' ');
  }

  static String _range(Uint8List bytes, int elementOid) {
    final data = ByteData.sublistView(bytes);
    final flags = bytes[0];
    if (flags & 0x01 != 0) return 'empty';
    var offset = 1;
    String bound(bool infinite) {
      if (infinite) return '';
      final length = data.getInt32(offset);
      final value =
          Uint8List.sublistView(bytes, offset + 4, offset + 4 + length);
      offset += 4 + length;
      return _quoteRangeBound(scalar(elementOid, value)!);
    }

    final lower = bound(flags & 0x08 != 0);
    final upper = bound(flags & 0x10 != 0);
    return '${flags & 0x02 != 0 ? '[' : '('}$lower,$upper'
        '${flags & 0x04 != 0 ? ']' : ')'}';
  }

  static String _quoteRangeBound(String value) {
    if (value.isNotEmpty && !RegExp(r'[\s"\\()\[\],]').hasMatch(value)) {
      return value;
    }
    return '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }

  static _BinaryArray? _parseArray(Uint8List bytes) {
    if (bytes.length < 12) return null;
    final data = ByteData.sublistView(bytes);
    final dimensions = data.getInt32(0);
    final hasNull = data.getInt32(4);
    if (dimensions < 0 || dimensions > 6 || (hasNull != 0 && hasNull != 1)) {
      return null;
    }
    final elementOid = data.getUint32(8);
    var offset = 12;
    if (bytes.length < offset + dimensions * 8) return null;
    final sizes = <int>[];
    final lowerBounds = <int>[];
    var total = dimensions == 0 ? 0 : 1;
    for (var d = 0; d < dimensions; d++) {
      final size = data.getInt32(offset);
      if (size < 0) return null;
      sizes.add(size);
      lowerBounds.add(data.getInt32(offset + 4));
      total *= size;
      offset += 8;
    }
    final elements = <Uint8List?>[];
    for (var i = 0; i < total; i++) {
      if (offset + 4 > bytes.length) return null;
      final length = data.getInt32(offset);
      offset += 4;
      if (length == -1) {
        elements.add(null);
        continue;
      }
      if (length < 0 || offset + length > bytes.length) return null;
      elements.add(Uint8List.sublistView(bytes, offset, offset + length));
      offset += length;
    }
    if (offset != bytes.length) return null;
    return _BinaryArray(elementOid, sizes, lowerBounds, elements);
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _seconds(int microseconds) {
    final seconds = microseconds ~/ Duration.microsecondsPerSecond;
    final fraction = microseconds % Duration.microsecondsPerSecond;
    if (fraction == 0) return _two(seconds);
    final digits =
        fraction.toString().padLeft(6, '0').replaceFirst(RegExp(r'0+$'), '');
    return '${_two(seconds)}.$digits';
  }

  static String _year(int year) =>
      (year > 0 ? year : 1 - year).toString().padLeft(4, '0');

  static String _bc(int year) => year > 0 ? '' : ' BC';

  static String _withUtcOffset(String timestamp) => timestamp.endsWith(' BC')
      ? '${timestamp.substring(0, timestamp.length - 3)}+00 BC'
      : '$timestamp+00';
}

class _BinaryArray {
  _BinaryArray(this.elementOid, this.sizes, this.lowerBounds, this.elements);

  final int elementOid;
  final List<int> sizes;
  final List<int> lowerBounds;
  final List<Uint8List?> elements;

  /// The elements nested by dimension; the innermost lists are `List<E>`.
  List<Object?> nested<E>(E Function(Uint8List? value) decode) {
    if (sizes.isEmpty) return <E>[];
    var index = 0;
    List<Object?> level(int dimension) => dimension == sizes.length - 1
        ? <E>[
            for (var i = 0; i < sizes[dimension]; i++)
              decode(elements[index++]),
          ]
        : <Object?>[
            for (var i = 0; i < sizes[dimension]; i++) level(dimension + 1),
          ];
    return level(0);
  }

  String literal(String Function(Uint8List value) decode) {
    if (sizes.isEmpty) return '{}';
    var index = 0;
    String level(int dimension) {
      final items = <String>[];
      for (var i = 0; i < sizes[dimension]; i++) {
        if (dimension == sizes.length - 1) {
          final value = elements[index++];
          items.add(value == null ? 'NULL' : _quote(decode(value)));
        } else {
          items.add(level(dimension + 1));
        }
      }
      return '{${items.join(',')}}';
    }

    final bounds = lowerBounds.every((b) => b == 1)
        ? ''
        : '${[
            for (var d = 0; d < sizes.length; d++)
              '[${lowerBounds[d]}:${lowerBounds[d] + sizes[d] - 1}]',
          ].join()}=';
    return '$bounds${level(0)}';
  }

  static String _quote(String value) {
    if (value.isNotEmpty &&
        value.toUpperCase() != 'NULL' &&
        !RegExp(r'[\s"\\{},]').hasMatch(value)) {
      return value;
    }
    return '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }
}
