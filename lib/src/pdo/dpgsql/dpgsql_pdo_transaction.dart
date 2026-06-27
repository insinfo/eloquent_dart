import 'package:dpgsql/dpgsql.dart';
import 'package:eloquent/eloquent.dart';

import 'dpgsql_pdo.dart';

class DpgsqlPDOTransaction extends PDOExecutionContext {
  DpgsqlPDOTransaction(this.connection, this.transaction, PDOInterface pdo) {
    super.pdoInstance = pdo;
  }

  final DpgsqlConnection connection;
  final DpgsqlTransaction transaction;

  @override
  PDOConfig getConfig() {
    return super.pdoInstance.config;
  }

  @override
  Future<int> execute(String statement, [int? timeoutInSeconds]) async {
    final timeout = Duration(
      seconds: timeoutInSeconds ?? DpgsqlPDO.defaultTimeoutInSeconds,
    );
    final command = connection.createCommand(statement);
    return command.executeNonQuery().timeout(timeout);
  }

  @override
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]) async {
    final timeout = Duration(
      seconds: timeoutInSeconds ?? DpgsqlPDO.defaultTimeoutInSeconds,
    );
    if (DpgsqlPDO.expectsRows(query)) {
      final rows = await connection
          .executeMaps(
            query,
            parameters: DpgsqlPDO.parametersFromBindings(params),
          )
          .timeout(timeout);
      return PDOResults(rows, rows.length);
    }
    final command = connection.createCommand(query);
    DpgsqlPDO.addParametersFromBindings(command, params);
    final affected = await command.executeNonQuery().timeout(timeout);
    return PDOResults([], affected);
  }
}
