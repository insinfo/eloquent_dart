/// Thrown by `sole()`, `soleValue()` and `firstOrFail()` when the query
/// returns no row.
class RecordsNotFoundException implements Exception {
  RecordsNotFoundException([this.message = 'No records found.']);

  final String message;

  @override
  String toString() => 'RecordsNotFoundException: $message';
}

/// Thrown by `sole()` and `soleValue()` when the query returns more than one
/// row.
class MultipleRecordsFoundException implements Exception {
  MultipleRecordsFoundException(this.count);

  /// How many rows were seen (at least 2: `sole()` stops at two).
  final int count;

  @override
  String toString() =>
      'MultipleRecordsFoundException: $count records were found.';
}
