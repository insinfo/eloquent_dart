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

    final sslMode = await _sslMode();
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

  /// The postgres 3.x SSL mode for `sslmode` (see [PDOSslMode]). The
  /// package has no allow/prefer: those use TLS when the server accepts it
  /// (asked before connecting) and plain otherwise. verify-ca is
  /// [SslMode.verifyFull]: dart:io verifies the chain and the host name
  /// together.
  Future<SslMode> _sslMode() async {
    switch (await config.resolvePgSslMode()) {
      case PDOSslMode.disable:
      case PDOSslMode.allow:
      case PDOSslMode.prefer:
        return SslMode.disable;
      case PDOSslMode.require:
        return SslMode.require;
      case PDOSslMode.verifyCa:
      case PDOSslMode.verifyFull:
        return SslMode.verifyFull;
    }
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
          sslMode: await _sslMode(),
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
  /// The values are quoted as string literals; the schema comes formatted
  /// by PostgresConnector.formatSchema (quoted identifiers), and an empty
  /// one sets no search_path.
  Future<void> _onOpen(Connection conn, PDOConfig dsnParser) async {
    final charset = dsnParser.charset;
    if (charset != null) {
      await conn.execute(
          'SET client_encoding = ${PDOConfig.quotePgLiteral(charset)}');
    }
    final schema = dsnParser.schema;
    if (schema != null && schema.trim().isNotEmpty) {
      await conn.execute('SET search_path TO $schema');
    }
    final timezone = dsnParser.timezone;
    if (timezone != null) {
      await conn
          .execute('SET timezone TO ${PDOConfig.quotePgLiteral(timezone)}');
    }
    final applicationName = dsnParser.applicationName;
    if (applicationName != null) {
      await conn.execute('SET application_name TO '
          '${PDOConfig.quotePgLiteral(applicationName)}');
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
