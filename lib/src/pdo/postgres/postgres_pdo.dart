import 'dart:convert';
import 'package:eloquent/src/utils/dsn_parser.dart';
import 'package:eloquent/eloquent.dart';
import 'package:enough_convert/windows.dart';
import 'postgres_pdo_transaction.dart';
import 'package:postgres_fork/postgres.dart';

import 'dependencies/postgres_pool/postgres_pool.dart';

class PostgresPDO extends PDOInterface {
  /// default query Timeout =  30 seconds
  static const defaultTimeoutInSeconds = 30;

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
  PostgresPDO(this.dsn, this.user, this.password, [this.attributes]) {
    super.pdoInstance = this;
  }

  /// CoreConnection
  late dynamic connection;

  Encoding _getEncoding(String encoding) {
    switch (encoding.toLowerCase()) {
      case 'utf8':
        return Utf8Codec();
      case 'ascii':
        return AsciiCodec();
      case 'latin1':
        return Latin1Codec();
      case 'iso-8859-1':
        return Latin1Codec();
      case 'win1252':
        //WIN1250	Windows CP1250 | cp1252
        return Windows1252Codec(allowInvalid: false);
      default:
        return Utf8Codec(allowMalformed: true);
    }
  }

  //called from postgres_connector.dart
  Future<PostgresPDO> connect() async {
    final dsnParser = DSNParser(dsn, DsnType.pdoPostgreSql);

    if (dsnParser.pool == true) {
      final endpoint = PgEndpoint(
        host: dsnParser.host,
        port: dsnParser.port,
        database: dsnParser.database,
        username: user,
        password: password,
      );
      final settings = PgPoolSettings();
      settings.encoding = _getEncoding(dsnParser.charset ?? 'utf8');
      settings.maxConnectionCount = dsnParser.poolSize;
      settings.onOpen = (conn) async {
        await _onOpen(conn, dsnParser);
      };
      connection = PgPool(endpoint, settings: settings);
      //print('dsnParser.pool ${dsnParser.pool} $connection');
    } else {
      connection = PostgreSQLConnection(
        dsnParser.host,
        dsnParser.port,
        dsnParser.database,
        username: user,
        password: password,
        encoding: _getEncoding(dsnParser.charset ?? 'utf8'),
      );
      final conn = connection as PostgreSQLConnection;
      await conn.open();
      await _onOpen(conn, dsnParser);
    }

    return this;
  }

  /// inicializa configurações ao conectar com o banco de dados
  Future<void> _onOpen(
      PostgreSQLExecutionContext conn, DSNParser dsnParser) async {
    if (dsnParser.charset != null) {
      await conn.execute("SET client_encoding = '${dsnParser.charset}'");
    }
    if (dsnParser.schema != null) {
      await conn.execute("SET search_path TO ${dsnParser.schema}");
    }
    if (dsnParser.timezone != null) {
      await conn.execute("SET timezone TO '${dsnParser.timezone}'");
    }
    if (dsnParser.applicationName != null) {
      await conn
          .execute("SET application_name TO '${dsnParser.applicationName}'");
    }
  }

  Future<T> runInTransaction<T>(Future<T> operation(PostgresPDOTransaction ctx),
      [int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = defaultTimeoutInSeconds;
    }
    if (connection is PostgreSQLConnection) {
      final res = await (connection as PostgreSQLConnection).transaction(
          (transaCtx) async {
        final pdoCtx = PostgresPDOTransaction(transaCtx, this);
        return operation(pdoCtx);
      }, commitTimeoutInSeconds: timeoutInSeconds);
      return res as T;
    } else {
      final res = await (connection as PgPool).runTx(
        (transaCtx) async {
          final pdoCtx = PostgresPDOTransaction(transaCtx, this);
          return operation(pdoCtx);
        },
      ).timeout(Duration(seconds: timeoutInSeconds));
      return res;
    }
  }

  /// Executa uma instrução SQL e retornar o número de linhas afetadas
  Future<int> execute(String statement, [int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = defaultTimeoutInSeconds;
    }
    if (connection is PostgreSQLConnection) {
      final result = await (connection as PostgreSQLConnection).execute(
          statement,
          timeoutInSeconds: timeoutInSeconds,
          placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark);
      return result;
    } else {
      final result = await (connection as PgPool).execute(statement,
          timeoutInSeconds: timeoutInSeconds,
          placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark);
      return result;
    }
  }

  /// Prepares and executes an SQL statement
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = defaultTimeoutInSeconds;
    }
    if (connection is PostgreSQLConnection) {
      final rs = await (connection as PostgreSQLConnection).query(
        query,
        substitutionValues: params,
        // allowReuse: allowReuse ?? false,
        timeoutInSeconds: timeoutInSeconds,
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
      );
      final rows = rs.map((row) => row.toColumnMap()).toList();
      final pdoResult = PDOResults(rows, rs.affectedRowCount);
      return pdoResult;
    } else {
      final rs = await (connection as PgPool).query(
        query,
        substitutionValues: params,
        // allowReuse: allowReuse ?? false,
        timeoutInSeconds: timeoutInSeconds,
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
      );
      final rows = rs.map((row) => row.toColumnMap()).toList();
      final pdoResult = PDOResults(rows, rs.affectedRowCount);
      return pdoResult;
    }
  }

  @override
  Future close() async {
    if (connection is PostgreSQLConnection) {
      await (connection as PostgreSQLConnection).close();
    } else {
      await (connection as PgPool).close();
    }
  }
}
