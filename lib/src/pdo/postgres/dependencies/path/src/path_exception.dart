
/// An exception class that's thrown when a path operation is unable to be
/// computed accurately.
class PathException implements Exception {
  String message;

  PathException(this.message);

  @override
  String toString() => 'PathException: $message';
}
