import 'dart:async';
import 'dart:io';

import 'package:dpgsql/dpgsql.dart';
import 'package:eloquent/eloquent.dart';

import '../core/operation_lock.dart';
import 'dpgsql_driver_access.dart';
import 'dpgsql_pdo_transaction.dart';

class DpgsqlPDO extends PDOInterface {
  static const defaultTimeoutInSeconds = 30;

  @override
  PDOConfig config;

  DpgsqlPDO(this.config) {
    super.pdoInstance = this;
  }

  DpgsqlDataSource? _dataSource;
  DpgsqlConnection? _connection;

  @override
  Future<DpgsqlPDO> connect() async {
    final settings = _connectionSettingsFromConfig(config);
    if (config.pool == true) {
      _dataSource = DpgsqlDataSource.fromConnectionStringBuilder(
        settings,
      );
      await _dataSource!.warmup();
    } else {
      final connection = DpgsqlConnection.fromConnectionStringBuilder(settings);
      await connection.open();
      _connection = connection;
    }
    return this;
  }

  @override
  Future<T> runInTransaction<T>(
    Future<T> Function(PDOExecutionContext ctx) operation, [
    int? timeoutInSeconds,
  ]) {
    // A single connection runs one transaction/command at a time.
    if (_dataSource == null) {
      return _singleConnectionLock
          .run(() => _runInTransactionUnlocked(operation, timeoutInSeconds));
    }
    return _runInTransactionUnlocked(operation, timeoutInSeconds);
  }

  /// Serializes callers of the single (non-pool) connection.
  final OperationLock _singleConnectionLock = OperationLock();

  Future<T> _runInTransactionUnlocked<T>(
    Future<T> Function(PDOExecutionContext ctx) operation,
    int? timeoutInSeconds,
  ) async {
    final timeout = Duration(
      seconds: timeoutInSeconds ?? defaultTimeoutInSeconds,
    );
    final connection = await _openConnectionForOperation();
    DpgsqlTransaction? transaction;
    try {
      if (_dataSource == null) {
        // The driver's runInTransaction holds the shared connection: other
        // callers' commands wait for the commit instead of running inside
        // this transaction (with or without the adapter lock). It rolls back
        // itself when the operation throws.
        return await connection.runInTransaction((tx) {
          final context = DpgsqlPDOTransaction(connection, tx, this);
          return runWithTimeout(connection, () => operation(context), timeout);
        });
      }
      transaction = await connection.beginTransaction();
      final context = DpgsqlPDOTransaction(connection, transaction, this);
      final result =
          await runWithTimeout(connection, () => operation(context), timeout);
      await transaction.commit();
      return result;
    } catch (e) {
      if (e is TimeoutException) {
        // The cancelled command leaves the protocol state unknown.
        await _replaceAfterTimeout(connection);
        rethrow;
      }
      final connectionInvalid = _isConnectionFailure(e);
      if (connectionInvalid) {
        connection.markUnusable();
      }
      if (transaction != null && !connectionInvalid) {
        try {
          await transaction.rollback();
        } catch (_) {}
      }
      rethrow;
    } finally {
      if (_dataSource != null) {
        await connection.close();
      }
    }
  }

  @override
  Future<int> execute(String statement, [int? timeoutInSeconds]) async {
    final timeout = Duration(
      seconds: timeoutInSeconds ?? defaultTimeoutInSeconds,
    );
    return _withConnection((connection) async {
      final command = connection.createCommand(statement);
      return runWithTimeout(
          connection, () => command.executeNonQuery(), timeout);
    });
  }

