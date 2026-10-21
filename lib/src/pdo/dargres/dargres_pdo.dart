import 'dart:async';

import 'package:dargres/dargres.dart' as dargres;
import 'package:eloquent/eloquent.dart';
import '../core/operation_lock.dart';
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

  /// Underlying dargres connection. Either a [dargres.CoreConnection] (single)
  /// or a [dargres.PostgreSqlPool] (pool). As of dargres 4.0.0 the pool no
  /// longer implements `ConnectionInterface`, but both expose the same
  /// `execute`/`queryNamed`/`runInTransaction`/`close` surface used here.
  dynamic connection;

  bool get _isPool => connection is dargres.PostgreSqlPool;

  // Same session as PostgresV2PDO._onOpen: client_encoding, timezone and
  // application_name go in the startup packet; search_path and the timeouts
  // run on every physical connection (pool slots and reconnects included)
  // before it serves a query.
  dargres.ConnectionSettings _settings(bool allowAttemptToReconnect) {
    // dargres 4.0.0: TimeZoneSettings is immutable; pass the decode flags via
    // the constructor instead of mutating fields after construction.
    final timeZone = dargres.TimeZoneSettings(
      config.timezone ?? 'UTC',
      forceDecodeTimestamptzAsUTC: config.forceDecodeTimestamptzAsUTC,
      forceDecodeTimestampAsUTC: config.forceDecodeTimestampAsUTC,
      forceDecodeDateAsUTC: config.forceDecodeDateAsUTC,
    );
    // driver_options: ConnectionSettings fields (durations as Duration or
    // seconds).
    final options = config.driverOptionsFor('dargres', const {
      'connectionTimeout',
      'commandTimeout',
      'cancelGracePeriod',
      'tcpKeepalive',
      'statementCacheCapacity',
      'queueConcurrentCalls',
      'numericAsString',
      'sourceAddress',
    });
    return dargres.ConnectionSettings(
      user: config.username ?? '',
      database: config.database,
      host: config.host,
      port: config.port,
      password: config.password,
      textCharset: config.charset ?? 'utf8',
      applicationName: config.applicationName,
      allowAttemptToReconnect: allowAttemptToReconnect,
      timeZone: timeZone,
      commandTimeout: _commandTimeout =
          options.duration('commandTimeout') ?? defaultTimeout,
      connectionTimeout:
          options.duration('connectionTimeout') ?? const Duration(seconds: 180),
      cancelGracePeriod:
          options.duration('cancelGracePeriod') ?? const Duration(seconds: 5),
      tcpKeepalive: options.flag('tcpKeepalive') ?? false,
      statementCacheCapacity: options.integer('statementCacheCapacity') ?? 64,
      queueConcurrentCalls: options.flag('queueConcurrentCalls') ?? true,
      sourceAddress: options.text('sourceAddress') ?? '',
      searchPath: config.schema,
      sessionStatements: config.postgresTimeoutStatements(),
      // postgres_fork (the default driver) returns numeric as an exact String.
      numericAsString: options.flag('numericAsString') ?? true,
    );
  }

  @override
  bool get supportsNotifications => true;

  /// A new CoreConnection, outside the pool, for LISTEN. It does not
  /// reconnect by itself: the listener reconnects and runs LISTEN again.
  @override
  Future<PDONotificationConnection> openNotificationConnection() async {
    final core = dargres.CoreConnection.fromSettings(_settings(false));
    await core.connect();
    return PDONotificationConnection(
      notifications: core.notifications.map((n) => DriverNotification(
          n['channel'] as String,
          n['payload'] as String,
          n['backendPid'] as int)),
      execute: (sql, timeout) => core.execute(sql),
      close: core.close,
    );
  }

  //called from postgres_connector.dart
  Future<DargresPDO> connect() async {
    final settings = _settings(config.allowReconnect ?? false);

    if (config.pool == true) {
      connection = dargres.PostgreSqlPool(config.poolSize ?? 1, settings,
          allowAttemptToReconnect: config.allowReconnect ?? false);
    } else {
      connection = dargres.CoreConnection.fromSettings(settings);
      await connection!.connect();
    }

    return this;
  }

  /// [defaultTimeout], or `driver_options` `commandTimeout`: also the pool's
  /// per-call timeout when the caller gives none.
  Duration _commandTimeout = defaultTimeout;

  Duration _timeout(int? timeoutInSeconds) => timeoutInSeconds == null
      ? _commandTimeout
      : Duration(seconds: timeoutInSeconds);

  Future<T> runInTransaction<T>(Future<T> operation(DargresPDOTransaction ctx),
      [int? timeoutInSeconds]) async {
    Future<T> body(dargres.TransactionContext transaCtx) {
      final pdoCtx = DargresPDOTransaction(transaCtx, this);
      return operation(pdoCtx);
    }

    if (_isPool) {
      return (connection as dargres.PostgreSqlPool)
          .runInTransaction<T>(body, timeout: _timeout(timeoutInSeconds));
    }
    return _onCore((core) => core.runInTransaction<T>(body), timeoutInSeconds);
  }

  /// Serializes callers of the single connection: while one caller's
  /// transaction runs, dargres rejects other queries on the connection ("A
  /// transaction is active; execute this query through its
  /// TransactionContext").
  final OperationLock _singleConnectionLock = OperationLock();

  /// Runs [action] on the single connection. A per-call timeout cancels the
  /// command on the server (CancelRequest) and waits for it to settle; without
  /// one, the connection's 30 s command timeout applies.
  Future<R> _onCore<R>(Future<R> Function(dargres.CoreConnection core) action,
          int? timeoutInSeconds) =>
      _singleConnectionLock
          .run(() => _onCoreUnlocked(action, timeoutInSeconds));

  Future<R> _onCoreUnlocked<R>(
      Future<R> Function(dargres.CoreConnection core) action,
      int? timeoutInSeconds) async {
    final core = connection as dargres.CoreConnection;
    final future = action(core);
    if (timeoutInSeconds == null) return future;
    final limit = Duration(seconds: timeoutInSeconds);
    try {
      return await future.timeout(limit);
    } on TimeoutException {
      try {
        await core.cancelCurrentQuery();
      } catch (_) {}
      try {
        await future.timeout(const Duration(seconds: 5));
      } catch (_) {
        // Expected: "canceling statement due to user request".
      }
      throw TimeoutException(
          'PostgreSQL command exceeded $limit and was cancelled.', limit);
    }
  }

  /// Executa uma instrução SQL e retornar o número de linhas afetadas
  Future<int> execute(String statement, [int? timeoutInSeconds]) {
    if (_isPool) {
      return (connection as dargres.PostgreSqlPool)
          .execute(statement, timeout: _timeout(timeoutInSeconds));
    }
    return _onCore((core) => core.execute(statement), timeoutInSeconds);
  }

  /// Prepares and executes an SQL statement
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]) async {
    final dargres.Results results;
    if (_isPool) {
      results = await (connection as dargres.PostgreSqlPool).queryNamed(
          query, params ?? [],
          placeholderIdentifier: dargres.PlaceholderIdentifier.onlyQuestionMark,
          timeout: _timeout(timeoutInSeconds));
    } else {
      results = await _onCore(
          (core) => core.queryNamed(query, params ?? [],
              placeholderIdentifier:
                  dargres.PlaceholderIdentifier.onlyQuestionMark),
          timeoutInSeconds);
    }
    final pdoResult = PDOResults(results.toMaps(), results.rowsAffected.value);
    return pdoResult;
  }

  @override
  Future close() async {
    await connection!.close();
  }
}
