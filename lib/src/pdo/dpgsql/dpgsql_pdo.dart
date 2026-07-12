import 'dart:async';
import 'dart:io';

import 'package:dpgsql/dpgsql.dart';
import 'package:eloquent/eloquent.dart';

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
  ]) async {
    final timeout = Duration(
      seconds: timeoutInSeconds ?? defaultTimeoutInSeconds,
    );
    final connection = await _openConnectionForOperation();
    DpgsqlTransaction? transaction;
    try {
      transaction = await connection.beginTransaction();
      final context = DpgsqlPDOTransaction(connection, transaction, this);
      final result = await operation(context).timeout(timeout);
      await transaction.commit();
      return result;
    } catch (e) {
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
      return command.executeNonQuery().timeout(timeout);
    });
  }

  @override
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]) async {
    final timeout = Duration(
      seconds: timeoutInSeconds ?? defaultTimeoutInSeconds,
    );
    return _withConnection((connection) async {
      if (expectsRows(query)) {
        final rows = await connection
            .executeMaps(
              query,
              parameters: parametersFromBindings(params),
            )
            .timeout(timeout);
        return PDOResults(rows, rows.length);
      }
      final command = connection.createCommand(query);
      addParametersFromBindings(command, params);
      final affected = await command.executeNonQuery().timeout(timeout);
      return PDOResults([], affected);
    });
  }

  @override
  Stream<Map<String, dynamic>> queryStream(String query,
      [dynamic params, int? fetchSize]) async* {
    // Server-side, incremental streaming via dpgsql's forward-only reader.
    // Memory stays roughly constant regardless of result-set size. For pooled
    // connections the connection is held for the lifetime of the stream and
    // returned to the pool once the stream is fully drained (or on error).
    final connection = await _openConnectionForOperation();
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
    }
  }

  static bool expectsRows(String sql) {
    final lower = sql.trimLeft().toLowerCase();
    return lower.startsWith('select') ||
        lower.startsWith('with') ||
        lower.startsWith('show') ||
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

  Future<T> _withConnection<T>(
      Future<T> Function(DpgsqlConnection connection) operation) async {
    final connection = await _openConnectionForOperation();
    try {
      return await operation(connection);
    } catch (e) {
      if (_isConnectionFailure(e)) {
        connection.markUnusable();
      }
      rethrow;
    } finally {
      if (_dataSource != null) {
        await connection.close();
      }
    }
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
      // Defensive fallback for direct PDO usage that bypasses
      // Connection.prepareBindings(). Keep this as text/unknown so PostgreSQL
      // infers timestamp/date from context instead of forcing Dpgsql's typed
      // DateTime binary encoding and changing timestamp without time zone
      // wall-clock values.
      return DpgsqlParameter(name, _formatDateTimeBinding(value));
    }

    return DpgsqlParameter(name, value);
  }

  static String _formatDateTimeBinding(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}-'
        '${two(value.month)}-'
        '${two(value.day)} '
        '${two(value.hour)}:'
        '${two(value.minute)}:'
        '${two(value.second)}';
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
      ..useExtendedQueryForUnparameterizedCommands = true;

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
      settings.statementTimeout = _pgTimeout(statementTimeout);
    }
    final lockTimeout = config.lockTimeout;
    if (lockTimeout != null && lockTimeout.isNotEmpty) {
      settings.lockTimeout = _pgTimeout(lockTimeout);
    }
    final idleTimeout = config.idleInTransactionSessionTimeout;
    if (idleTimeout != null && idleTimeout.isNotEmpty) {
      settings.idleInTransactionSessionTimeout = _pgTimeout(idleTimeout);
    }
    if (config.pool == true) {
      settings.noResetOnClose = true;
    }

    settings.forceDecodeTimestamptzAsUTC = config.forceDecodeTimestamptzAsUTC;
    settings.forceDecodeTimestampAsUTC = config.forceDecodeTimestampAsUTC;
    settings.forceDecodeDateAsUTC = config.forceDecodeDateAsUTC;

    return settings;
  }

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

  static String _pgTimeout(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == '0' || s == '0ms' || s == '0s' || s == '0min') {
      return '0';
    }
    const okUnits = ['ms', 's', 'min'];
    if (okUnits.any((u) => s.endsWith(u))) {
      return s;
    }
    if (RegExp(r'^\d+$').hasMatch(s)) {
      return '${s}ms';
    }
    throw ArgumentError(
      'Timeout invalido: "$raw". Use "250ms", "3s", "2min" ou "0".',
    );
  }
}
