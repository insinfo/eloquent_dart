import 'package:eloquent/src/pdo/core/pdo_config.dart';
import 'package:eloquent/src/pdo/core/pdo_interface.dart';
import 'package:eloquent/src/pdo/core/pdo_result.dart';

import 'package:mysql_dart/mysql_dart.dart';
import '../core/operation_lock.dart';
import 'mysql_client_pdo_transaction.dart';

class MySqlClientPDO extends PDOInterface {
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
  MySqlClientPDO(this.config, {this.sessionStatements = const <String>[]}) {
    super.pdoInstance = this;
  }

  /// Statements run on every new physical connection (pool connections
  /// included), before it serves a query: `set names`, `time_zone`, ...
  final List<String> sessionStatements;

  /// Applies [sessionStatements] and the configured timeouts to [conn].
  Future<void> _initSession(MySQLConnection conn) async {
    for (final statement in sessionStatements) {
      await conn.execute(statement);
    }
    final lockTimeout = config.lockTimeout;
    if (lockTimeout != null && lockTimeout.trim().isNotEmpty) {
      final ms = PDOConfig.timeoutToMilliseconds(lockTimeout);
      // Whole seconds, at least 1 ("0" means no limit: one year).
      final seconds = ms <= 0 ? 31536000 : ((ms + 999) ~/ 1000);
      await conn.execute('set session lock_wait_timeout = $seconds');
    }
    final statementTimeout = config.statementTimeout;
    if (statementTimeout != null && statementTimeout.trim().isNotEmpty) {
      final ms = PDOConfig.timeoutToMilliseconds(statementTimeout);
      final version = (await conn.execute('select version() as v'))
          .rows
          .first
          .colByName('v');
      if ('$version'.toLowerCase().contains('mariadb')) {
        // MariaDB: any statement, in seconds (0 = no limit).
        await conn.execute('set session max_statement_time = ${ms / 1000}');
      } else {
        // MySQL only limits read-only SELECTs, in milliseconds.
        await conn.execute('set session max_execution_time = $ms');
      }
    }
  }

  /// CoreConnection
  late dynamic connection;

  Duration _timeout([int? timeoutInSeconds]) => Duration(
        seconds: timeoutInSeconds ?? defaultTimeoutInSeconds,
      );

  Object? _normalizedParams(dynamic params) {
    // Query builder bindings are normalized by Connection.prepareBindings()
    // before reaching this adapter. DateTime values should arrive formatted
    // with the grammar date format, mirroring Laravel/PDO behavior.
    if (params == null) {
      return null;
    }
    if (params is List && params.isEmpty) {
      return null;
    }
    if (params is Map && params.isEmpty) {
      return null;
    }
    return params;
  }

  PDOResults _toPDOResults(IResultSet result) {
    final rows = <Map<String, dynamic>>[];
    for (final row in result.rows) {
      rows.add(row.typedAssoc());
    }
    return PDOResults(rows, result.affectedRows.toInt(),
        insertId: _insertId(result));
  }

  //called from postgres_connector.dart
  Future<MySqlClientPDO> connect() async {
    final pool = config.pool == true;
    // driver_options: MySQLConnection.createConnection / MySQLConnectionPool
    // parameters (durations as Duration or seconds).
    final options = config.driverOptionsFor(
        'mysql_dart',
        pool
            ? const {
                'autoPreparedStatementCacheCapacity',
                'allowPublicKeyRetrieval',
                'serverPublicKey',
                'timeoutMs',
                'idleTestThreshold',
                'maxConnectionAge',
                'maxSessionUse',
                'maxErrorCount',
              }
            : const {
                'autoPreparedStatementCacheCapacity',
                'allowPublicKeyRetrieval',
                'serverPublicKey',
                'queueConcurrentCalls',
              });
    if (pool) {
      connection = MySQLConnectionPool(
        host: config.host,
        port: config.port,
        databaseName: config.database,
        userName: config.username ?? '',
        password: config.password,
        collation: config.charset ?? 'utf8mb4_general_ci',
        maxConnections: config.poolSize ?? 1,
        secure: config.sslmode?.toString() == 'require',
        onConnectionOpen: _initSession,
        autoPreparedStatementCacheCapacity:
            options.integer('autoPreparedStatementCacheCapacity') ?? 32,
        allowPublicKeyRetrieval:
            options.flag('allowPublicKeyRetrieval') ?? false,
        serverPublicKey: options.text('serverPublicKey'),
        timeoutMs: options.integer('timeoutMs') ?? 10000,
        idleTestThreshold: options.duration('idleTestThreshold') ??
            const Duration(minutes: 1),
        maxConnectionAge:
            options.duration('maxConnectionAge') ?? const Duration(hours: 12),
        maxSessionUse:
            options.duration('maxSessionUse') ?? const Duration(hours: 8),
        maxErrorCount: options.integer('maxErrorCount') ?? 64,
      );
    } else {
      connection = await MySQLConnection.createConnection(
        host: config.host,
        port: config.port,
        databaseName: config.database,
        userName: config.username ?? '',
        password: config.password ?? '',
        collation: config.charset ?? 'utf8mb4_general_ci',
        secure: config.sslmode?.toString() == 'require',
        autoPreparedStatementCacheCapacity:
            options.integer('autoPreparedStatementCacheCapacity') ?? 32,
        allowPublicKeyRetrieval:
            options.flag('allowPublicKeyRetrieval') ?? false,
        serverPublicKey: options.text('serverPublicKey'),
        queueConcurrentCalls: options.flag('queueConcurrentCalls') ?? true,
      );
    }
    if (connection is MySQLConnection) {
      final conn = connection as MySQLConnection;
      await conn.connect();
      await _initSession(conn);
    }

    return this;
  }

