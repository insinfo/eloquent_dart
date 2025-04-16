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
      Future<T> operation(MySqlClientPDOTransaction ctx),
      [int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = defaultTimeoutInSeconds;
    }

    if (connection is MySQLConnectionPool) {
      final res = await (connection as MySQLConnectionPool)
          .transactional((transaCtx) async {
        final pdoCtx = MySqlClientPDOTransaction(transaCtx, this);
        return operation(pdoCtx);
      });
      return res;
    }

    final res =
        await (connection as MySQLConnection).transactional((transaCtx) async {
      final pdoCtx = MySqlClientPDOTransaction(transaCtx, this);
      return operation(pdoCtx);
    });
    return res;
  }

  /// Executa uma instrução SQL e retornar o número de linhas afetadas
  Future<int> execute(String statement, [int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = defaultTimeoutInSeconds;
    }

    if (connection is MySQLConnectionPool) {
      final result =
          await (connection as MySQLConnectionPool).execute(statement);
      return result.affectedRows.toInt();
    }

    final result = await (connection as MySQLConnection).execute(statement);
    return result.affectedRows.toInt();
  }

  /// Prepares and executes an SQL statement
  /// [params] List<dynamic>
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = defaultTimeoutInSeconds;
    }

    if (connection is MySQLConnectionPool) {
      final stmt = await (connection as MySQLConnectionPool).prepare(query);
      //.timeout(timeoutInSeconds);
      final result = await stmt.execute(params ?? []);
      await stmt.deallocate();
      final rows = result.rows.map((row) => row.typedAssoc()).toList();
      final pdoResult = PDOResults(rows, result.affectedRows.toInt());
      return pdoResult;
    }

    final stmt = await (connection as MySQLConnection).prepare(query);
    final result = await stmt.execute(params ?? []);
    await stmt.deallocate();
    final rows = result.rows.map((row) => row.typedAssoc()).toList();
    final pdoResult = PDOResults(rows, result.affectedRows.toInt());
    return pdoResult;
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
