import 'pdo_execution_context.dart';

/// PDO defines a lightweight, consistent interface for accessing databases
/// provides a data-access abstraction layer
abstract class PDOInterface extends PDOExecutionContext {
  Future<PDOInterface> connect();
  Future<T> runInTransaction<T>(Future<T> operation(PDOExecutionContext ctx),[int? timeoutInSeconds]);
  Future close();
}
