import 'package:eloquent/src/pdo/core/pdo_interface.dart';
import 'package:eloquent/src/pdo/core/pdo_result.dart';
import 'package:eloquent/src/utils/dsn_parser.dart';
import 'package:mysql_client/mysql_client.dart';
import 'mysql_client_pdo_transaction.dart';

class MySqlClientPDO extends PDOInterface {
  /// default query Timeout =  30 seconds
  static const defaultTimeoutInSeconds = 30;

  String dsn;
  String user;
  String password;
  String dbname = '';
  int port = 3306;
  String driver = 'mysql_client';
  String host = 'localhost';
  dynamic attributes;

  /// Creates a PDO instance representing a connection to a database
  /// Example
  ///
  /// var dsn = "mysql:host=localhost;port=3306;dbname=banco_teste;";
  /// Example: "mysql:host=localhost;port=3306;dbname=banco_teste;";
  /// var pdo = new PDO($dsn, $user, $password, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
  /// await pdo.connect();
  ///
  MySqlClientPDO(this.dsn, this.user, this.password, [this.attributes]) {
    super.pdoInstance = this;
  }

  /// CoreConnection
  late dynamic connection;

  //called from postgres_connector.dart
  Future<MySqlClientPDO> connect() async {
    final dsnParser = DSNParser(dsn, DsnType.pdoPostgreSql);

    if (dsnParser.pool == true) {
      connection = MySQLConnectionPool(
        host: dsnParser.host,
        port: dsnParser.port,
        databaseName: dsnParser.database,
        userName: user,
        password: password,
        collation: dsnParser.charset ?? 'utf8mb4_general_ci',
        maxConnections: dsnParser.poolSize,
        secure: false,
      );
    } else {
      connection = await MySQLConnection.createConnection(
        host: dsnParser.host,
        port: dsnParser.port,
        databaseName: dsnParser.database,
        userName: user,
        password: password,
        collation: dsnParser.charset ?? 'utf8mb4_general_ci',
        secure: false,
      );
    }
    if (connection is MySQLConnection) {
      await (connection as MySQLConnection).connect();
    }
    //else if(connection is MySQLConnectionPool){
    //await (connection as MySQLConnectionPool).;
    //}

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
