import 'package:eloquent/eloquent.dart';

import 'package:mysql_dart/mysql_dart.dart';
import 'mysql_client_pdo.dart';

class MySqlClientPDOTransaction extends PDOExecutionContext {
  final MySQLConnection transactionContext;

  @override
  PDOConfig getConfig() {
    return super.pdoInstance.config;
  }

  MySqlClientPDOTransaction(this.transactionContext, PDOInterface pdo) {
    super.pdoInstance = pdo;
  }

  Future<int> execute(String statement, [int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = MySqlClientPDO.defaultTimeoutInSeconds;
    }
    final result = await transactionContext.execute(statement);
    return result.affectedRows.toInt();
  }

  /// Prepares and executes an SQL statement without placeholders
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = MySqlClientPDO.defaultTimeoutInSeconds;
    }

    final stmt = await transactionContext.prepare(query);
    final result =
        await stmt.execute(params ?? []); //.timeout(timeoutInSeconds);
    await stmt.deallocate();
    final rows = result.rows.map((row) => row.typedAssoc()).toList();
    final pdoResult = PDOResults(rows, result.affectedRows.toInt());
    return pdoResult;
  }
}
