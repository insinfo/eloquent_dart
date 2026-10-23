/// A raw SQL fragment: the grammars write it as is, without quoting it or
/// binding it.
class QueryExpression {
  /// The SQL of the expression.
  dynamic value;

  /// Creates a raw expression with the SQL [value].
  QueryExpression(this.value);

  /// Returns the SQL of the expression.
  dynamic getValue() {
    return value;
  }

  /// Returns the SQL of the expression as a string.
  @override
  String toString() {
    return getValue().toString();
  }
}
