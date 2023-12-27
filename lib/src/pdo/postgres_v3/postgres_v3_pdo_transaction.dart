import 'package:eloquent/src/pdo/core/pdo_execution_context.dart';
import 'package:eloquent/src/pdo/core/pdo_interface.dart';
import 'package:eloquent/src/pdo/core/pdo_result.dart';
import 'package:postgres/postgres.dart';
import 'postgres_v3_pdo.dart';

class PostgresV3PDOTransaction extends PDOExecutionContext {
  final TxSession transactionContext;

  PostgresV3PDOTransaction(this.transactionContext, PDOInterface pdo) {
    super.pdoInstance = pdo;
  }

  Future<int> execute(String statement, [int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = PostgresV3PDO.defaultTimeoutInSeconds;
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
      timeoutInSeconds = PostgresV3PDO.defaultTimeoutInSeconds;
    }

    final rs = await transactionContext.execute(
      Sql.indexed(query, substitution: '?'),
      parameters: params,
      timeout: Duration(seconds: timeoutInSeconds),
    );

    final rows = rs.map((row) => row.toColumnMap()).toList();
    final maps = <Map<String, dynamic>>[];
    if (rows.isNotEmpty) {
      for (final row in rows) {
        final map = <String, dynamic>{};
        for (final col in row.entries) {
          final key = col.key;
          final value =
              col.value is UndecodedBytes ? col.value.asString : col.value;
          map.addAll({key: value});
        }
        maps.add(map);
      }
    }

    final pdoResult = PDOResults(maps, rs.affectedRows);
    return pdoResult;
  }
}
