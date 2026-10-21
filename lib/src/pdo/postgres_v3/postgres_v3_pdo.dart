import 'dart:convert';
import 'package:eloquent/src/pdo/core/operation_lock.dart';
import 'package:eloquent/src/pdo/core/pdo_config.dart';
import 'package:eloquent/src/pdo/core/pdo_interface.dart';
import 'package:eloquent/src/pdo/core/pdo_notification_connection.dart';
import 'package:eloquent/src/driver/driver_access.dart' show DriverNotification;
import 'package:eloquent/src/pdo/core/pdo_result.dart';
import 'package:eloquent/src/utils/codecs/windows.dart';
import 'package:postgres/postgres.dart';
import 'postgres_v3_pdo_transaction.dart';
import 'postgres_v3_values.dart';

class PostgresV3PDO extends PDOInterface {
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
  PostgresV3PDO(this.config) {
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

  /// The per-query timeout when the caller gives none:
  /// [defaultTimeoutInSeconds], or `driver_options` `queryTimeout`. Each
  /// query passes it to the driver, so the connection's own default never
  /// applied.
  int queryTimeoutInSeconds = defaultTimeoutInSeconds;

  //called from postgres_connector.dart
  Future<PostgresV3PDO> connect() async {
    final endpoint = Endpoint(
      host: config.host,
      port: config.port,
      database: config.database,
      username: config.username,
      password: config.password,
    );

    final sslMode = config.sslmode?.toString() == 'require'
        ? SslMode.require
        : SslMode.disable;
    // driver_options: ConnectionSettings / PoolSettings fields (durations as
    // Duration or seconds; queryMode 'extended' or 'simple').
    final options = config.driverOptionsFor('postgres_v3', {
      'connectTimeout',
      'queryTimeout',
      'queryMode',
      'ignoreSuperfluousParameters',
      if (config.pool == true) ...{
        'maxConnectionAge',
        'maxSessionUse',
        'maxQueryCount',
      },
    });
    final queryMode = _queryMode(options.text('queryMode'));
    final queryTimeout = options.duration('queryTimeout');
    if (queryTimeout != null) {
      queryTimeoutInSeconds =
          (queryTimeout.inMicroseconds / Duration.microsecondsPerSecond).ceil();
    }

    if (config.pool == true) {
      connection = Pool.withEndpoints(
        [endpoint],
        settings: PoolSettings(
          applicationName: config.applicationName,
          timeZone: config.timezone,
          onOpen: (conn) async {
            await _onOpen(conn, config);
          },
          maxConnectionCount: config.poolSize,
          encoding: _getEncoding(config.charset ?? 'utf8'),
          sslMode: sslMode,
          typeRegistry: postgresV3TypeRegistry(config),
          connectTimeout: options.duration('connectTimeout'),
          queryTimeout: options.duration('queryTimeout'),
          queryMode: queryMode,
          ignoreSuperfluousParameters:
              options.flag('ignoreSuperfluousParameters'),
          maxConnectionAge: options.duration('maxConnectionAge'),
          maxSessionUse: options.duration('maxSessionUse'),
          maxQueryCount: options.integer('maxQueryCount'),
        ),
      );
    } else {
      connection = await Connection.open(endpoint,
          settings: ConnectionSettings(
            applicationName: config.applicationName,
            timeZone: config.timezone,
            onOpen: (conn) async {
              await _onOpen(conn, config);
            },
            encoding: _getEncoding(config.charset ?? 'utf8'),
            sslMode: sslMode,
            typeRegistry: postgresV3TypeRegistry(config),
            connectTimeout: options.duration('connectTimeout'),
            queryTimeout: options.duration('queryTimeout'),
            queryMode: queryMode,
            ignoreSuperfluousParameters:
                options.flag('ignoreSuperfluousParameters'),
          ));
    }

    return this;
  }

  static QueryMode? _queryMode(String? name) {
    if (name == null) return null;
    for (final mode in QueryMode.values) {
      if (mode.name == name) return mode;
    }
    throw ArgumentError.value(
        name, 'driver_options.queryMode', "Expected 'extended' or 'simple'");
  }

  @override
  bool get supportsNotifications => true;

  /// A new Connection, outside the pool, for LISTEN.
  @override
  Future<PDONotificationConnection> openNotificationConnection() async {
    final conn = await Connection.open(
        Endpoint(
          host: config.host,
          port: config.port,
          database: config.database,
          username: config.username,
          password: config.password,
        ),
        settings: ConnectionSettings(
          applicationName: config.applicationName,
          timeZone: config.timezone,
          onOpen: (conn) async {
            await _onOpen(conn, config);
          },
          encoding: _getEncoding(config.charset ?? 'utf8'),
          sslMode: config.sslmode?.toString() == 'require'
              ? SslMode.require
              : SslMode.disable,
          typeRegistry: postgresV3TypeRegistry(config),
        ));
    return PDONotificationConnection(
      notifications: conn.channels.all
          .map((n) => DriverNotification(n.channel, n.payload, n.processId)),
      execute: (sql, timeout) => conn.execute(sql,
          timeout: timeout, queryMode: QueryMode.simple, ignoreRows: true),
      close: conn.close,
      closed: conn.closed,
    );
  }

  /// inicializa configurações ao conectar com o banco de dados
  Future<void> _onOpen(Connection conn, PDOConfig dsnParser) async {
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
    // statement/lock/idle-in-transaction timeouts, as in the other adapters.
    for (final statement in dsnParser.postgresTimeoutStatements()) {
      await conn.execute(statement);
    }
  }

  /// Serializes callers of the single (non-pool) connection: postgres 3.x
  /// rejects a query on a connection that is inside `runTx` ("Attempting to
  /// execute query on connection while inside a `runTx` call"), so a request
  /// that arrived during another one's transaction failed.
  final OperationLock _singleConnectionLock = OperationLock();

  Future<R> _single<R>(Future<R> Function() operation) =>
      connection is Pool ? operation() : _singleConnectionLock.run(operation);

  Future<T> runInTransaction<T>(
          Future<T> operation(PostgresV3PDOTransaction ctx),
          [int? timeoutInSeconds]) =>
      _single(() => _runInTransaction(operation, timeoutInSeconds));

  Future<T> _runInTransaction<T>(
      Future<T> operation(PostgresV3PDOTransaction ctx),
      [int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = queryTimeoutInSeconds;
    }

    final res = await connection.runTx((transaCtx) async {
      final pdoCtx = PostgresV3PDOTransaction(transaCtx, this);
      return operation(pdoCtx);
    },
        settings: TransactionSettings(
            queryTimeout: Duration(seconds: timeoutInSeconds)));

    return res;
  }

  /// Executa uma instrução SQL e retornar o número de linhas afetadas
  Future<int> execute(String statement, [int? timeoutInSeconds]) =>
      _single(() => _execute(statement, timeoutInSeconds));

  Future<int> _execute(String statement, [int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = queryTimeoutInSeconds;
    }
    // Simple query protocol, as PDO::exec (libpq's PQexec): no parameters,
    // and a script with several statements runs whole. The extended
    // protocol (queryMode's default) refuses more than one (42601).
    final res = await connection.execute(
      statement,
      queryMode: QueryMode.simple,
      timeout: Duration(seconds: timeoutInSeconds),
    );
    return res.affectedRows;
  }

  /// Prepares and executes an SQL statement with placeholders
  Future<PDOResults> query(String query,
          [dynamic params, int? timeoutInSeconds]) =>
      _single(() => _query(query, params, timeoutInSeconds));

  Future<PDOResults> _query(String query,
      [dynamic params, int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = queryTimeoutInSeconds;
    }

    // final conn = connection is Pool ? connection as Pool : connection as Connection;

    final rs = await connection.execute(
      Sql.indexed(query, substitution: '?'),
      parameters: params,
      timeout: Duration(seconds: timeoutInSeconds),
    );

    final pdoResult = PDOResults(postgresV3Rows(config, rs), rs.affectedRows);
    return pdoResult;
  }

  @override
  Future close() async {
    if (connection is Connection) {
      await (connection as Connection).close(force: true);
    } else if (connection is Pool) {
      await (connection as Pool).close(force: true);
    }
  }
}
