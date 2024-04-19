import 'dart:convert';
import 'package:eloquent/src/pdo/core/pdo_interface.dart';
import 'package:eloquent/src/pdo/core/pdo_result.dart';
import 'package:eloquent/src/utils/dsn_parser.dart';
import 'package:enough_convert/windows.dart';
import 'package:postgres/postgres.dart';
import 'postgres_v3_pdo_transaction.dart';

class PostgresV3PDO extends PDOInterface {
  /// default query Timeout =  30 seconds
  static const defaultTimeoutInSeconds = 30;

  String dsn;
  String user;
  String password;
  String dbname = '';
  int port = 5432;
  String driver = 'pgsql';
  String host = 'localhost';
  Map<dynamic, dynamic>? attributes;

  /// Creates a PDO instance representing a connection to a database
  /// Example
  ///
  /// var dsn = "pgsql:host=$host;port=5432;dbname=$db;";
  /// Example: "pgsql:host=$host;dbname=$db;charset=utf8";
  /// var pdo = new PDO($dsn, $user, $password, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
  /// await pdo.connect();
  ///
  PostgresV3PDO(this.dsn, this.user, this.password, [this.attributes]) {
    super.pdoInstance = this;
  }

  /// postgres V3 Connection
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
  Future<PostgresV3PDO> connect() async {
    final dsnParser = DSNParser(dsn, DsnType.pdoPostgreSql);

    final endpoint = Endpoint(
      host: dsnParser.host,
      port: dsnParser.port,
      database: dsnParser.database,
      username: user,
      password: password,
    );

    final sslMode = dsnParser.sslmode?.toString() == 'require'
        ? SslMode.require
        : SslMode.disable;

    if (dsnParser.pool == true) {
      connection = Pool.withEndpoints(
        [endpoint],
        settings: PoolSettings(
          applicationName: dsnParser.applicationName,
          timeZone: dsnParser.timezone,
          onOpen: (conn) async {
            await _onOpen(conn, dsnParser);
          },
          maxConnectionCount: dsnParser.poolSize,
          encoding: _getEncoding(dsnParser.charset ?? 'utf8'),
          sslMode: sslMode,
        ),
      );

      
    } else {
      connection = await Connection.open(endpoint,
          settings: ConnectionSettings(
            applicationName: dsnParser.applicationName,
            timeZone: dsnParser.timezone,
            onOpen: (conn) async {
              await _onOpen(conn, dsnParser);
            },
            encoding: _getEncoding(dsnParser.charset ?? 'utf8'),
            sslMode: sslMode,
          ));
    }

    return this;
  }

  /// inicializa configurações ao conectar com o banco de dados
  Future<void> _onOpen(Connection conn, DSNParser dsnParser) async {
    if (dsnParser.charset != null) {
      await conn.execute("SET client_encoding = '${dsnParser.charset}'");
    }
    if (dsnParser.schema != null) {
      await conn.execute("SET search_path TO ${dsnParser.schema}");
    }
    if (dsnParser.timezone != null) {
      await conn.execute("SET time zone '${dsnParser.timezone}'");
    }
    if (dsnParser.applicationName != null) {
      await conn
          .execute("SET application_name TO '${dsnParser.applicationName}'");
    }
  }

  Future<T> runInTransaction<T>(
      Future<T> operation(PostgresV3PDOTransaction ctx),
      [int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = defaultTimeoutInSeconds;
    }

    final res = await connection.runTx((transaCtx) async {
      final pdoCtx = PostgresV3PDOTransaction(transaCtx, this);
      return operation(pdoCtx);
    });

    return res;
  }

  /// Executa uma instrução SQL e retornar o número de linhas afetadas
  Future<int> execute(String statement, [int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = PostgresV3PDO.defaultTimeoutInSeconds;
    }
    final res = await connection.execute(
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

    // final conn = connection is Pool ? connection as Pool : connection as Connection;

    final rs = await connection.execute(
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

  @override
  Future close() async {
    // print('postgres_v3_pdo@close isOpen ${(connection).isOpen} ');
    if (connection is Connection) {
      await (connection as Connection).close();
    } else if (connection is Pool) {
      await (connection as Pool).close();
    }
    //print('postgres_v3_pdo@close isOpen ${(connection).isOpen} ');
  }
}
