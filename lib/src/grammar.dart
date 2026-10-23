import 'package:eloquent/eloquent.dart';

/// Identifier quoting and placeholders shared by the query and schema
/// grammars.
abstract class BaseGrammar {
  /// The prefix added to table names.
  String tablePrefix = '';

  /// Wraps each of [values] with [wrap].
  List wrapArray(List values) {
    return Utils.array_map(wrap, values);
  }

  /// Quotes a table name with the [tablePrefix] added (to an alias too); a
  /// [QueryExpression] is used as is.
  String wrapTable(dynamic table) {
    if (table is QueryExpression) {
      return getValue(table);
    }

    return wrap(tablePrefix + table, true);
  }

  /// Quotes a column or table reference: `table.column` becomes
  /// `"table"."column"` and `column as alias` becomes `"column" as "alias"`;
  /// a [QueryExpression] is used as is.
  ///
  /// [prefixAlias] adds the [tablePrefix] to the alias.
  String wrap(dynamic valueP, [bool prefixAlias = false]) {
    if (valueP is QueryExpression) {
      return getValue(valueP);
    }

    // Any value other than a String or a QueryExpression throws here.
    final String value = valueP; // valueP is String ? : valueP.toString();

    // An aliased value (`x as y`) wraps each side and joins them with `as`.
    //
    // The case-insensitive " as " probe avoids allocating a lowercased copy
    // of the whole string on every wrap().
    if (_containsAsKeyword(value)) {
      var segments = Utils.explode(' ', value);
      if (prefixAlias) {
        segments[2] = tablePrefix + segments[2];
      }
      return wrap(segments[0]) + ' as ' + wrapValue(segments[2]);
    }

    // Fast path: no dotted segments -> wrap the single value directly, avoiding
    // the explode/loop/implode allocations for the common case (e.g. "id").
    final dot = value.indexOf('.');
    if (dot == -1) {
      return wrapValue(value);
    }

    var wrapped = <String>[];
    var segments = Utils.explode('.', value);

    // If the value is not an aliased table expression, we'll just wrap it like
    // normal, so if there is more than one segment, we will wrap the first
    // segments as if it was a table and the rest as just regular values.
    for (var key = 0; key < segments.length; key++) {
      final segment = segments[key];
      if (key == 0 && Utils.count(segments) > 1) {
        wrapped.add(wrapTable(segment));
      } else {
        wrapped.add(wrapValue(segment));
      }
    }

    return Utils.implode('.', wrapped);
  }

  /// Case-insensitive scan for a `" as "` alias keyword (space, a/A, s/S,
  /// space) without allocating a lowercased copy of the input.
  static bool _containsAsKeyword(String s) {
    final n = s.length;
    for (var i = 0; i + 4 <= n; i++) {
      if (s.codeUnitAt(i) == 0x20 && // ' '
          (s.codeUnitAt(i + 1) | 0x20) == 0x61 && // 'a'/'A'
          (s.codeUnitAt(i + 2) | 0x20) == 0x73 && // 's'/'S'
          s.codeUnitAt(i + 3) == 0x20) {
        return true;
      }
    }
    return false;
  }

  /// Quotes one identifier with double quotes (`"` doubled inside); `*` is
  /// kept.
  String wrapValue(String value) {
    if (value == '*') {
      return value;
    }

    // Only run the quote-doubling replace when a double-quote is actually
    // present (rare); otherwise wrap directly.
    if (value.contains('"')) {
      return '"' + Utils.str_replace('"', '""', value) + '"';
    }
    return '"$value"';
  }

  /// Wraps [columns] (names or [QueryExpression]s) and joins them with
  /// commas.
  String columnize(List<dynamic> columns) {
    return Utils.implode(', ', Utils.array_map(wrap, columns));
  }

  /// The placeholders of [values], comma-separated: `?, ?, ...`.
  String parameterize(List values) {
    return Utils.implode(', ', Utils.array_map(parameter, values));
  }

  /// The placeholder of [value]: `?`, or the SQL of a [QueryExpression].
  String parameter(dynamic value) {
    return isExpression(value) ? getValue(value) : '?';
  }

  /// The SQL of a raw [expression].
  String getValue(QueryExpression expression) {
    return expression.getValue();
  }

  /// Whether [value] is a raw [QueryExpression].
  bool isExpression(dynamic value) {
    return value is QueryExpression;
  }

  /// The format of the dates sent to the database: `yyyy-MM-dd HH:mm:ss`.
  String getDateFormat() {
    return 'yyyy-MM-dd HH:mm:ss';
  }

  /// [value] as the date string sent for a DateTime binding (with
  /// `datetime_bindings: 'string'`, the default) and written by
  /// `toRawSql()`: [getDateFormat], wall-clock fields, no offset.
  String formatDateTime(DateTime value) =>
      Utils.formatDate(value, getDateFormat());

  /// Returns the [tablePrefix].
  String getTablePrefix() {
    return tablePrefix;
  }

  /// Sets the [tablePrefix] and returns this grammar.
  dynamic setTablePrefix(String prefix) {
    tablePrefix = prefix;

    return this;
  }
}
