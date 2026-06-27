import 'package:eloquent/eloquent.dart';

import 'package:mysql_dart/mysql_dart.dart';
import 'mysql_client_pdo.dart';

class MySqlClientPDOTransaction extends PDOExecutionContext {
  final MySQLConnection transactionContext;

  Duration _timeout([int? timeoutInSeconds]) => Duration(
        seconds: timeoutInSeconds ?? MySqlClientPDO.defaultTimeoutInSeconds,
      );

  Object? _normalizedParams(dynamic params) {
    if (params == null) {
      return null;
    }
    if (params is List && params.isEmpty) {
      return null;
    }
    if (params is Map && params.isEmpty) {
      return null;
    }
    return params;
  }

  PDOResults _toPDOResults(IResultSet result) {
    final rows = <Map<String, dynamic>>[];
    for (final row in result.rows) {
      rows.add(row.typedAssoc());
    }
    return PDOResults(rows, result.affectedRows.toInt());
  }

  @override
  PDOConfig getConfig() {
    return super.pdoInstance.config;
  }

  MySqlClientPDOTransaction(this.transactionContext, PDOInterface pdo) {
    super.pdoInstance = pdo;
  }

  Future<int> execute(String statement, [int? timeoutInSeconds]) async {
    final result = await transactionContext
        .execute(statement)
        .timeout(_timeout(timeoutInSeconds));
    return result.affectedRows.toInt();
  }

  /// Prepares and executes an SQL statement without placeholders
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]) async {
    final result = await transactionContext
        .execute(query, _normalizedParams(params))
        .timeout(_timeout(timeoutInSeconds));
    return _toPDOResults(result);
  }
}
