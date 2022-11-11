class QueryException implements Exception {
  String sql;
  dynamic bindings;
  dynamic previous;
  QueryException([
    this.sql = 'QueryException',
    this.bindings,
    this.previous,
  ]);
}
