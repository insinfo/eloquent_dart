import 'pdo.dart';
import 'pdo_statement.dart';

abstract class PDOExecutionContext {

   late PDO pdoInstance;

  //PDOExecutionContext.init(this.pdoInstance);

  Future<int> execute(String statement);
  Future<PDOStatement> prepareStatement(String query, dynamic params);
  Future<dynamic> executeStatement(PDOStatement statement, [int? fetchMode]);
  Future<dynamic> query(String query, [int? fetchMode]);


  Future<dynamic> queryUnnamed(String query, dynamic params, [int? fetchMode]);
}
