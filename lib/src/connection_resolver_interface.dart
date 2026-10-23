import '../eloquent.dart';

abstract class ConnectionResolverInterface {
  /// Returns the connection named [name], or the default connection.
  Future<ConnectionInterface> connection([String name]);

  /// Returns the name of the default connection.
  String getDefaultConnection();

  /// Sets the name of the default connection.
  void setDefaultConnection(String name);
}
