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
  dynamic attributes;

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
  late Connection connection;

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

    connection = await Connection.open(
        Endpoint(
          host: dsnParser.host,
          port: dsnParser.port,
          database: dsnParser.database,
          username: user,
          password: password,
        ),
        settings: ConnectionSettings(
          encoding: _getEncoding(dsnParser.charset ?? 'utf8'),
          sslMode: SslMode.disable,
        ));

    await connection
        .execute('''SET client_encoding = '${dsnParser.charset}';''');
    return this;
  }

  Future<T> runInTransaction<T>(Future<T> operation(PostgresV3PDOTransaction ctx),
      [int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = defaultTimeoutInSeconds;
    }

    final res = await connection.runTx((transaCtx) async {
      final pdoCtx = PostgresV3PDOTransaction(transaCtx, this);
      return operation(pdoCtx);
    });

    return res ;
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
          final value = col.value is UndecodedBytes ? col.value.asString : col.value;
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
    await connection.close();
  }
}
