import 'expression.dart';

/// The SQL of a value assigned to a JSON path in a MySQL update (see
/// `QueryMySqlGrammar.compileJsonUpdateColumn`).
class JsonExpression extends QueryExpression {
  /// Creates the expression for [value]; see [getJsonBindingParameter].
  JsonExpression(dynamic value) : super(getJsonBindingParameter(value));

  /// Returns the SQL for [value]: `true` or `false` for a boolean, the
  /// number itself for an int or double, and the placeholder `?` for any
  /// other object. Throws for null.
  static getJsonBindingParameter(dynamic value) {
    if (value is bool) {
      return value ? 'true' : 'false';
    } else if (value is int) {
      return value;
    } else if (value is double) {
      return value;
    } else if (value is String) {
      return '?';
    } else if (value is Object) {
      return '?';
    } else if (value is List) {
      return '?';
    }

    throw Exception('JSON value is of illegal type: $value');
  }
}
