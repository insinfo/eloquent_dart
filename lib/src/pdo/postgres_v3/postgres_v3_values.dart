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
TypeRegistry? postgresV3TypeRegistry(PDOConfig config) {
  if (!config.uniformPgTypes) return null;
  const codec = _ServerTextCodec();
  return TypeRegistry(codecs: {
    for (final oid in _textOids) oid: codec,
    for (final oid in PgBinaryText.arrayElements.keys) oid: codec,
    for (final oid in _oidLike) oid: codec,
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
