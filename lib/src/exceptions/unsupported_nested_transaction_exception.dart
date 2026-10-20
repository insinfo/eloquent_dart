/// Thrown when `transaction()` is called inside another transaction and the
/// current driver context cannot create a SAVEPOINT.
///
/// eloquent never opens a second, independent physical transaction in that
/// situation: pretending the inner block is isolated would be unsafe.
class UnsupportedNestedTransactionException implements Exception {
  final String message;

  UnsupportedNestedTransactionException(
      [this.message =
          'Nested transactions are not supported by the current database driver.']);

  @override
  String toString() => 'UnsupportedNestedTransactionException: $message';
}
