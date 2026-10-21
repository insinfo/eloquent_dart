import 'dart:convert';

/// A page of `cursorPaginate`: keyset pagination on the order columns of the
/// query, without OFFSET and without a count query.
///
/// [nextCursor] and [previousCursor] are opaque strings to send back as the
/// `cursor` of the next request (`null`: there is no such page).
final class CursorPage {
  const CursorPage(
      {required this.items,
      required this.perPage,
      this.nextCursor,
      this.previousCursor});

  final List<Map<String, dynamic>> items;
  final int perPage;
  final String? nextCursor;
  final String? previousCursor;

  bool get hasMorePages => nextCursor != null;
  bool get onFirstPage => previousCursor == null;

  /// Laravel's JSON shape: `data`, `per_page`, `next_cursor`, `prev_cursor`.
  Map<String, dynamic> toMap() => {
        'data': items,
        'per_page': perPage,
        'next_cursor': nextCursor,
        'prev_cursor': previousCursor,
      };
}

/// The position encoded in a cursor: the values of the order columns of the
/// row at the edge of a page and the direction to read from it.
///
/// The values are only ever bound as parameters; the column names in a
/// decoded cursor are never used as SQL (the query's own order columns are).
final class PageCursor {
  const PageCursor(this.values, {required this.pointsToNextItems});

  /// Order column (as written in `orderBy`) -> value of the edge row.
  final Map<String, Object?> values;

  /// `true`: the rows after the edge row; `false`: the rows before it.
  final bool pointsToNextItems;

  String encode() {
    final json = jsonEncode({
      'v': values.map((key, value) => MapEntry(key, _encodeValue(value))),
      'n': pointsToNextItems,
    });
    return base64Url.encode(utf8.encode(json)).replaceAll('=', '');
  }

  /// Throws [FormatException] for a cursor that was not made by [encode].
  static PageCursor decode(String cursor) {
    try {
      final padded = cursor.padRight((cursor.length + 3) ~/ 4 * 4, '=');
      final map = jsonDecode(utf8.decode(base64Url.decode(padded)));
      final values = (map as Map)['v'] as Map;
      final next = map['n'] as bool;
      return PageCursor(
          values.map((key, value) => MapEntry(key as String, _decodeValue(value))),
          pointsToNextItems: next);
    } catch (_) {
      throw FormatException('Invalid pagination cursor.', cursor);
    }
  }

  /// The value of the order column [column]; throws [FormatException] when
  /// the cursor has none (a cursor of another query).
  Object? valueOf(String column) {
    if (!values.containsKey(column)) {
      throw FormatException(
          'The pagination cursor has no value for the order column "$column".');
    }
    return values[column];
  }

  static Object? _encodeValue(Object? value) {
    if (value == null || value is String || value is bool || value is num) {
      return value;
    }
    if (value is DateTime) return {r'$dt': value.toIso8601String()};
    if (value is BigInt) return {r'$bi': value.toString()};
    throw ArgumentError.value(value, 'value',
        'Unsupported order column value for a cursor (${value.runtimeType}).');
  }

  static Object? _decodeValue(Object? value) {
    if (value is Map) {
      if (value[r'$dt'] is String) return DateTime.parse(value[r'$dt']);
      if (value[r'$bi'] is String) return BigInt.parse(value[r'$bi']);
      throw const FormatException('Invalid pagination cursor value.');
    }
    return value;
  }
}
