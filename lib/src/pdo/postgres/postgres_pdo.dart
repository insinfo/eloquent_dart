import 'dart:convert';
import 'package:eloquent/src/utils/dsn_parser.dart';
import 'package:eloquent/eloquent.dart';
import 'package:enough_convert/windows.dart';
import 'postgres_pdo_transaction.dart';
import 'package:postgres/postgres.dart';

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
    //print('PDO@construct');
    super.pdoInstance = this;
  }

  /// CoreConnection
  late PostgreSQLConnection connection;

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
    //print('PostgresPDO@connect dsn: $dsn');
    final dsnParser = DSNParser(dsn, DsnType.pdoPostgreSql);

    connection = PostgreSQLConnection(
      dsnParser.host,
      dsnParser.port,
      dsnParser.database,
      username: user,
      password: password,
      encoding: _getEncoding(dsnParser.charset),
    );
    await connection.open();
    await connection.query('''SET client_encoding = '${dsnParser.charset}';''');
    //print('PostgresPDO@connect host: ${dsnParser.host}');
    return this;
  }

  Future<T> runInTransaction<T>(Future<T> operation(PostgresPDOTransaction ctx),
      [int? timeoutInSeconds]) async {
    //print('PDO@runInTransaction ');
    if (timeoutInSeconds == null) {
      timeoutInSeconds = defaultTimeoutInSeconds;
    }
    final res = await connection.transaction((transaCtx) async {
      final pdoCtx = PostgresPDOTransaction(transaCtx, this);
      return operation(pdoCtx);
    }, commitTimeoutInSeconds: timeoutInSeconds);

    return res as T;
  }

  /// Executa uma instrução SQL e retornar o número de linhas afetadas
  Future<int> execute(String statement, [int? timeoutInSeconds]) async {
    // print( 'PostgresPDO@execute statement $statement | timeoutInSeconds $timeoutInSeconds');
    if (timeoutInSeconds == null) {
      timeoutInSeconds = defaultTimeoutInSeconds;
    }
    final result = await connection.execute(statement,
        timeoutInSeconds: timeoutInSeconds,
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark);
    //print('PostgresPDO@execute result: $result');
    return result;
  }

  /// Prepares and executes an SQL statement
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = defaultTimeoutInSeconds;
    }
    // final rows = await connection.mappedResultsQuery(
    //   query,
    //   substitutionValues: params,
    //   timeoutInSeconds: timeoutInSeconds,
    //   placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
    // );

    final rs = await connection.query(
      query,
      substitutionValues: params,
      // allowReuse: allowReuse ?? false,
      timeoutInSeconds: timeoutInSeconds,
      placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
    );

    final rows = rs.map((row) => row.toTableColumnMap()).toList();

    final maps = <Map<String, dynamic>>[];
    if (rows.isNotEmpty) {
      for (var item in rows) {
        //Combine/merge multiple maps into 1 map
        maps.add(item.values.reduce((map1, map2) => map1..addAll(map2)));
      }
    }

    final pdoResult = PDOResults(maps, rs.affectedRowCount);
    return pdoResult;
  }

  @override
  Future close() async {
    await connection.close();
  }
}
