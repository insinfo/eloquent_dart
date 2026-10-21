import 'package:eloquent/src/pdo/core/pdo_config.dart';
import 'package:eloquent/src/pdo/core/pdo_execution_context.dart';
import 'package:eloquent/src/pdo/core/pdo_interface.dart';
import 'package:eloquent/src/pdo/core/pdo_result.dart';
import 'package:postgres/postgres.dart';
import 'postgres_v3_pdo.dart';
import 'postgres_v3_values.dart';

class PostgresV3PDOTransaction extends PDOTransactionContext {
  final TxSession transactionContext;

  @override
  PDOConfig getConfig() {
    return super.pdoInstance.config;
  }

  PostgresV3PDOTransaction(this.transactionContext, PDOInterface pdo) {
    super.pdoInstance = pdo;
  }

  Future<int> execute(String statement, [int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds =
          (pdoInstance as PostgresV3PDO).queryTimeoutInSeconds;
    }
    final res = await transactionContext.execute(
      statement,
      timeout: Duration(seconds: timeoutInSeconds),
    );
    return res.affectedRows;
  }

  /// Prepares and executes an SQL statement with placeholders
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds =
          (pdoInstance as PostgresV3PDO).queryTimeoutInSeconds;
    }

    final rs = await transactionContext.execute(
      Sql.indexed(query, substitution: '?'),
      parameters: params,
      timeout: Duration(seconds: timeoutInSeconds),
    );

    final pdoResult =
        PDOResults(postgresV3Rows(getConfig(), rs), rs.affectedRows);
    return pdoResult;
  }
}
