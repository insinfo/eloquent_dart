import 'expression.dart';

/// The SQL of a value assigned to a JSON path in a MySQL update (see
/// `QueryMySqlGrammar.compileJsonUpdateColumn`).
class JsonExpression extends QueryExpression {
  /// Creates the expression for [value]; see [getJsonBindingParameter].
  JsonExpression(dynamic value) : super(getJsonBindingParameter(value));

  /// Whether [value] is written into the SQL instead of bound: a boolean or
  /// a number. `QueryMySqlGrammar.prepareBindingsForUpdate` leaves these
  /// values out of the bindings.
  static bool isInlined(dynamic value) => value is bool || value is num;

  /// Returns the SQL for [value]: `true` or `false` for a boolean, the
  /// number itself for an int or double, and the placeholder `?` for
  /// anything else (null included). Throws [ArgumentError] for NaN and the
  /// infinities, which have no SQL literal.
  static getJsonBindingParameter(dynamic value) {
    if (value is bool) {
      return value ? 'true' : 'false';
    } else if (value is num) {
      if (value is double && !value.isFinite) {
        throw ArgumentError.value(
            value, 'value', 'JSON has no NaN or infinity.');
      }
      return value;
    }
    return '?';
  }
}
