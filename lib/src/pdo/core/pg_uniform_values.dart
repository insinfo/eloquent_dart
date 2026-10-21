/// Helpers for `pg_types: 'uniform'` (see `PgTypes`). The drivers decode the
/// uniform types themselves (postgres_fork `DecodingSettings`, dpgsql
/// `Decode Extended Types As Text`, dargres text decoding, a postgres 3.x
/// `TypeRegistry`); these only fix the list type of postgres 3.x arrays.
library;

import 'dart:typed_data';

/// [list] with [convert] applied to its elements (nested lists included).
/// When an element changes, or with [retype], the result is a typed list
/// (`List<String?>`, `List<int?>`...) when the elements share a type.
List<Object?> uniformList(
    List<Object?> list, Object? Function(Object? value) convert,
    {bool retype = false}) {
  var changed = false;
  final elements = <Object?>[];
  for (final element in list) {
    // Uint8List (bytea) is a List<int> too.
    final converted = element is List && element is! TypedData
        ? uniformList(element, convert, retype: retype)
        : (element == null ? null : convert(element));
    if (!identical(converted, element)) changed = true;
    elements.add(converted);
  }
  return changed || retype ? _typed(elements) : list;
}

List<Object?> _typed(List<Object?> elements) {
  final values = elements.where((e) => e != null);
  if (values.isEmpty) return elements;
  if (values.every((e) => e is String))
    return List<String?>.of(elements.cast());
  if (values.every((e) => e is int)) return List<int?>.of(elements.cast());
  if (values.every((e) => e is double))
    return List<double?>.of(elements.cast());
  if (values.every((e) => e is bool)) return List<bool?>.of(elements.cast());
  if (values.every((e) => e is DateTime)) {
    return List<DateTime?>.of(elements.cast());
  }
  return elements;
}

/// json and jsonb: their lists are JSON values, not PostgreSQL arrays.
bool isJsonOid(int oid) => oid == 114 || oid == 3802;
