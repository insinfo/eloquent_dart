import '../pdo/core/pdo_interface.dart';

abstract class ConnectorInterface {
  /// Opens a database connection with the settings in [config].
  Future<PDOInterface> connect(Map<String, dynamic> config);
}
