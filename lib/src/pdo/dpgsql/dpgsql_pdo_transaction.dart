import 'package:dpgsql/dpgsql.dart';
import 'package:eloquent/eloquent.dart';

import 'dpgsql_driver_access.dart';
import 'dpgsql_pdo.dart';

class DpgsqlPDOTransaction extends PDOTransactionContext {
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
  DriverAccess driverAccess() =>
      DpgsqlDriverAccess.forConnection(connection);

  @override
  Future<int> execute(String statement, [int? timeoutInSeconds]) async {
    final timeout = Duration(
      seconds: timeoutInSeconds ?? DpgsqlPDO.defaultTimeoutInSeconds,
    );
    final command = connection.createCommand(statement);
    return DpgsqlPDO.runWithTimeout(
        connection, () => command.executeNonQuery(), timeout);
  }

  @override
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]) async {
    final timeout = Duration(
      seconds: timeoutInSeconds ?? DpgsqlPDO.defaultTimeoutInSeconds,
    );
    return DpgsqlPDO.runQuery(connection, query, params, timeout);
  }

  @override
  Stream<Map<String, dynamic>> queryStream(String query,
      [dynamic params, int? fetchSize]) async* {
    // Streams over the transaction's live connection; the connection is owned
    // by the surrounding transaction, so it is not closed here.
    final reader = await connection.executeReader(
      query,
      parameters: DpgsqlPDO.parametersFromBindings(params),
    );
    try {
      while (await reader.read()) {
        yield reader.toMap();
      }
    } finally {
      await reader.close();
    }
  }
}
