import 'pdo_config.dart';
import 'pdo_interface.dart';
import 'pdo_result.dart';

abstract class PDOExecutionContext {
  late PDOInterface pdoInstance;

  /// Executa uma instrução SQL e retornar o número de linhas afetadas
  Future<int> execute(String statement, [int? timeoutInSeconds]);
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]);

  PDOConfig getConfig();
}
