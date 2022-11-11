import '../eloquent.dart';

abstract class ConnectionResolverInterface {
  ///
  /// Get a database connection instance.
  ///
  /// @param  string  $name
  /// @return \Illuminate\Database\ConnectionInterface
  ///
  ConnectionInterface connection([String name]);

  ///
  /// Get the default connection name.
  ///
  /// @return string
  ///
  String getDefaultConnection();

  ///
  /// Set the default connection name.
  ///
  /// @param  string  $name
  /// @return void
  ///
  void setDefaultConnection(String name);
}
