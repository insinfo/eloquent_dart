import 'pdo.dart';
import 'pdo_statement.dart';

abstract class PDOExecutionContext {
  late PDO pdoInstance;

  //PDOExecutionContext.init(this.pdoInstance);

  /// Executa uma instrução SQL e retornar o número de linhas afetadas
  Future<int> execute(String statement);
  Future<PDOStatement> prepareStatement(String query, dynamic params);
  Future<dynamic> executeStatement(PDOStatement statement, [int? fetchMode]);
  Future<dynamic> query(String query, [dynamic params, int? fetchMode]);

 // Future<dynamic> queryNamed(String query, dynamic params, [int? fetchMode]);
  // Future<dynamic> queryUnnamed(String query, dynamic params, [int? fetchMode,Duration? timeout]);
}
