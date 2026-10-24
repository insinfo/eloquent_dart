import 'dart:async';
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

  /// Creates a PDO instance representing a connection to a database.
  ///
  /// ```dart
  /// Map<String, dynamic> config = {'host': 'localhost','port':5432,'database':'teste'};
  /// var pdo = PostgresV3PDO(PDOConfig.fromMap(config));
  /// await pdo.connect();
  /// ```
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

  /// Serializes callers of the single (non-pool) connection: while one of
  /// them has a transaction open on it, a statement of another request would
  /// run inside that transaction.
  final OperationLock _singleConnectionLock = OperationLock();

  Future<R> _single<R>(Future<R> Function() operation) =>
      connection is Pool ? operation() : _singleConnectionLock.run(operation);

  Future<T> runInTransaction<T>(
          Future<T> operation(PostgresV3PDOTransaction ctx),
          [int? timeoutInSeconds]) =>
      _single(() => _runInTransaction(operation, timeoutInSeconds));

  Future<T> _runInTransaction<T>(
      Future<T> operation(PostgresV3PDOTransaction ctx),
      [int? timeoutInSeconds]) {
    final timeout =
        Duration(seconds: timeoutInSeconds ?? queryTimeoutInSeconds);
    final c = connection;
    if (c is Pool) {
      return c.withConnection<T>(
          (session) => _transaction(session, operation, timeout));
    }
    return _transaction(c as Connection, operation, timeout);
  }

  /// Runs [operation] between a BEGIN and a COMMIT sent on [session], a
  /// connection reserved for it.
  ///
  /// Not `runTx`: postgres 3.x rolls back the whole transaction after any
  /// SQL error, even one a ROLLBACK TO SAVEPOINT recovered from, so a nested
  /// transaction could not survive an SQL error. The context tracks whether
  /// the server aborted the transaction instead (see
  /// [PostgresV3PDOTransaction.abortedBy]): a COMMIT then would be answered
  /// with a ROLLBACK, not with an error, so it rolls back and throws.
  ///
  /// When a COMMIT or ROLLBACK fails without an answer from the server (lost
  /// connection, timeout), the state of the transaction is unknown and
  /// [session] is closed, so it is never used again: the pool discards it,
  /// and the single connection is reconnected by `Connection`.
  Future<T> _transaction<T>(
      Connection session,
      Future<T> operation(PostgresV3PDOTransaction ctx),
      Duration timeout) async {
    Future<void> end(String statement) async {
      try {
        await session.execute(statement,
            queryMode: QueryMode.simple, timeout: timeout);
      } catch (e) {
        // A COMMIT or ROLLBACK the server answered, even with an error,
        // ended the transaction.
        if (e is! ServerException || e is TimeoutException || !session.isOpen) {
          try {
            await session.close(force: true);
          } catch (_) {}
        }
        rethrow;
      }
    }

    await session.execute('BEGIN',
        queryMode: QueryMode.simple, timeout: timeout);
    final ctx = PostgresV3PDOTransaction(session, this);
    final T result;
    try {
      result = await operation(ctx);
    } catch (_) {
      try {
        await end('ROLLBACK');
      } catch (_) {
        // The operation's error takes precedence.
      }
      rethrow;
    }

    final aborted = ctx.abortedBy;
    if (aborted != null) {
      await end('ROLLBACK');
      throw PgException('The transaction was rolled back: a statement failed '
          'and no ROLLBACK TO SAVEPOINT recovered from it ($aborted).');
    }
    await end('COMMIT');
    return result;
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
    return res.affectedRows as int;
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

    final pdoResult =
        PDOResults(postgresV3Rows(config, rs as Result), rs.affectedRows);
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
