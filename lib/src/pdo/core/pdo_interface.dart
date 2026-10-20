import 'pdo_config.dart';
import 'pdo_execution_context.dart';
import 'pdo_notification_connection.dart';

abstract class PDOInterface extends PDOExecutionContext {
  Future<PDOInterface> connect();
  Future<T> runInTransaction<T>(Future<T> operation(PDOExecutionContext ctx),
      [int? timeoutInSeconds]);
  Future close();

  @override
  PDOConfig getConfig() {
    return config;
  }

  abstract PDOConfig config;

  /// Whether [openNotificationConnection] is implemented (PostgreSQL
  /// adapters).
  bool get supportsNotifications => false;

  /// Opens a new connection, outside the pool, for `LISTEN`. The caller owns
  /// it; it is normally managed by `PostgresNotificationListener`.
  Future<PDONotificationConnection> openNotificationConnection() {
    throw UnsupportedError(
        'LISTEN/NOTIFY is not supported by this driver adapter.');
  }
}
