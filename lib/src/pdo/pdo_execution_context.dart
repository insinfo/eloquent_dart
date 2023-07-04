import 'pdo.dart';
import 'pdo_statement.dart';

abstract class PDOExecutionContext {

   late PDO pdoInstance;

  //PDOExecutionContext.init(this.pdoInstance);
  
  /// Executa uma instrução SQL e retornar o número de linhas afetadas
  Future<int> execute(String statement,[Duration? timeout]);
  Future<PDOStatement> prepareStatement(String query, dynamic params,[Duration? timeout]);
  Future<dynamic> executeStatement(PDOStatement statement, [int? fetchMode,Duration? timeout]);
  Future<dynamic> query(String query, [int? fetchMode,Duration? timeout]);


  Future<dynamic> queryNamed(String query, dynamic params, [int? fetchMode,Duration? timeout]);
  Future<dynamic> queryUnnamed(String query, dynamic params, [int? fetchMode,Duration? timeout]);
}
