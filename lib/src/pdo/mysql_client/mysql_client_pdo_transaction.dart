
import 'package:eloquent/src/pdo/core/pdo_execution_context.dart';
import 'package:eloquent/src/pdo/core/pdo_interface.dart';
import 'package:eloquent/src/pdo/core/pdo_result.dart';
import 'package:mysql_client/mysql_client.dart';
import 'mysql_client_pdo.dart';

class MySqlClientPDOTransaction extends PDOExecutionContext {
  final MySQLConnection transactionContext;

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
    final result = await stmt.execute(params ?? []); //.timeout(timeoutInSeconds);
    await stmt.deallocate();
    final rows = result.rows.map((row) => row.typedAssoc()).toList();
    final pdoResult = PDOResults(rows, result.affectedRows.toInt());
    return pdoResult;
  }
}
