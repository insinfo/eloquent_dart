import '../eloquent.dart';

mixin DetectsLostConnections {
  ///
  /// Determine if the given exception was caused by a lost connection.
  ///
  /// @param  \Exception  $e
  /// @return bool
  ///
  bool causedByLostConnection(Exception e) {
    final message = '$e';
    //TODO revise isso para outros cenários
    final isR = Utils.string_contains(message, [
      '57P',//for posgresql restart
      // 'server has gone away',
      // 'no connection to the server',
      // 'Lost connection',
      // 'is dead or not enabled',
      // 'Error while sending',
    ]);
    //print('causedByLostConnection $isR');
    return isR;
  }
}
