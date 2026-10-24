import 'dart:convert';
import 'dart:math' as math;

import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/utils/codecs/windows.dart';
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
  /// The per-query timeout when the caller gives none:
  /// [defaultTimeoutInSeconds], or `driver_options` `queryTimeoutInSeconds`
  /// (`queryTimeout` with pool). Each query passes it to the driver, so the
  /// connection's own default never applied.
  int queryTimeoutInSeconds = defaultTimeoutInSeconds;

  Future<PostgresV2PDO> connect() async {
    final pool = config.pool == true;
    // driver_options: PostgreSQLConnection parameters, or PgPoolSettings
    // fields with pool (durations as Duration or seconds).
    final options = config.driverOptionsFor(
        'postgres',
        pool
            ? const {
                'connectTimeout',
                'queryTimeout',
                'idleTestThreshold',
                'maxConnectionAge',
                'maxSessionUse',
                'maxErrorCount',
                'maxQueryCount',
              }
            : const {
                'timeoutInSeconds',
                'queryTimeoutInSeconds',
                'useSSL',
                'allowClearTextPassword',
                'isUnixSocket',
                'cancelQueryOnTimeout',
              });
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
        sslMode: _sslMode(),
      );
      final settings = PgPoolSettings();
      settings.encoding = _getEncoding(config.charset ?? 'utf8');
      settings.maxConnectionCount = config.poolSize ?? 1;

      settings.onOpen = (conn) async {
        await _onOpen(conn, config);
      };
      settings.timeZone = timeZone;
      settings.decodingSettings = _decodingSettings(config);
      final connectTimeout = options.duration('connectTimeout');
      if (connectTimeout != null) settings.connectTimeout = connectTimeout;
      final queryTimeout = options.duration('queryTimeout');
      if (queryTimeout != null) {
        settings.queryTimeout = queryTimeout;
        queryTimeoutInSeconds = _seconds(queryTimeout);
      }
      final idleTestThreshold = options.duration('idleTestThreshold');
      if (idleTestThreshold != null) {
        settings.idleTestThreshold = idleTestThreshold;
      }
      final maxConnectionAge = options.duration('maxConnectionAge');
      if (maxConnectionAge != null)
        settings.maxConnectionAge = maxConnectionAge;
      final maxSessionUse = options.duration('maxSessionUse');
      if (maxSessionUse != null) settings.maxSessionUse = maxSessionUse;
      final maxErrorCount = options.integer('maxErrorCount');
      if (maxErrorCount != null) settings.maxErrorCount = maxErrorCount;
      final maxQueryCount = options.integer('maxQueryCount');
      if (maxQueryCount != null) settings.maxQueryCount = maxQueryCount;
      connection = PgPool(endpoint, settings: settings);
    } else {
      connection = PostgreSQLConnection(
        config.host,
        config.port,
        config.database,
        username: config.username,
        password: config.password,
        timeZone: timeZone,
        encoding: _getEncoding(config.charset ?? 'utf8'),
        decodingSettings: _decodingSettings(config),
        timeoutInSeconds: options.integer('timeoutInSeconds') ?? 30,
        queryTimeoutInSeconds: queryTimeoutInSeconds =
            options.integer('queryTimeoutInSeconds') ?? queryTimeoutInSeconds,
        useSSL: options.flag('useSSL') ?? false,
        sslMode: _sslMode(options.flag('useSSL')),
        allowClearTextPassword: options.flag('allowClearTextPassword') ?? false,
        isUnixSocket: options.flag('isUnixSocket') ?? false,
        cancelQueryOnTimeout: options.flag('cancelQueryOnTimeout') ?? false,
      );
      final conn = connection as PostgreSQLConnection;
      await conn.open();
      await _onOpen(conn, config);
    }

    return this;
  }

  /// The postgres_fork SSL mode for `sslmode` (see [PDOSslMode]); `null`
  /// when `sslmode` is absent, so the `useSSL` driver option decides.
  /// `useSSL: true` still forces TLS over `disable`.
  PgSslMode? _sslMode([bool? useSSL]) {
    if (config.sslmode == null) return null;
    switch (config.parsedSslMode) {
      case PDOSslMode.disable:
        return useSSL == true ? PgSslMode.require : PgSslMode.disable;
      case PDOSslMode.allow:
      case PDOSslMode.prefer:
        return PgSslMode.prefer;
      case PDOSslMode.require:
        return PgSslMode.require;
      // postgres_fork verifies the chain and the host name together.
      case PDOSslMode.verifyCa:
      case PDOSslMode.verifyFull:
        return PgSslMode.verifyFull;
    }
  }

  static int _seconds(Duration duration) =>
      (duration.inMicroseconds / Duration.microsecondsPerSecond).ceil();

  @override
  bool get supportsNotifications => true;

  /// A new PostgreSQLConnection, outside the pool, for LISTEN.
  @override
  Future<PDONotificationConnection> openNotificationConnection() async {
    final useSSL = config.driverOptions['useSSL'] == true ||
        config.driverOptions['useSSL'] == 'true';
    final timeZone = TimeZoneSettings(config.timezone ?? 'UTC');
    timeZone.forceDecodeTimestamptzAsUTC = config.forceDecodeTimestamptzAsUTC;
    timeZone.forceDecodeTimestampAsUTC = config.forceDecodeTimestampAsUTC;
    timeZone.forceDecodeDateAsUTC = config.forceDecodeDateAsUTC;
    final conn = PostgreSQLConnection(
      config.host,
      config.port,
      config.database,
      username: config.username,
      password: config.password,
      timeZone: timeZone,
      encoding: _getEncoding(config.charset ?? 'utf8'),
      // The same TLS mode as the queries' connections.
      useSSL: useSSL,
      sslMode: _sslMode(useSSL),
    );
    await conn.open();
    try {
      await _onOpen(conn, config);
    } catch (_) {
      await conn.close();
      rethrow;
    }
    return PDONotificationConnection(
      notifications: conn.notifications
          .map((n) => DriverNotification(n.channel, n.payload, n.processID)),
      execute: (sql, timeout) =>
          conn.execute(sql, timeoutInSeconds: math.max(1, timeout.inSeconds)),
      close: conn.close,
    );
  }

  /// inicializa configurações ao conectar com o banco de dados
  /// The values are quoted as string literals; the schema comes formatted
  /// by PostgresConnector.formatSchema (quoted identifiers), and an empty
  /// one sets no search_path.
  Future<void> _onOpen(PostgreSQLExecutionContext conn, PDOConfig conf) async {
    final charset = conf.charset;
    if (charset != null) {
      await conn.execute(
          'SET client_encoding = ${PDOConfig.quotePgLiteral(charset)}');
    }
    final schema = conf.schema;
    if (schema != null && schema.trim().isNotEmpty) {
      await conn.execute('SET search_path TO $schema');
    }
    final timezone = conf.timezone;
    if (timezone != null) {
      await conn
          .execute('SET timezone TO ${PDOConfig.quotePgLiteral(timezone)}');
    }
    final applicationName = conf.applicationName;
    if (applicationName != null) {
      await conn.execute('SET application_name TO '
          '${PDOConfig.quotePgLiteral(applicationName)}');
    }
    for (final statement in conf.postgresTimeoutStatements()) {
      await conn.execute(statement);
    }
  }

  Future<T> runInTransaction<T>(Future<T> operation(PostgresPDOTransaction ctx),
      [int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = queryTimeoutInSeconds;
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
      timeoutInSeconds = queryTimeoutInSeconds;
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
    // Query builder bindings are normalized by Connection.prepareBindings()
    // before reaching this adapter. In particular, DateTime values are already
    // formatted as grammar date strings, matching Laravel/PDO behavior and
    // avoiding driver-specific binary timestamp/UTC conversions.
    if (timeoutInSeconds == null) {
      timeoutInSeconds = queryTimeoutInSeconds;
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

  /// `pg_types: 'uniform'`: the driver decodes time, timetz, interval, inet,
  /// cidr and point as the server's text and every array as `List<T?>`, as
  /// the other adapters return them. Done by postgres_fork while it decodes
  /// (no pass over the rows afterwards).
  static DecodingSettings _decodingSettings(PDOConfig config) =>
      config.uniformPgTypes
          ? const DecodingSettings(
              interval: IntervalDecoding.text,
              extendedTypes: ExtendedTypeDecoding.text,
              nullableArrays: true,
            )
          : const DecodingSettings();

  @override
  Future close() async {
    if (connection is PostgreSQLConnection) {
      await (connection as PostgreSQLConnection).close();
    } else if (connection is PgPool) {
      await (connection as PgPool).close();
    }
  }
}
