import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:postgres/postgres.dart';

import '../core/pdo_config.dart';
import '../core/pg_binary_text.dart';
import '../core/pg_uniform_values.dart';

/// `pg_types: 'uniform'` for postgres 3.x: the types without a natural Dart
/// type decode to the server's text (see [PgTypes]), oid and reg* to int.
///
/// postgres 3.x requests every column in binary. For these types it returned
/// its own objects (Time, Interval, Point, IntRange...) or UndecodedBytes,
/// whose `asString` decoded binary bytes as text (garbage for inet, an error
/// for money, timetz, bit and their arrays).
///
/// With any `pg_types`, dates `DateTime` cannot represent are null, as on the
/// other adapters (see [_DateCodec]).
TypeRegistry postgresV3TypeRegistry(PDOConfig config) {
  const dates = _DateCodec();
  const codec = _ServerTextCodec();
  return TypeRegistry(codecs: {
    for (final oid in _dateOids) oid: dates,
    for (final oid in _dateArrayElements.keys) oid: dates,
    if (config.uniformPgTypes) ...{
      for (final oid in _textOids) oid: codec,
      for (final oid in PgBinaryText.arrayElements.keys)
        if (!_dateArrayElements.containsKey(oid)) oid: codec,
      for (final oid in _oidLike) oid: codec,
    },
  });
}

/// A column value postgres 3.x left undecoded (a type it does not know: an
/// enum, an array of a user-defined type...).
Object? postgresV3Value(PDOConfig config, Object? value) {
  if (value is! UndecodedBytes) return value;
  if (!config.uniformPgTypes || !value.isBinary) return value.asString;
  // An enum[] (or another array of a user-defined type): the array literal.
  final literal = PgBinaryText.arrayLiteral(value.bytes, value.encoding);
  if (literal != null) return literal;
  // The binary form of an enum, and of most user-defined types over text,
  // is their text.
  try {
    return value.encoding is Utf8Codec
        ? const Utf8Decoder().convert(value.bytes)
        : value.encoding.decode(value.bytes);
  } on FormatException {
    return value.bytes;
  }
}

/// Rows of a postgres 3.x result, with [postgresV3Value] applied and, with
/// `pg_types: 'uniform'`, arrays as `List<T?>` (postgres 3.x returns some as
/// `CastList`), in the same pass.
List<Map<String, dynamic>> postgresV3Rows(PDOConfig config, Result result) {
  final uniform = config.uniformPgTypes;
  final columns = result.schema.columns;
  final arrays = [
    for (final column in columns) uniform && !isJsonOid(column.typeOid),
  ];
  final rows = <Map<String, dynamic>>[];
  for (final row in result) {
    final map = <String, dynamic>{};
    for (var i = 0; i < row.length; i++) {
      var value = postgresV3Value(config, row[i]);
      if (value is List &&
          value is! TypedData &&
          arrays[i] &&
          !_isTypedList(value)) {
        value = uniformList(value, _identity, retype: true);
      }
      map[columns[i].columnName ?? '[$i]'] = value;
    }
    rows.add(map);
  }
  return rows;
}

Object? _identity(Object? value) => value;

final _typedListTypes = {
  <int?>[].runtimeType,
  <String?>[].runtimeType,
  <double?>[].runtimeType,
  <bool?>[].runtimeType,
  <DateTime?>[].runtimeType,
};

bool _isTypedList(List<Object?> value) =>
    _typedListTypes.contains(value.runtimeType);

const _textOids = [
  PgBinaryText.oidTime,
  PgBinaryText.oidTimetz,
  PgBinaryText.oidInterval,
  PgBinaryText.oidInet,
  PgBinaryText.oidCidr,
  PgBinaryText.oidMacaddr,
  PgBinaryText.oidMacaddr8,
  PgBinaryText.oidMoney,
  PgBinaryText.oidPoint,
  PgBinaryText.oidLseg,
  PgBinaryText.oidPath,
  PgBinaryText.oidBox,
  PgBinaryText.oidPolygon,
  PgBinaryText.oidLine,
  PgBinaryText.oidCircle,
  PgBinaryText.oidBit,
  PgBinaryText.oidVarbit,
  PgBinaryText.oidTsvector,
  PgBinaryText.oidInt4range,
  PgBinaryText.oidInt8range,
  PgBinaryText.oidNumrange,
  PgBinaryText.oidDaterange,
  PgBinaryText.oidTsrange,
  PgBinaryText.oidTstzrange,
];

/// oid and the reg* types (an unsigned 4-byte oid in binary).
const _oidLike = [26, 24, 2202, 2203, 2204, 2205, 2206, 3734, 3769, 4089, 4096];

