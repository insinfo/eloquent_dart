import 'package:eloquent/eloquent.dart';

/// base_query_grammar.dart BaseGrammar
abstract class BaseGrammar {
  ///
  /// The grammar table prefix.
  ///
  /// @var string
  ///
  String tablePrefix = '';

  ///
  /// Wrap an array of values.
  ///
  /// @param  array  $values
  /// @return array
  ///
  List wrapArray(List values) {
    return Utils.array_map(wrap, values);
  }

  ///
  /// Wrap a table in keyword identifiers.
  ///
  /// @param  string|\Illuminate\Database\Query\Expression  $table
  /// @return string
  ///
  dynamic wrapTable(dynamic table) {
    if (isExpression(table)) {
      return getValue(table as QueryExpression);
    }

    return wrap(tablePrefix + table, true);
  }

  ///
  /// Wrap a value in keyword identifiers.
  ///
  /// @param  String |\Illuminate\Database\Query\Expression  $value
  /// @param  bool    $prefixAlias
  /// @return string
  ///
  String wrap(dynamic value, [bool prefixAlias = false]) {
    if (isExpression(value)) {
      return getValue(value);
    }

    // If the value being wrapped has a column alias we will need to separate out
    // the pieces so we can wrap each of the segments of the expression on it
    // own, and then joins them both back together with the "as" connector.
    if (Utils.strpos(Utils.strtolower(value), ' as ') != false) {
      var segments = Utils.explode(' ', value);

      if (prefixAlias) {
        segments[2] = tablePrefix + segments[2];
      }

      return wrap(segments[0]) + ' as ' + wrapValue(segments[2]);
    }

    var wrapped = [];

    var segments = Utils.explode('.', value);

    // If the value is not an aliased table expression, we'll just wrap it like
    // normal, so if there is more than one segment, we will wrap the first
    // segments as if it was a table and the rest as just regular values.
    for (var key = 0; key < segments.length; key++) {
      var segment = segments[key];
      if (key == 0 && Utils.count(segments) > 1) {
        wrapped.add(wrapTable(segment));
      } else {
        wrapped.add(wrapValue(segment));
      }
    }

    return Utils.implode('.', wrapped);
  }

  ///
  /// Wrap a single string in keyword identifiers.
  ///
  /// @param  string  $value
  /// @return string
  ///
  String wrapValue(String value) {
    if (value == '*') {
      return value;
    }

    return '"' + Utils.str_replace('"', '""', value) + '"';
  }

  ///
  /// Convert an array of column names into a delimited string.
  ///
  /// @param  array   $columns
  /// @return string
  ///
  String columnize(List<String> columns) {
    return Utils.implode(', ', Utils.array_map(wrap, columns));
  }

  ///
  /// Create query parameter place-holders for an array.
  ///
  /// @param  array   $values
  /// @return string
  ///
  String parameterize(List values) {
    return Utils.implode(', ', Utils.array_map(parameter, values));
  }

  ///
  /// Get the appropriate query parameter place-holder for a value.
  ///
  /// @param  mixed   $value
  /// @return string
  ///
  String parameter(dynamic value) {
    return isExpression(value) ? getValue(value) : '?';
  }

  ///
  /// Get the value of a raw expression.
  ///
  /// [expression]  \Illuminate\Database\Query\Expression
  ///  Return `String`
  ///
  String getValue(QueryExpression expression) {
    return expression.getValue();
  }

  ///
  /// Determine if the given value is a raw expression.
  ///
  /// @param  mixed  $value
  /// @return bool
  ///
  bool isExpression(dynamic value) {
    return value is QueryExpression;
  }

  ///
  /// Get the format for database stored dates.
  ///
  /// @return string
  ///
  String getDateFormat() {
    // return 'Y-m-d H:i:s';
    return 'yyyy-MM-dd HH:mm:ss';
  }

  ///
  /// Get the grammar's table prefix.
  ///
  /// @return string
  ///
  String getTablePrefix() {
    return tablePrefix;
  }

  ///
  /// Set the grammar's table prefix.
  ///
  /// @param  string  $prefix
  /// @return $this
  ///
  dynamic setTablePrefix(String prefix) {
    tablePrefix = prefix;

    return this;
  }
}
