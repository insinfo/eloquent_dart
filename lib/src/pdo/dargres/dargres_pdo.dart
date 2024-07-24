import 'package:dargres/dargres.dart' as dargres;
import 'package:eloquent/eloquent.dart';
import 'dargres_pdo_transaction.dart';

class DargresPDO extends PDOInterface {
  /// default query Timeout =  30 seconds
  static const defaultTimeout = const Duration(seconds: 30);

  PDOConfig config;

  /// Creates a PDO instance representing a connection to a database
  /// Example
  ///
  ///
  /// Example:  Map<String, dynamic> config = {'host': 'localhost','port':5432,'database':'teste'};
  /// var pdo = new PDO(PDOConfig.fromMap(config));
  /// await pdo.connect();
  ///
  DargresPDO(this.config) {
    super.pdoInstance = this;
  }

  /// CoreConnection
  dargres.ConnectionInterface? connection;

  //called from postgres_connector.dart
  Future<DargresPDO> connect() async {
    final timeZone = dargres.TimeZoneSettings(config.timezone ?? 'UTC');
    timeZone.forceDecodeTimestamptzAsUTC = config.forceDecodeTimestamptzAsUTC;
    timeZone.forceDecodeTimestampAsUTC = config.forceDecodeTimestampAsUTC;
    timeZone.forceDecodeDateAsUTC = config.forceDecodeDateAsUTC;

    if (config.pool == true) {
      final settings = dargres.ConnectionSettings(
        user: config.username ?? '',
        database: config.database,
        host: config.host,
        port: config.port,
        password: config.password,
        textCharset: config.charset ?? 'utf8',
        applicationName: config.applicationName,
        allowAttemptToReconnect: false,
        timeZone: timeZone,
      );
      connection = dargres.PostgreSqlPool(config.poolSize ?? 1, settings,
          allowAttemptToReconnect: config.allowReconnect ?? false);
    } else {
      connection = dargres.CoreConnection(config.username ?? '',
          database: config.database,
          host: config.host,
          port: config.port,
          password: config.password,
          allowAttemptToReconnect: false,
          // sslContext: sslContext,
          textCharset: config.charset ?? 'utf8',
          timeZone: timeZone);
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
