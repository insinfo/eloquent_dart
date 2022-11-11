class LogicException implements Exception {
  String cause;
  LogicException([this.cause = 'LogicException']);
}
