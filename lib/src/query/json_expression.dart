import 'expression.dart';

class JsonExpression extends QueryExpression {
  ///
  /// Create a new raw query expression.
  ///
  /// @param  mixed  $value
  /// @return void
  ///
  JsonExpression(dynamic value) : super(getJsonBindingParameter(value));

  ///
  /// Translate the given value into the appropriate JSON binding parameter.
  ///
  /// @param  mixed  $value
  /// @return string
  ///
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
