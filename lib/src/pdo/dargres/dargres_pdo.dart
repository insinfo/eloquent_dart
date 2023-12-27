import 'package:dargres/dargres.dart' as dargres;
import 'package:eloquent/src/utils/dsn_parser.dart';
import 'package:eloquent/eloquent.dart';
import 'dargres_pdo_transaction.dart';

class DargresPDO extends PDOInterface {
  /// default query Timeout =  30 seconds
  static const defaultTimeout = const Duration(seconds: 30);

  String dsn;
  String user;
  String password;
  String dbname = '';
  int port = 5432;
  String driver = 'pgsql';
  String host = 'localhost';
  dynamic attributes;

  /// Creates a PDO instance representing a connection to a database
  /// Example
  ///
  /// var dsn = "pgsql:host=$host;port=5432;dbname=$db;";
  /// Example: "pgsql:host=$host;dbname=$db;charset=utf8";
  /// var pdo = new PDO($dsn, $user, $password, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
  /// await pdo.connect();
  ///
  DargresPDO(this.dsn, this.user, this.password, [this.attributes]) {
    super.pdoInstance = this;
  }

  /// CoreConnection
  dargres.ConnectionInterface? connection;

  //called from postgres_connector.dart
  Future<DargresPDO> connect() async {
    final dsnParser = DSNParser(dsn, DsnType.pdoPostgreSql);

    if (dsnParser.pool == true) {
      final settings = dargres.ConnectionSettings(
        user: user,
        database: dsnParser.database,
        host: dsnParser.host,
        port: dsnParser.port,
        password: password,
        textCharset: dsnParser.charset ?? 'utf8',
        applicationName: dsnParser.applicationName,
        allowAttemptToReconnect: false,
      );
      connection = dargres.PostgreSqlPool(dsnParser.poolSize, settings,
          allowAttemptToReconnect: dsnParser.allowReconnect);
    } else {
      connection = dargres.CoreConnection(user,
          database: dsnParser.database,
          host: dsnParser.host,
          port: dsnParser.port,
          password: password,
          allowAttemptToReconnect: false,
          // sslContext: sslContext,
          textCharset: dsnParser.charset ?? 'utf8');
      await connection!.connect();
    }

    return this;
  }

  Future<T> runInTransaction<T>(Future<T> operation(DargresPDOTransaction ctx),
      [int? timeoutInSeconds]) async {
    return connection!.runInTransaction((transaCtx) async {
      final pdoCtx = DargresPDOTransaction(transaCtx, this);
      return operation(pdoCtx);
    });
  }

  /// Executa uma instrução SQL e retornar o número de linhas afetadas
  Future<int> execute(String statement, [int? timeoutInSeconds]) {
    return connection!.execute(statement);
  }

  /// Prepares and executes an SQL statement
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]) async {
    final results = await connection!.queryNamed(query, params ?? [],
        placeholderIdentifier: dargres.PlaceholderIdentifier.onlyQuestionMark);
    final pdoResult = PDOResults(results.toMaps(), results.rowsAffected.value);
    return pdoResult;
  }

  @override
  Future close() async {
    await connection!.close();
  }
}
