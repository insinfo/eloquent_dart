import '../eloquent.dart';

mixin DetectsLostConnections {
  ///
  /// Determine if the given exception was caused by a lost connection.
  ///
  /// @param  \Exception  $e
  /// @return bool
  ///
  bool causedByLostConnection(dynamic e) {
    final message = '$e';
    //TODO revise isso para outros cenários
    final isR = Utils.string_contains(message, [
      '57P',//for posgresql restart
       "Can't create a connection",
       'Connection is closed',  
       'connection is not open',
    ]);
    
    return isR;
  }
}
