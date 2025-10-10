import 'dart:convert';

import 'package:eloquent/eloquent.dart';
import 'package:enough_convert/windows.dart';
import 'postgres_pdo_transaction.dart';
import 'package:postgres_fork/postgres.dart';

import 'dependencies/postgres_pool/postgres_pool.dart';

class PostgresV2PDO extends PDOInterface {
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
  PostgresV2PDO(this.config) {
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
  Future<PostgresV2PDO> connect() async {
    final timeZone = TimeZoneSettings(config.timezone ?? 'UTC');
    timeZone.forceDecodeTimestamptzAsUTC = config.forceDecodeTimestamptzAsUTC;
    timeZone.forceDecodeTimestampAsUTC = config.forceDecodeTimestampAsUTC;
    timeZone.forceDecodeDateAsUTC = config.forceDecodeDateAsUTC;

    if (config.pool == true) {
      final endpoint = PgEndpoint(
        host: config.host,
        port: config.port,
        database: config.database,
        username: config.username,
        password: config.password,
      );
      final settings = PgPoolSettings();
      settings.encoding = _getEncoding(config.charset ?? 'utf8');
      settings.maxConnectionCount = config.poolSize ?? 1;

      settings.onOpen = (conn) async {
        await _onOpen(conn, config);
      };
      settings.timeZone = timeZone;
      connection = PgPool(endpoint, settings: settings);
      // TODO remover logs para produção

      //  logger simples para todos os eventos do pool
      // connection.events.listen((e) {
      //   // encurta SQL pra log não virar um livro
      //   String q(String? s) => s == null
      //       ? '-'
      //       : (s.length <= 120 ? s : s.substring(0, 117) + '...');
      //   print('[PgPool] c${e.connectionId} ${e.action}'
      //       '${e.sessionId != null ? ' session=' + e.sessionId! : ''}'
      //       '${e.traceId != null ? ' trace=' + e.traceId! : ''}'
      //       '${e.elapsed != null ? ' in ${e.elapsed!.inMilliseconds}ms' : ''}'
      //       '${e.query != null ? ' sql=' + q(e.query) : ''}'
      //       '${e.error != null ? ' error=' + e.error.toString() : ''}');
      // });

    } else {
      connection = PostgreSQLConnection(
        config.host,
        config.port,
        config.database,
        username: config.username,
        password: config.password,
        timeZone: timeZone,
        encoding: _getEncoding(config.charset ?? 'utf8'),
      );
      final conn = connection as PostgreSQLConnection;
      await conn.open();
      await _onOpen(conn, config);
    }

    return this;
  }

  /// ajuda: normaliza valores tipo "3000", "250ms", "3s", "2min" -> string aceita pelo PG
  String _pgTimeout(String raw) {
    final s = raw.trim().toLowerCase();
    // 0 desabilita
    if (s == '0' || s == '0ms' || s == '0s' || s == '0min') return '0';
    // já vem com unidade suportada pelo PG?
    final okUnits = ['ms', 's', 'min'];
    if (okUnits.any((u) => s.endsWith(u))) return s;
    // só números -> trata como ms
    if (RegExp(r'^\d+$').hasMatch(s)) return '${s}ms';
    throw ArgumentError(
        'Timeout inválido: "$raw". Use "250ms", "3s", "2min" ou "0".');
  }

  /// inicializa configurações ao conectar com o banco de dados
  Future<void> _onOpen(PostgreSQLExecutionContext conn, PDOConfig conf) async {
    if (conf.charset != null) {
      await conn.execute("SET client_encoding = '${conf.charset}'");
    }
    if (conf.schema != null) {
      await conn.execute("SET search_path TO ${conf.schema}");
    }
    if (conf.timezone != null) {
      await conn.execute("SET timezone TO '${conf.timezone}'");
    }
    if (conf.applicationName != null) {
      await conn.execute("SET application_name TO '${conf.applicationName}'");
    }
    //
    if (conf.statementTimeout != null && conf.statementTimeout!.isNotEmpty) {
      final v = _pgTimeout(conf.statementTimeout!);
      await conn.execute("SET statement_timeout = '$v'");
    }
    if (conf.lockTimeout != null && conf.lockTimeout!.isNotEmpty) {
      final v = _pgTimeout(conf.lockTimeout!);
      await conn.execute("SET lock_timeout = '$v'");
    }
    if (conf.idleInTransactionSessionTimeout != null &&
        conf.idleInTransactionSessionTimeout!.isNotEmpty) {
      final v = _pgTimeout(conf.idleInTransactionSessionTimeout!);
      await conn.execute("SET idle_in_transaction_session_timeout = '$v'");
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
    } else if (connection is PgPool) {
      await (connection as PgPool).close();
    }
  }
}
