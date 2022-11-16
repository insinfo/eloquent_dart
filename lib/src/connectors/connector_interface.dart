import 'package:eloquent/eloquent.dart';

abstract class ConnectorInterface {
  ///
  /// Establish a database connection.
  ///
  /// @param  array  $config
  /// @return \PDO
  ///
  PDO connect(Map<String, dynamic> config);
}