  /// Serializes callers of the single (non-pool) connection: mysql_dart
  /// rejects a second command with "connection is busy".
  final OperationLock _singleConnectionLock = OperationLock();

  Future<R> _single<R>(Future<R> Function() operation) =>
      connection is MySQLConnection
          ? _singleConnectionLock.run(operation)
          : operation();

  Future<T> runInTransaction<T>(
    Future<T> operation(MySqlClientPDOTransaction ctx), [
    int? timeoutInSeconds,
  ]) =>
      _single(() => _runInTransactionUnlocked(operation, timeoutInSeconds));

  Future<int> execute(String statement, [int? timeoutInSeconds]) =>
      _single(() => _executeUnlocked(statement, timeoutInSeconds));

  Future<PDOResults> query(String query,
          [dynamic params, int? timeoutInSeconds]) =>
      _single(() => _queryUnlocked(query, params, timeoutInSeconds));

  Future<T> _runInTransactionUnlocked<T>(
    Future<T> operation(MySqlClientPDOTransaction ctx), [
    int? timeoutInSeconds,
  ]) async {
    if (connection is MySQLConnectionPool) {
      final res = await (connection as MySQLConnectionPool)
          .transactional((transaCtx) async {
        final pdoCtx = MySqlClientPDOTransaction(transaCtx, this);
        return operation(pdoCtx);
      }).timeout(_timeout(timeoutInSeconds));
      return res;
    }

    final res =
        await (connection as MySQLConnection).transactional((transaCtx) async {
      final pdoCtx = MySqlClientPDOTransaction(transaCtx, this);
      return operation(pdoCtx);
    }).timeout(_timeout(timeoutInSeconds));
    return res;
  }

  /// Executa uma instrução SQL e retornar o número de linhas afetadas
  Future<int> _executeUnlocked(String statement, [int? timeoutInSeconds]) async {
    if (connection is MySQLConnectionPool) {
      final result = await (connection as MySQLConnectionPool)
          .execute(statement)
          .timeout(_timeout(timeoutInSeconds));
      return result.affectedRows.toInt();
    }

    final result = await (connection as MySQLConnection)
        .execute(statement)
        .timeout(_timeout(timeoutInSeconds));
    return result.affectedRows.toInt();
  }

  /// Prepares and executes an SQL statement
  /// [params] List<dynamic>
  Future<PDOResults> _queryUnlocked(String query,
      [dynamic params, int? timeoutInSeconds]) async {
    // Do not reformat DateTime here; this adapter receives prepared bindings.
    final normalizedParams = _normalizedParams(params);

    if (connection is MySQLConnectionPool) {
      final result = await Future<IResultSet>.value(
        (connection as MySQLConnectionPool)
            .withConnection((conn) => conn.execute(query, normalizedParams)),
      ).timeout(_timeout(timeoutInSeconds));
      return _toPDOResults(result);
    }

    final result = await (connection as MySQLConnection)
        .execute(query, normalizedParams)
        .timeout(_timeout(timeoutInSeconds));
    return _toPDOResults(result);
  }

  @override
  Future close() async {
    if (connection is MySQLConnectionPool) {
      await (connection as MySQLConnectionPool).close();
    }
    if (connection is MySQLConnection) {
      await (connection as MySQLConnection).close();
    }
  }
}

/// The id generated by the statement, from the OK packet (`null` when none).
Object? _insertId(IResultSet result) {
  final id = result.lastInsertID;
  if (id == BigInt.zero) return null;
  return id.isValidInt ? id.toInt() : id;
}
