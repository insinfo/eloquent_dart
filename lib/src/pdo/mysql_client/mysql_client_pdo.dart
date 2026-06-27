import 'package:eloquent/src/pdo/core/pdo_config.dart';
import 'package:eloquent/src/pdo/core/pdo_interface.dart';
import 'package:eloquent/src/pdo/core/pdo_result.dart';

import 'package:mysql_dart/mysql_dart.dart';
import 'mysql_client_pdo_transaction.dart';

class MySqlClientPDO extends PDOInterface {
  /// default query Timeout =  30 seconds
  static const defaultTimeoutInSeconds = 30;

  PDOConfig config;

  /// Creates a PDO instance representing a connection to a database
  /// Example
  ///
  ///
  /// Example:  Map<String, dynamic> config = {'host': 'localhost','port':5432,'database':'teste'};
  /// var pdo = new PDO(PDOConfig.fromMap(config));
  /// await pdo.connect();
  ///
  MySqlClientPDO(this.config) {
    super.pdoInstance = this;
  }

  /// CoreConnection
  late dynamic connection;

  Duration _timeout([int? timeoutInSeconds]) => Duration(
        seconds: timeoutInSeconds ?? defaultTimeoutInSeconds,
      );

  Object? _normalizedParams(dynamic params) {
    // Query builder bindings are normalized by Connection.prepareBindings()
    // before reaching this adapter. DateTime values should arrive formatted
    // with the grammar date format, mirroring Laravel/PDO behavior.
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

  //called from postgres_connector.dart
  Future<MySqlClientPDO> connect() async {
    if (config.pool == true) {
      connection = MySQLConnectionPool(
        host: config.host,
        port: config.port,
        databaseName: config.database,
        userName: config.username ?? '',
        password: config.password,
        collation: config.charset ?? 'utf8mb4_general_ci',
        maxConnections: config.poolSize ?? 1,
        secure: config.sslmode?.toString() == 'require',
      );
    } else {
      connection = await MySQLConnection.createConnection(
        host: config.host,
        port: config.port,
        databaseName: config.database,
        userName: config.username ?? '',
        password: config.password ?? '',
        collation: config.charset ?? 'utf8mb4_general_ci',
        secure: config.sslmode?.toString() == 'require',
      );
    }
    if (connection is MySQLConnection) {
      await (connection as MySQLConnection).connect();
    }

    return this;
  }

  Future<T> runInTransaction<T>(
    Future<T> operation(MySqlClientPDOTransaction ctx), [
    int? timeoutInSeconds,
  ]) async {
    if (connection is MySQLConnectionPool) {
      final res = await (connection as MySQLConnectionPool)
          .transactional((transaCtx) async {
        final pdoCtx = MySqlClientPDOTransaction(transaCtx, this);
        return operation(pdoCtx);
      }).timeout(_timeout(timeoutInSeconds));
      return res;
    }

    final res =
        await (connection as MySQLConnection).transactional((transaCtx) async {
      final pdoCtx = MySqlClientPDOTransaction(transaCtx, this);
      return operation(pdoCtx);
    }).timeout(_timeout(timeoutInSeconds));
    return res;
  }

  /// Executa uma instrução SQL e retornar o número de linhas afetadas
  Future<int> execute(String statement, [int? timeoutInSeconds]) async {
    if (connection is MySQLConnectionPool) {
      final result = await (connection as MySQLConnectionPool)
          .execute(statement)
          .timeout(_timeout(timeoutInSeconds));
      return result.affectedRows.toInt();
    }

    final result = await (connection as MySQLConnection)
        .execute(statement)
        .timeout(_timeout(timeoutInSeconds));
    return result.affectedRows.toInt();
  }

  /// Prepares and executes an SQL statement
  /// [params] List<dynamic>
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]) async {
    // Do not reformat DateTime here; this adapter receives prepared bindings.
    final normalizedParams = _normalizedParams(params);

    if (connection is MySQLConnectionPool) {
      final result = await Future<IResultSet>.value(
        (connection as MySQLConnectionPool)
            .withConnection((conn) => conn.execute(query, normalizedParams)),
      ).timeout(_timeout(timeoutInSeconds));
      return _toPDOResults(result);
    }

    final result = await (connection as MySQLConnection)
        .execute(query, normalizedParams)
        .timeout(_timeout(timeoutInSeconds));
    return _toPDOResults(result);
  }

  @override
  Future close() async {
    if (connection is MySQLConnectionPool) {
      await (connection as MySQLConnectionPool).close();
    }
    if (connection is MySQLConnection) {
      await (connection as MySQLConnection).close();
    }
  }
}
