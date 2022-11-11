import '../eloquent.dart';

mixin DetectsLostConnections {
  /**
     * Determine if the given exception was caused by a lost connection.
     *
     * @param  \Exception  $e
     * @return bool
     */
  bool causedByLostConnection(Exception e) {
    var message = '$e';

    return Utils.string_contains(message, [
      'server has gone away',
      'no connection to the server',
      'Lost connection',
      'is dead or not enabled',
      'Error while sending',
    ]);
  }
}