const _oidDate = 1082;
const _oidTimestamp = 1114;
const _oidTimestamptz = 1184;
const _dateOids = [_oidDate, _oidTimestamp, _oidTimestamptz];

const _dateArrayElements = {
  1182: _oidDate,
  1115: _oidTimestamp,
  1185: _oidTimestamptz,
};

final _epoch2000 = DateTime.utc(2000);

/// The microseconds since 1970 that `DateTime` can represent.
const _maxDateTimeMicros = 8640000000000000000;
const _epoch2000Micros = 946684800000000;

/// `date`, `timestamp` and `timestamptz`, decoded as postgres 3.x does, except
/// for what `DateTime` cannot represent (`infinity`, or a year past its range),
/// which is null. postgres 3.5.7 turned the `infinity` of a `date` into a wrong
/// date, and that of a timestamp into a `RangeError` no caller could catch,
/// which ends the process. A codec replaces the built-in one of its type: what
/// it does not decode would be `UndecodedBytes`.
class _DateCodec implements Codec {
  const _DateCodec();

  /// Parameters keep the package's own encoders.
  @override
  FutureOr<EncodedValue?> encode(TypedValue input, CodecContext context) =>
      null;

  @override
  FutureOr<Object?> decode(EncodedValue input, CodecContext context) {
    final bytes = input.bytes;
    if (bytes == null) return null;
    final oid = input.typeOid!;
    final element = _dateArrayElements[oid];
    if (input.isText) {
      if (element != null) return input;
      return _fromText(context.encoding.decode(bytes));
    }
    if (element != null) return _array(bytes, element);
    return _binary(oid, ByteData.sublistView(bytes));
  }

  static DateTime? _fromMicros(int micros) {
    final sinceEpoch = micros + _epoch2000Micros;
    if (micros.abs() > _maxDateTimeMicros ||
        sinceEpoch.abs() > _maxDateTimeMicros) {
      return null;
    }
    return _epoch2000.add(Duration(microseconds: micros));
  }

  static DateTime? _binary(int oid, ByteData data) {
    if (oid == _oidDate) {
      final days = data.getInt32(0);
      // 100,000,000 days from 1970 is the range of DateTime.
      if (days.abs() > 99000000) return null;
      return _epoch2000.add(Duration(days: days));
    }
    return _fromMicros(data.getInt64(0));
  }

  /// The text protocol, as the package's text decoder does.
  static Object? _fromText(String text) {
    if (text == 'infinity' || text == '-infinity') return null;
    final DateTime raw;
    try {
      raw = DateTime.parse(text);
    } on FormatException {
      return text;
    }
    if (raw.isUtc) return raw;
    return DateTime.utc(raw.year, raw.month, raw.day, raw.hour, raw.minute,
        raw.second, raw.millisecond, raw.microsecond);
  }

  /// A binary array: dimensions, flags, element oid, a length and lower bound
  /// per dimension, then each element with its length (-1 for NULL).
  static List<Object?> _array(Uint8List bytes, int element) {
    final data = ByteData.sublistView(bytes);
    final dimensions = data.getInt32(0);
    if (dimensions == 0) return <DateTime?>[];
    final lengths = [
      for (var d = 0; d < dimensions; d++) data.getInt32(12 + d * 8)
    ];
    var offset = 12 + dimensions * 8;

    List<Object?> read(int depth) {
      if (depth < dimensions - 1) {
        return [
          for (var i = 0; i < lengths[depth]; i++) read(depth + 1),
        ];
      }
      final values = <DateTime?>[];
      for (var i = 0; i < lengths[depth]; i++) {
        final length = data.getInt32(offset);
        offset += 4;
        if (length < 0) {
          values.add(null);
          continue;
        }
        values.add(_binary(element, ByteData.sublistView(bytes, offset)));
        offset += length;
      }
      return values;
    }

    return read(0);
  }
}

class _ServerTextCodec implements Codec {
  const _ServerTextCodec();

  /// Parameters keep the package's own encoders.
  @override
  FutureOr<EncodedValue?> encode(TypedValue input, CodecContext context) =>
      null;

  @override
  FutureOr<Object?> decode(EncodedValue input, CodecContext context) {
    final bytes = input.bytes;
    if (bytes == null) return null;
    final oid = input.typeOid!;
    if (input.isText) {
      final text = context.encoding.decode(bytes);
      if (oid == PgBinaryText.oidMoney) return PgBinaryText.moneyFromText(text);
      return _oidLike.contains(oid) ? int.tryParse(text) ?? text : text;
    }
    if (_oidLike.contains(oid)) return ByteData.sublistView(bytes).getUint32(0);
    return PgBinaryText.scalar(oid, bytes) ??
        PgBinaryText.array(oid, bytes) ??
        input;
  }
}