  @override
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]) async {
    final timeout = Duration(
      seconds: timeoutInSeconds ?? defaultTimeoutInSeconds,
    );
    return _withConnection(
        (connection) => runQuery(connection, query, params, timeout, config));
  }

  /// Runs [query] on [connection] and maps the result. Shared with
  /// [DpgsqlPDOTransaction].
  static Future<PDOResults> runQuery(DpgsqlConnection connection, String query,
      dynamic params, Duration timeout,
      [PDOConfig? config]) {
    return runWithTimeout(connection, () async {
      // A CTE may wrap a SELECT or an UPDATE/DELETE without RETURNING: read
      // the rows, and fall back to the command's affected-row count.
      if (query.trimLeft().toLowerCase().startsWith('with')) {
        final reader = await connection.executeReader(
          query,
          parameters: parametersFromBindings(params),
        );
        final rows = <Map<String, dynamic>>[];
        try {
          while (await reader.read()) {
            rows.add(reader.toMap());
          }
          return PDOResults(
              rows, rows.isNotEmpty ? rows.length : reader.recordsAffected);
        } finally {
          await reader.close();
        }
      }
      if (expectsRows(query)) {
        final rows = await connection.executeMaps(
          query,
          parameters: parametersFromBindings(params),
        );
        return PDOResults(rows, rows.length);
      }
      final command = connection.createCommand(query);
      addParametersFromBindings(command, params);
      final affected = await command.executeNonQuery();
      return PDOResults([], affected);
    }, timeout);
  }

  /// Runs [operation] with [timeout]. On expiry the command is cancelled on
  /// the server (CancelRequest) and its pending response is awaited, so the
  /// connection's protocol state stays consistent; abandoning the read left
  /// the next command reading a half-consumed buffer.
  static Future<T> runWithTimeout<T>(DpgsqlConnection connection,
      Future<T> Function() operation, Duration timeout) async {
    final future = operation();
    try {
      return await future.timeout(timeout);
    } on TimeoutException {
      try {
        await connection.cancel();
      } catch (_) {}
      try {
        // Let the cancelled command finish ("canceling statement due to
        // user request") before the socket is released.
        await future.timeout(const Duration(seconds: 5));
      } catch (_) {}
      // Even when the response settled, the driver's read state after a
      // CancelRequest is not reliable: never reuse this socket.
      connection.markUnusable();
      throw TimeoutException(
          'PostgreSQL command exceeded $timeout and was cancelled.', timeout);
    }
  }

  @override
  bool get supportsQueryStream => true;

  @override
  Stream<Map<String, dynamic>> queryStream(String query,
      [dynamic params, int? fetchSize]) async* {
    // Server-side, incremental streaming via dpgsql's forward-only reader.
    // Memory stays roughly constant regardless of result-set size. For pooled
    // connections the connection is held for the lifetime of the stream and
    // returned to the pool once the stream is fully drained (or on error).
    // A single connection is held (locked) for the lifetime of the stream.
    final release =
        _dataSource == null ? await _singleConnectionLock.acquire() : null;
    final DpgsqlConnection connection;
    try {
      connection = await _openConnectionForOperation();
    } catch (_) {
      release?.call();
      rethrow;
    }
    DpgsqlDataReader? reader;
    try {
      reader = await connection.executeReader(
        query,
        parameters: parametersFromBindings(params),
      );
      while (await reader.read()) {
        yield reader.toMap();
      }
    } catch (e) {
      if (_isConnectionFailure(e)) {
        connection.markUnusable();
      }
      rethrow;
    } finally {
      if (reader != null) {
        try {
          await reader.close();
        } catch (_) {}
      }
      if (_dataSource != null) {
        await connection.close();
      }
      release?.call();
    }
  }

  /// Whether [sql] returns rows. EXPLAIN, VALUES, TABLE, FETCH and a
  /// parenthesized SELECT (`(select ...) union (select ...)`) went through
  /// executeNonQuery and their rows were lost.
  static bool expectsRows(String sql) {
    final lower = sql.trimLeft().toLowerCase();
    return lower.startsWith('select') ||
        lower.startsWith('with') ||
        lower.startsWith('show') ||
        lower.startsWith('explain') ||
        lower.startsWith('values') ||
        lower.startsWith('table') ||
        lower.startsWith('fetch') ||
        lower.startsWith('(') ||
        _containsReturningKeyword(lower);
  }

  @override
  DriverAccess driverAccess() => DpgsqlDriverAccess.forPdo(this);

  /// Run [action] with a driver connection (pooled or single), releasing it
  /// afterwards. Exposed for [DpgsqlDriverAccess].
  Future<T> useConnection<T>(
          Future<T> Function(DpgsqlConnection connection) action) =>
      _withConnection(action);

  /// Open a brand-new dedicated connection independent of the pool/single
  /// connection. The caller owns its lifecycle (used for LISTEN). Only valid in
  /// non-pool configuration when [_connection] exists, but always builds a
  /// fresh connection from the current settings.
  Future<DpgsqlConnection> openDedicatedConnection() async {
    final connection = DpgsqlConnection.fromConnectionStringBuilder(
      _connectionSettingsFromConfig(config),
    );
    await connection.open();
    return connection;
  }

  @override
  bool get supportsNotifications => true;

  /// A dedicated DpgsqlConnection, outside the pool, for LISTEN.
  @override
  Future<PDONotificationConnection> openNotificationConnection() async {
    final connection = await openDedicatedConnection();
    return PDONotificationConnection(
      notifications: connection.notifications
          .map((e) => DriverNotification(e.channel, e.payload, e.pid)),
      execute: (sql, timeout) =>
          connection.createCommand(sql).executeNonQuery(),
      close: connection.close,
    );
  }

  Future<T> _withConnection<T>(
      Future<T> Function(DpgsqlConnection connection) operation) {
    if (_dataSource == null) {
      return _singleConnectionLock
          .run(() => _withConnectionUnlocked(operation));
    }
    return _withConnectionUnlocked(operation);
  }

  Future<T> _withConnectionUnlocked<T>(
      Future<T> Function(DpgsqlConnection connection) operation) async {
    final connection = await _openConnectionForOperation();
    try {
      return await operation(connection);
    } catch (e) {
      if (e is TimeoutException) {
        await _replaceAfterTimeout(connection);
      } else if (_isConnectionFailure(e)) {
        connection.markUnusable();
      }
      rethrow;
    } finally {
      if (_dataSource != null) {
        await connection.close();
      }
    }
  }

  /// After a cancelled (timed-out) command the driver may still deliver part
  /// of its response to the next command, so the socket is not reused: a
  /// pooled connection is discarded on close, the single connection reopened.
  Future<void> _replaceAfterTimeout(DpgsqlConnection connection) async {
    connection.markUnusable();
    if (_dataSource != null || !identical(connection, _connection)) return;
    try {
      await connection.close();
    } catch (_) {}
    final fresh = DpgsqlConnection.fromConnectionStringBuilder(
      _connectionSettingsFromConfig(config),
    );
    await fresh.open();
    _connection = fresh;
  }

  Future<DpgsqlConnection> _openConnectionForOperation() async {
    if (_dataSource != null) {
      final connection = await _dataSource!.openConnection();
      return connection;
    }

    final connection = _connection;
    if (connection == null) {
      throw StateError('DpgsqlPDO is not connected.');
    }
    return connection;
  }

  @override
  Future close() async {
    final connection = _connection;
    if (connection != null) {
      await connection.close();
      _connection = null;
    }
    final dataSource = _dataSource;
    if (dataSource != null) {
      await dataSource.dispose();
      _dataSource = null;
    }
  }

  static void addParametersFromBindings(
    DpgsqlCommand command,
    dynamic bindings,
  ) {
    final parameters = parametersFromBindings(bindings);
    if (parameters != null) {
      command.parameters.addAll(parameters);
    }
  }

  static DpgsqlParameterCollection? parametersFromBindings(dynamic bindings) {
    // Query builder bindings are normalized by Connection.prepareBindings()
    // before reaching this adapter. Untyped DateTime values from the query
    // builder should normally arrive as grammar date strings, preserving the
    // Laravel/PDO semantics used by the postgres/postgresql-fork adapter.
    if (bindings == null) {
      return null;
    }
    final parameters = DpgsqlParameterCollection();
    if (bindings is Map) {
      bindings.forEach((key, value) {
        parameters.add(_parameterFromBinding(key.toString(), value));
      });
      return parameters.isEmpty ? null : parameters;
    }
    if (bindings is Iterable) {
      var index = 0;
      for (final value in bindings) {
        parameters.add(_parameterFromBinding('p$index', value));
        index++;
      }
      return parameters.isEmpty ? null : parameters;
    }
    parameters.add(_parameterFromBinding('p0', bindings));
    return parameters;
  }

  static DpgsqlParameter _parameterFromBinding(String name, dynamic value) {
    if (value is DateTime) {
      // A DateTime reaches the adapter with `datetime_bindings: 'native'` or
      // through direct PDO use. dpgsql would type it as `timestamp` with its
      // UTC fields (a local DateTime loses its wall clock, timestamptz gets
      // the wrong instant), so it is sent as untyped ISO text with offset and
      // microseconds, like postgres/postgres_v3/dargres: a `timestamp` column
      // takes the fields, a `timestamptz` column the instant.
      return DpgsqlParameter(name, formatDateTimeBinding(value));
    }

    return DpgsqlParameter(name, value);
  }

  /// `2024-03-10 12:34:56.789123-03:00` (`+00:00` for a UTC DateTime).
  static String formatDateTimeBinding(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final offset = value.isUtc ? Duration.zero : value.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final minutes = offset.inMinutes.abs();
    final fraction = (value.millisecond * 1000 + value.microsecond)
        .toString()
        .padLeft(6, '0');
    return '${value.year.toString().padLeft(4, '0')}-'
        '${two(value.month)}-'
        '${two(value.day)} '
        '${two(value.hour)}:'
        '${two(value.minute)}:'
        '${two(value.second)}.$fraction'
        '$sign${two(minutes ~/ 60)}:${two(minutes % 60)}';
  }

  static bool _containsReturningKeyword(String sql) {
    var index = sql.indexOf('returning');
    while (index != -1) {
      final before = index == 0 ? 32 : sql.codeUnitAt(index - 1);
      final afterIndex = index + 9;
      final after = afterIndex >= sql.length ? 32 : sql.codeUnitAt(afterIndex);
      if (!_isIdentifierChar(before) && !_isIdentifierChar(after)) {
        return true;
      }
      index = sql.indexOf('returning', index + 9);
    }
    return false;
  }

  static bool _isIdentifierChar(int code) {
    return (code >= 48 && code <= 57) ||
        (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        code == 95;
  }

  static DpgsqlConnectionStringBuilder _connectionSettingsFromConfig(
    PDOConfig config,
  ) {
    final settings = DpgsqlConnectionStringBuilder()
      ..host = config.host
      ..port = config.port
      ..database = config.database
      ..pooling = config.pool == true
      ..maxPoolSize = config.poolSize ?? 1
      ..maxAutoPrepare = 128
      ..autoPrepareMinUsages = 2
      ..useExtendedQueryForUnparameterizedCommands = true
      // postgres_fork (the default driver), postgres_v3 and dargres return
      // numeric as the exact server text; dpgsql's default is a double.
      ..decodeNumericAsString = true
      // pg_types: 'uniform': interval, ranges, geometric types... as the
      // server's text, as on the other adapters.
      ..decodeExtendedTypesAsText = config.uniformPgTypes;

    final username = config.username;
    if (username != null) {
      settings.username = username;
    }
    final password = config.password;
    if (password != null) {
      settings.password = password;
    }
    final sslMode = config.sslmode;
    if (sslMode != null) {
      settings.sslMode = _sslMode(sslMode);
    }
    final charset = config.charset;
    if (charset != null) {
      settings.encodingName = charset;
      settings.clientEncoding = charset;
    }
    final timezone = config.timezone;
    final hasTimezone = timezone != null && timezone.isNotEmpty;
    if (hasTimezone) {
      settings.timeZoneName = timezone;
      settings.useIanaTimeZoneDatabase = true;
    }
    final schema = config.schema;
    if (schema != null && schema.isNotEmpty) {
      settings.searchPath = schema;
    }
    final applicationName = config.applicationName;
    if (applicationName != null && applicationName.isNotEmpty) {
      settings.applicationName = applicationName;
    }
    final statementTimeout = config.statementTimeout;
    if (statementTimeout != null && statementTimeout.isNotEmpty) {
      settings.statementTimeout =
          PDOConfig.normalizePgTimeout(statementTimeout);
    }
    final lockTimeout = config.lockTimeout;
    if (lockTimeout != null && lockTimeout.isNotEmpty) {
      settings.lockTimeout = PDOConfig.normalizePgTimeout(lockTimeout);
    }
    final idleTimeout = config.idleInTransactionSessionTimeout;
    if (idleTimeout != null && idleTimeout.isNotEmpty) {
      settings.idleInTransactionSessionTimeout =
          PDOConfig.normalizePgTimeout(idleTimeout);
    }
    if (config.pool == true) {
      settings.noResetOnClose = true;
    }

    settings.forceDecodeTimestamptzAsUTC = config.forceDecodeTimestamptzAsUTC;
    settings.forceDecodeTimestampAsUTC = config.forceDecodeTimestampAsUTC;
    settings.forceDecodeDateAsUTC = config.forceDecodeDateAsUTC;

    // driver_options: dpgsql connection-string keywords, over the ones set
    // above.
    final options = config.driverOptionsFor('dpgsql', _connectionKeywords);
    if (options.values.isEmpty) return settings;
    return DpgsqlConnectionStringBuilder([
      settings.toString(),
      for (final entry in options.values.entries) '${entry.key}=${entry.value}',
    ].join(';'));
  }

  static const _connectionKeywords = {
    'Client Encoding',
    'Encoding',
    'TimeZone',
    'Force Decode Timestamptz As UTC',
    'Force Decode Timestamp As UTC',
    'Force Decode Date As UTC',
    'Use Current Offset For Local Timestamp',
    'Use IANA Time Zone Database',
    'IANA Time Zone Database Scope',
    'Throw On DateTime Infinity',
    'Host',
    'Port',
    'Username',
    'Password',
    'Database',
    'SSL Mode',
    'Trust Server Certificate',
    'Pooling',
    'Minimum Pool Size',
    'Maximum Pool Size',
    'Timeout',
    'Connection Idle Lifetime',
    'Connection Lifetime',
    'Connection Pruning Interval',
    'Max Auto Prepare',
    'Auto Prepare Min Usages',
    'No Reset On Close',
    'Search Path',
    'Application Name',
    'Statement Timeout',
    'Lock Timeout',
    'Idle In Transaction Session Timeout',
    'Decode Network Types As String',
    'Decode Uuid As String',
    'Decode Json As String',
    'Decode Numeric As String',
    'Use Custom Decimal',
    'Decode Extended Types As Text',
    'Infer String Parameters As Unknown',
    'Use Extended Query For Unparameterized Commands',
  };

  static SslMode _sslMode(String raw) {
    switch (raw.trim().toLowerCase().replaceAll('-', '')) {
      case 'allow':
        return SslMode.allow;
      case 'prefer':
        return SslMode.prefer;
      case 'require':
        return SslMode.require;
      case 'verifyca':
        return SslMode.verifyCa;
      case 'verifyfull':
        return SslMode.verifyFull;
      case 'disable':
      default:
        return SslMode.disable;
    }
  }

  static bool _isConnectionFailure(Object error) {
    if (error is SocketException) {
      return true;
    }
    if (error is PostgresException && error.sqlState.startsWith('08')) {
      return true;
    }
    if (error is DpgsqlException && error.innerException is SocketException) {
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('eof') ||
        message.contains('socket') ||
        message.contains('connection closed') ||
        message.contains('connection reset') ||
        message.contains('broken pipe') ||
        message.contains('socketbinaryinput');
  }
}
