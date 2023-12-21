/// class Expression
class QueryExpression {
  ///
  ///  The value of the expression.
  ///
  ///  @var mixed
  ///
  dynamic value;

  ///
  ///  Create a new raw query expression.
  ///
  ///  @param  mixed  $value
  ///  @return void
  ///
  QueryExpression(this.value);

  ///
  ///  Get the value of the expression.
  ///
  ///  @return mixed
  ///
  dynamic getValue() {
    return value;
  }

  ///
  ///  Get the value of the expression.
  ///
  ///  @return string
  ///
  @override
  String toString() {
    return getValue().toString();
  }
}
