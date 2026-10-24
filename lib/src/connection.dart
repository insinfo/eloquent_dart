import 'dart:async';

import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/doctrine/connection.dart' as doctrine;
import 'package:eloquent/src/doctrine/schema/mysql_schema_manager.dart';
import 'package:eloquent/src/doctrine/schema/postgres_schema_manager.dart';

/// A database connection: runs statements on a [PDOExecutionContext],
/// creates query and schema builders and manages transactions.
///
/// [PostgresConnection] and [MySqlConnection] add each driver's grammars and
/// post processor.
class Connection with DetectsLostConnections implements ConnectionInterface {
  /// A query timeout of 300 seconds. Not read by the driver adapters, which
  /// have their own defaults.
  static const defaultTimeout = const Duration(seconds: 300);

  /// The PDO execution context that runs the statements (and the reads, when
  /// [readPdo] is null).
  PDOExecutionContext pdo;

  /// The PDO execution context for reads, or null to read through [pdo].
  PDOExecutionContext? readPdo;

  /// Called with this connection to reconnect after the connection was lost;
  /// see [setReconnector].
  Future<dynamic> Function(Connection)? reconnector;

  /// The grammar that compiles queries.
  late QueryGrammar queryGrammar;

  /// The grammar that compiles schema statements, set by [getSchemaBuilder]
  /// when null.
  SchemaGrammar? schemaGrammar;

  /// The processor applied to query results.
  Processor? postProcessor;

  /// The transaction depth.
  @Deprecated('Use transactionLevel() / isInTransaction.')
  int get transactions => transactionLevel();

  /// Query log and listeners. Shared with the connections handed to
  /// transaction callbacks, so queries run through `ctx` are logged and
  /// reported like the others.
  _QueryObservers _observers = _QueryObservers();

  /// The queries run on this connection while logging is on: maps with
  /// `query`, `bindings` and `time` (milliseconds), as in Laravel.
  List get queryLog => _observers.log;
  set queryLog(List value) => _observers.log = value;

  /// Whether queries are being logged.
  bool get loggingQueries => _observers.logging;
  set loggingQueries(bool value) => _observers.logging = value;

  /// Whether the current code runs in a "dry run"; see [pretend].
  ///
  /// Setting it puts the whole connection (every request that uses it, and
  /// its transaction connections) in a dry run until it is set back to
  /// false; [pretend] only affects the code of its callback.
  @Deprecated('Use pretend() and pretending().')
  bool get pretendingProp => pretending();
  @Deprecated('Use pretend() and pretending().')
  set pretendingProp(bool value) => _observers.pretending = value;

  /// The name of the connected database.
  late String _databaseName;

  /// The table prefix for the connection.
  String _tablePrefix = '';

  /// The database connection configuration options.
  Map<String, dynamic> _config = {};

  String? _cachedDriverName;

  doctrine.DoctrineConnection? doctrineConnection;
  AbstractSchemaManager? doctrineSchemaManager;

  /// How many times [tryAgainIfCausedByLostConnection] reconnects and runs a
  /// statement again before giving up.
  int tryReconnectLimit = 10;

  /// Creates a connection over [pdo], with the database name, table prefix
  /// and configuration options.
  Connection(this.pdo,
      [this._databaseName = '',
      this._tablePrefix = '',
      this._config = const <String, dynamic>{}]) {
    //print('lib\src\connection.dart Connection _config $_config');

    // First we will setup the default properties. We keep track of the DB
    // name we are connected to since it is needed when some reflective
    // type commands are run such as checking whether a table exists.

    // We need to initialize a query grammar and the query post processors
    // which are both very important parts of the database abstractions
    // so we initialize these to their default values while starting.
    useDefaultQueryGrammar();
    useDefaultPostProcessor();
    _poolReconnect = parsePoolReconnect(_config['pool_reconnect']);
  }

  /// `'keep'` or `'replace'`; see [parsePoolReconnect].
  late final String _poolReconnect;

  /// Parses the `pool_reconnect` option, which decides what a lost
  /// connection does with `'pool': true`:
  ///
  /// - `'keep'` (the default): the pool is kept. The pool discards the dead
  ///   connection and opens a new one when needed, so the statements other
  ///   requests run on the pool are not affected.
  /// - `'replace'`: the pool is closed and a new one is made (through the
  ///   [reconnector]); the statements other requests run on the old pool
  ///   fail.
  ///
  /// Without a pool the connection is always reopened. Throws
  /// [ArgumentError] for another value.
  static String parsePoolReconnect(Object? value) {
    if (value == null) return 'keep';
    final mode = value.toString().toLowerCase();
    if (mode == 'keep' || mode == 'replace') return mode;
    throw ArgumentError.value(
        value, 'pool_reconnect', "Expected 'keep' or 'replace'.");
  }

  /// Whether a lost connection is left to the pool ([parsePoolReconnect]).
  bool get _keepsPool =>
      _poolReconnect == 'keep' && pdo.getConfig().pool == true;

  /// Sets the query grammar to [getDefaultQueryGrammar].
  void useDefaultQueryGrammar() {
    this.queryGrammar = getDefaultQueryGrammar();
  }

  /// Returns the query grammar a new connection uses; driver subclasses
  /// return their dialect's.
  QueryGrammar getDefaultQueryGrammar() {
    return QueryGrammar();
  }

  /// Sets the schema grammar to [getDefaultSchemaGrammar].
  void useDefaultSchemaGrammar() {
    this.schemaGrammar = getDefaultSchemaGrammar();
  }

  /// Returns the schema grammar [useDefaultSchemaGrammar] sets: null here,
  /// driver subclasses return their dialect's.
  dynamic getDefaultSchemaGrammar() {}

  /// Sets the post processor to [getDefaultPostProcessor].
  void useDefaultPostProcessor() {
    this.postProcessor = getDefaultPostProcessor();
  }

  /// Returns the post processor a new connection uses.
  Processor getDefaultPostProcessor() {
    return Processor();
  }

  /// Returns a schema builder for this connection, setting the default
  /// schema grammar first when none is set.
  SchemaBuilder getSchemaBuilder() {
    if (Utils.is_null(schemaGrammar)) {
      useDefaultSchemaGrammar();
    }
    return SchemaBuilder(this);
  }

  /// Returns a [QueryBuilder] on [table].
  QueryBuilder table(String table) {
    return this.query().from(table);
  }

  /// A [QueryBuilder2] (Dart 3 API: enums, named parameters with a fixed
  /// meaning, typed results) on [table].
  QueryBuilder2 table2(String table) {
    return QueryBuilder2(this, table);
  }

  /// Returns a [QueryBuilder] with this connection's grammar and post
  /// processor.
  QueryBuilder query() {
    return QueryBuilder(this, this.getQueryGrammar(), this.getPostProcessor());
  }

  /// Returns a raw SQL expression: [value] goes into the query as written,
  /// not as a binding.
  QueryExpression raw(dynamic value) {
    return QueryExpression(value);
  }

  /// Runs a select statement and returns its first row, or null when there
  /// is none.
  Future<Map<String, dynamic>?> selectOne(String query,
      [bindings = const [], int? timeoutInSeconds]) async {
    final records = await this.select(query, bindings, true, timeoutInSeconds);
    return records.isNotEmpty ? records.first : null;
  }

  /// Runs a select statement on the write PDO ([pdo]) and returns its rows.
  Future<List<Map<String, dynamic>>> selectFromWriteConnection(query,
      [bindings = const []]) {
    return this.select(query, bindings, false);
  }

  /// Runs a select statement and returns its rows.
  ///
  /// With [useReadPdo] it runs on [getReadPdo], else on [pdo]. In a "dry
  /// run" ([pretend]) it returns no rows.
  ///
  /// After a lost connection it is run again on a new one only when the
  /// driver refused it before sending it (see
  /// [tryAgainIfCausedByLostConnection]): a select can have side effects
  /// (`nextval`, a function that writes), so one that may have reached the
  /// server is not run twice.
  Future<List<Map<String, dynamic>>> select(String query,
      [List bindings = const [],
      bool useReadPdo = true,
      int? timeoutInSeconds]) async {
    //print('Connection@select timeout $timeoutInSeconds');

    final res = await this._run(query, bindings,
        (me, query, bindings, timeoutInSeconds) async {
      if (me.pretending()) {
        return <Map<String, dynamic>>[];
      }
      // For select statements, we'll simply execute the query and return the
      // rows of the result set, one map per row.
      final pdoL = me.getPdoForSelect(useReadPdo);
      final params = me.prepareBindings(bindings);
      return pdoL.query(query, params, timeoutInSeconds);
    }, timeoutInSeconds);

    return res as List<Map<String, dynamic>>;
  }

  /// Streams the rows of a select statement through a server-side cursor or
  /// incremental reader, keeping memory roughly constant regardless of the
  /// size of the result set.
  ///
  /// Throws [UnsupportedError] on driver adapters without streaming support
  /// (only the `dpgsql` adapter implements it today). [fetchSize] is an
  /// advisory hint for rows buffered per round-trip.
  ///
  /// Note: unlike [select], this does not go through the reconnect wrapper —
  /// a dropped connection mid-stream surfaces as an error to the consumer.
  @override
  Stream<Map<String, dynamic>> cursor(String query,
      [List bindings = const [],
      bool useReadPdo = true,
      int? fetchSize]) async* {
    final ambient = _ambient();
    if (ambient != null) {
      yield* ambient.cursor(query, bindings, useReadPdo, fetchSize);
      return;
    }
    if (this.pretending()) {
      _reportQuery(query, bindings, Duration.zero, null, _pretendScope());
      return;
    }
    final pdoL = this.getPdoForSelect(useReadPdo);
    if (!pdoL.supportsQueryStream) {
      yield* _sqlCursor(pdoL, query, bindings, fetchSize);
      return;
    }
    final params = this.prepareBindings(bindings);
    if (!_observers.active) {
      yield* pdoL.queryStream(query, params, fetchSize);
      return;
    }
    // Reported when the stream ends (time until the last row).
    final watch = Stopwatch()..start();
    Object? error;
    try {
      yield* pdoL.queryStream(query, params, fetchSize);
    } catch (e) {
      error = e;
      rethrow;
    } finally {
      _reportQuery(query, bindings, watch.elapsed, error);
    }
  }

  static int _cursorSequence = 0;

  /// [cursor] for drivers without an incremental reader, on PostgreSQL:
  /// `DECLARE name NO SCROLL CURSOR FOR <query>` and `FETCH FORWARD n` in a
  /// loop, inside the current transaction or one opened for the stream on
  /// [pdoL] (and closed when it ends or is cancelled; cancelling the
  /// subscription waits for that). Rows are fetched [fetchSize] (default
  /// 1000) at a time and only when the consumer asks for them.
  Stream<Map<String, dynamic>> _sqlCursor(
      PDOExecutionContext pdoL, String query, List bindings, int? fetchSize) {
    if (_resolvedDriverName() != 'pgsql') {
      throw UnsupportedError(
          'cursor() needs the dpgsql adapter or PostgreSQL (SQL cursors); on '
          '${getDriverName()} use lazyById/chunkById.');
    }
    final size = fetchSize == null || fetchSize < 1 ? 1000 : fetchSize;
    final name = 'eloquent_cursor_${++_cursorSequence}';
    if (isInTransaction) return _fetchCursor(this, name, query, bindings, size);

    // The cursor lives in a transaction that stays open while the stream is
    // consumed: the rows are handed over through a paused controller.
    late StreamController<Map<String, dynamic>> controller;
    Completer<void>? resumed;
    Future<void>? running;
    var cancelled = false;
    controller = StreamController<Map<String, dynamic>>(
      onListen: () {
        running = pdoL.pdoInstance.runInTransaction((pdoCtx) async {
          final ctx = _childConnection(pdoCtx);
          await for (final row
              in _fetchCursor(ctx, name, query, bindings, size)) {
            if (cancelled) break;
            controller.add(row);
            if (controller.isPaused) {
              await (resumed = Completer<void>()).future;
            }
          }
        }).then<void>((_) {}, onError: (Object e, StackTrace s) {
          if (!cancelled) controller.addError(e, s);
        }).whenComplete(() {
          // Not awaited: after a cancel, close() waits for onCancel, which
          // waits for this future.
          controller.close();
        });
      },
      onPause: () {},
      onResume: () {
        final waiting = resumed;
        resumed = null;
        if (waiting != null && !waiting.isCompleted) waiting.complete();
      },
      onCancel: () {
        cancelled = true;
        final waiting = resumed;
        resumed = null;
        if (waiting != null && !waiting.isCompleted) waiting.complete();
        // `subscription.cancel()` completes once the cursor is closed and
        // the transaction ended.
        return running;
      },
    );
    return controller.stream;
  }

  static Stream<Map<String, dynamic>> _fetchCursor(Connection connection,
      String name, String query, List bindings, int size) async* {
    await connection.statement(
        'declare $name no scroll cursor for $query', bindings);
    try {
      while (true) {
        final rows = await connection.select('fetch forward $size from $name');
        for (final row in rows) {
          yield row;
        }
        if (rows.length < size) break;
      }
    } finally {
      await connection.statement('close $name');
    }
  }

  /// Returns direct, driver-specific access (COPY, pipelining, LISTEN/NOTIFY,
  /// raw connection), or `null` when the active driver adapter has no such
  /// capabilities (only the `dpgsql` adapter implements it today).
  @override
  DriverAccess? driver() {
    final ambient = _ambient();
    if (ambient != null) return ambient.driver();
    return this.getPdo().driverAccess();
  }

  /// One LISTEN listener per physical PDO, shared with the connections given
  /// to transaction callbacks.
  static final Expando<PostgresNotificationListener> _notificationListeners =
      Expando<PostgresNotificationListener>();

  /// Whether the driver adapter implements PostgreSQL LISTEN/NOTIFY.
  bool get supportsNotifications => pdo.pdoInstance.supportsNotifications;

  /// Sends a PostgreSQL `NOTIFY` via `pg_notify(channel, payload)`. Inside a
  /// transaction (on the `ctx` connection) the notification is delivered only
  /// when the transaction commits, and dropped on rollback. The payload must
  /// be shorter than 8000 bytes.
  ///
  /// ```dart
  /// await db.transaction((ctx) async {
  ///   await ctx.table('tramita_fila').insert(item);
  ///   await ctx.notify('tramita_fila', '${item['id']}');
  /// });
  /// ```
  Future<void> notify(String channel, [String payload = '']) async {
    _assertNotifications('notify');
    await this.select(
        'select 1 from pg_notify(?::text, ?::text)', [channel, payload], false);
  }

  /// Returns a stream of the notifications sent to [channel] (PostgreSQL
  /// `LISTEN`).
  ///
  /// All channels share one dedicated connection (outside the pool) that
  /// reconnects by itself; see [notificationListener] for `ready()`,
  /// `onReconnect` and `onError`.
  ///
  /// ```dart
  /// final sub =
  ///     db.notifications('tramita_fila').listen((n) => acordarWorker());
  /// await db.notificationListener.ready();
  /// // ...
  /// await sub.cancel(); // UNLISTEN
  /// ```
  Stream<DriverNotification> notifications(String channel) {
    return notificationListener.channel(channel);
  }

  /// The shared LISTEN listener of this connection, created on first use and
  /// closed by [disconnect].
  PostgresNotificationListener get notificationListener {
    _assertNotifications('notifications');
    final pdoInstance = pdo.pdoInstance;
    return _notificationListeners[pdoInstance] ??=
        PostgresNotificationListener(pdoInstance.openNotificationConnection);
  }

  void _assertNotifications(String method) {
    if (!supportsNotifications) {
      throw UnsupportedError(
          '$method() requires a PostgreSQL driver adapter (driver '
          '"${getDriverName()}" has no LISTEN/NOTIFY).');
    }
  }

  // ------------------------------------------------------ advisory locks

  /// Takes a PostgreSQL transaction-level advisory lock on [key]
  /// (`pg_advisory_xact_lock`): waits until no other transaction holds the
  /// same key, and keeps it until this transaction commits or rolls back
  /// (there is no unlock). It serializes only the code that asks for the
  /// same key: unlike `LOCK TABLE`, reads, other writes to the table and
  /// foreign key checks go on.
  ///
  /// [key] is a String (hashed with `hashtextextended`; use a name such as
  /// `'normas.tipo_norma'` or `'tipo_norma:nome:$nome'`) or an int (a
  /// bigint key used as is). Needs a transaction ([StateError] outside one,
  /// where the lock would end with the statement) and PostgreSQL
  /// ([UnsupportedError] on other drivers).
  ///
  /// ```dart
  /// await db.transaction((ctx) async {
  ///   await ctx.advisoryLock('normas.tipo_norma');
  ///   // check the name, insert: one transaction at a time
  /// });
  /// ```
  Future<void> advisoryLock(Object key, [int? timeoutInSeconds]) async {
    await this.select(
        'select 1 from pg_advisory_xact_lock(${_advisoryKey(key, 'advisoryLock')})',
        [key],
        false,
        timeoutInSeconds);
  }

  /// Takes the lock of [advisoryLock] without waiting
  /// (`pg_try_advisory_xact_lock`): true when the lock was taken (held until
  /// the transaction ends), false when another transaction holds [key].
  Future<bool> tryAdvisoryLock(Object key) async {
    final rows = await this.select(
        'select pg_try_advisory_xact_lock(${_advisoryKey(key, 'tryAdvisoryLock')}) as locked',
        [key],
        false);
    final locked = rows.first['locked'];
    return locked == true || locked == 't' || locked == 1;
  }

  /// The SQL key expression of [key] after checking driver and transaction.
  String _advisoryKey(Object key, String method) {
    if (_resolvedDriverName() != 'pgsql') {
      throw UnsupportedError('$method() needs PostgreSQL '
          '(pg_advisory_xact_lock); driver "${getDriverName()}".');
    }
    if (!isInTransaction) {
      throw StateError('$method() needs a transaction: the lock is released '
          'when the transaction ends, so outside one it would end with the '
          'statement.');
    }
    if (key is String) return 'hashtextextended(?::text, 0)';
    if (key is int) return '?::bigint';
    throw ArgumentError.value(key, 'key', 'Expected a String or an int.');
  }

  /// Returns [getReadPdo] when [useReadPdo] is true, else [getPdo].
  PDOExecutionContext getPdoForSelect([bool useReadPdo = true]) {
    return useReadPdo ? this.getReadPdo() : this.getPdo();
  }

  /// Runs an insert statement and returns its [PDOResults]; the same as
  /// [statement].
  Future<PDOResults> insert(query,
      [bindings = const [], int? timeoutInSeconds]) async {
    return this.statement(query, bindings, timeoutInSeconds);
  }

  /// The same as [statement].
  Future<PDOResults> rawQuery(query,
      [bindings = const [], int? timeoutInSeconds]) async {
    return this.statement(query, bindings, timeoutInSeconds);
  }

  /// Runs an update statement and returns the number of rows affected.
  Future<int> update(String query,
      [List bindings = const [], int? timeoutInSeconds]) {
    return this.affectingStatement(query, bindings, timeoutInSeconds);
  }

  /// Runs a delete statement and returns the number of rows affected.
  Future<int> delete(String query,
      [List bindings = const [], int? timeoutInSeconds]) {
    return this.affectingStatement(query, bindings, timeoutInSeconds);
  }

  /// Runs an SQL statement on [pdo] and returns its [PDOResults] (empty in
  /// a "dry run").
  Future<PDOResults> statement(String query,
      [bindingsP = const [], int? timeoutInSeconds]) async {
    final resp = await this.run(query, bindingsP,
        (me, query, bindings, timeoutInSeconds) async {
      if (me.pretending()) {
        return PDOResults(<Map<String, dynamic>>[], 0);
      }

      final pdoL = me.getPdo();
      final params = me.prepareBindings(bindings);
      return await pdoL.query(query, params, timeoutInSeconds);
    }, timeoutInSeconds);

    return resp as PDOResults;
  }

  /// Runs [query] without bindings and returns a one-element list with the
  /// number of rows affected, or `true` in a "dry run" ([pretend]).
  Future<dynamic> execute(String query, [int? timeoutInSeconds]) async {
    final resp = await this.run(query, [],
        (me, query, bindings, timeoutInSeconds) async {
      if (me.pretending()) {
        return true;
      }

      var pdoL = me.getPdo();
      var res = await pdoL.execute(query, timeoutInSeconds);

      return [res];
    }, timeoutInSeconds);

    return resp;
  }

  /// Runs an SQL statement and returns the number of rows affected (0 in a
  /// "dry run").
  Future<int> affectingStatement(String query,
      [List<dynamic> bindingsP = const [], int? timeoutInSeconds]) async {
    final resp = await this.run(query, bindingsP,
        (me, query, bindings, timeoutInSeconds) async {
      if (me.pretending()) {
        return 0;
      }

      // For update or delete statements, we want to get the number of rows
      // affected by the statement and return that back to the developer.
      final _pdo = me.getPdo();
      final params = me.prepareBindings(bindings);
      final res = await _pdo.query(query, params, timeoutInSeconds);
      return res.rowsAffected;
    }, timeoutInSeconds);

    return resp as int;
  }

  /// Runs a raw, unprepared query against the PDO connection (Laravel's
  /// `DB::unprepared`, PHP's `PDO::exec`): no bindings, through the simple
  /// query protocol on every PostgreSQL adapter, so [query] may hold several
  /// statements (a script). They run as one implicit transaction unless the
  /// text has its own `BEGIN`/`COMMIT`, so `CREATE INDEX CONCURRENTLY` and
  /// `VACUUM` must be alone. Returns the rows affected.
  Future<int> unprepared(String query, [int? timeoutInSeconds]) async {
    final resp = await this.run(query, [],
        (me, query, bindings, timeoutInSeconds) async {
      if (me.pretending()) {
        return 0;
      }

      return me.getPdo().execute(query, timeoutInSeconds);
    }, timeoutInSeconds);
    return resp as int;
  }

  /// Returns [bindingsP] converted for the driver.
  ///
  /// [DateTime] values become date strings in the grammar's format (unless
  /// the `datetime_bindings` option is `'native'`) and `false` becomes `0`
  /// on drivers other than PostgreSQL. The conversions go into a copy:
  /// [bindingsP] itself is not modified.
  dynamic prepareBindings(List<dynamic> bindingsP) {
    var grammar = getQueryGrammar();
    String? driverName;
    // Converted values go into a copy: the caller's list (often a builder's
    // binding bucket, reused by the next execution) is never modified.
    List<dynamic>? bindings;

    for (var i = 0; i < bindingsP.length; i++) {
      var key = i;
      var value = bindingsP[key];
      // Ported from Laravel's Connection::prepareBindings().
      //
      // We need to transform all instances of DateTimeInterface into the actual
      // date string. Each query grammar maintains its own date string format
      // so we'll just ask the grammar for the format to get from the date.
      //
      // Keep this conversion before the PDO adapter layer. PostgreSQL adapters
      // such as postgres/postgresql-fork and dpgsql must receive the query
      // builder DateTime binding as an SQL date string, preserving Laravel/PDO
      // semantics for timestamp without time zone instead of forcing a Dart
      // DateTime binary/UTC encoding path.
      if (value is DateTime) {
        if (_nativeDateTimeBindings()) continue;
        (bindings ??= List<dynamic>.of(bindingsP))[key] =
            grammar.formatDateTime(value);
      } else if (value == false) {
        driverName ??= _resolvedDriverName();
        if (driverName != 'pgsql') {
          (bindings ??= List<dynamic>.of(bindingsP))[key] = 0;
        }
      }
    }

    return bindings ?? bindingsP;
  }

  String _resolvedDriverName() {
    return _cachedDriverName ??= getDriverName();
  }

  bool? _cachedNativeDateTimeBindings;

  /// `datetime_bindings: 'native'` passes DateTime bindings to the driver
  /// unchanged (microseconds and, on PostgreSQL, the time zone are kept);
  /// the default `'string'` formats them with the grammar date format
  /// (`yyyy-MM-dd HH:mm:ss`), as Laravel does.
  bool _nativeDateTimeBindings() {
    return _cachedNativeDateTimeBindings ??=
        PDOConfig.parseDateTimeBindings(getConfig('datetime_bindings')) ==
            DateTimeBindings.native;
  }

  /// Clears cached config-derived values when tests or custom integrations
  /// mutate the connection config map after construction.
  void clearConfigCache() {
    _cachedDriverName = null;
    _cachedNativeDateTimeBindings = null;
  }

  /// Runs [callback] in a transaction and returns its result.
  ///
  /// Outside a transaction this opens one (`BEGIN`/`COMMIT`, `ROLLBACK` on
  /// error). Called on a connection that is already inside a transaction (the
  /// `ctx` of an outer callback), it opens a nested transaction as a
  /// `SAVEPOINT eloquent_savepoint_<level>`: success releases it, an error
  /// rolls back to it and is rethrown, and the outer transaction stays usable
  /// if the caller catches the error. A second physical transaction is never
  /// opened; a driver without SAVEPOINT support throws
  /// [UnsupportedNestedTransactionException].
  ///
  /// Use [transactionIfNeeded] to join an existing transaction instead.
  ///
  /// [timeoutInSeconds] is handed to the driver for the outer transaction and
  /// used for the SAVEPOINT commands of a nested one.
  @override
  Future<T> transaction<T>(Future<T> Function(Connection ctx) callback,
      [int? timeoutInSeconds]) {
    final ambient = _ambient();
    if (ambient != null) {
      // `db.transaction` inside a transactionScope: a SAVEPOINT of the
      // scope's transaction, and the scope follows it.
      return ambient.transaction<T>(
          (ctx) => _runInScope(ctx, () => callback(ctx)), timeoutInSeconds);
    }
    if (isInTransaction) {
      return _savepointTransaction(callback, timeoutInSeconds);
    }
    return _withMappedErrors(pdo.pdoInstance.runInTransaction<T>(
        (pdoCtx) => callback(_childConnection(pdoCtx)), timeoutInSeconds));
  }

  /// [future], with a driver error the callback already saw as a
  /// [UniqueConstraintViolationException] rethrown as that exception.
  static Future<T> _withMappedErrors<T>(Future<T> future) async {
    try {
      return await future;
    } catch (e, stackTrace) {
      final mapped = UniqueConstraintViolationException.mappedFrom(e);
      if (mapped == null || identical(mapped, e)) rethrow;
      Error.throwWithStackTrace(mapped, stackTrace);
    }
  }

  /// Runs [callback] in a transaction, reusing the current one (no SAVEPOINT)
  /// when this connection is already inside a transaction.
  @override
  Future<T> transactionIfNeeded<T>(Future<T> Function(Connection ctx) callback,
      [int? timeoutInSeconds]) {
    final ambient = _ambient();
    if (ambient != null) return callback(ambient);
    if (isInTransaction) {
      return callback(this);
    }
    return transaction<T>(callback, timeoutInSeconds);
  }

  Future<T> _savepointTransaction<T>(
      Future<T> Function(Connection ctx) callback,
      int? timeoutInSeconds) async {
    final parent = pdo;
    if (!parent.supportsSavepoints) {
      throw UnsupportedNestedTransactionException();
    }
    final level = parent.transactionLevel + 1;
    return parent.runInSavepoint(
        savepointName(level),
        () => callback(_childConnection(NestedPDOTransaction(parent, level))),
        timeoutInSeconds);
  }

  /// SAVEPOINT name of a nested transaction at [level] (2 for the first).
  static String savepointName(int level) => 'eloquent_savepoint_$level';

  /// [newConnectionForPdo] sharing this connection's log, listeners,
  /// event dispatcher and reconnector.
  Connection _childConnection(PDOExecutionContext pdoContext) {
    final child = newConnectionForPdo(pdoContext);
    child._observers = _observers;
    child._events = _events;
    child._root = _root ?? this;
    return child;
  }

  // ------------------------------------------------- ambient transaction

  /// The connection this one was made from for a transaction callback
  /// (`ctx`), or null for a connection made by the manager.
  Connection? _root;

  /// Zone key of the [transactionScope] of this (root) connection.
  final Object _scopeKey = Object();

  /// Scopes running in this isolate; while 0 no query looks up the zone.
  static int _openScopes = 0;

  /// The `ctx` of the [transactionScope] the current code runs in, when this
  /// is the root connection (`db`) and the scope is still running.
  Connection? _ambient() {
    if (_openScopes == 0 || _root != null) return null;
    final scope = Zone.current[_scopeKey];
    if (scope is _AmbientScope && scope.active) return scope.connection;
    return null;
  }

  /// Runs [callback] in an *ambient* [transaction]: while [callback] runs, the
  /// connection it was called on (`db`, the one made by the manager) also
  /// runs in the transaction, so code that uses `db` instead of `ctx` (a
  /// repository called from the callback) takes part in it instead of
  /// running on another connection of the pool, or waiting for the
  /// transaction to end on a single connection.
  ///
  /// Inside the scope, `db.transaction(...)` becomes a SAVEPOINT of the
  /// scope's transaction, `db.transactionIfNeeded(...)` joins it and
  /// `db.isInTransaction` is true. Calls from code started inside the scope
  /// but still running after it ended (an unawaited future, a timer) use the
  /// connection normally again. [outsideTransaction] runs something on `db`
  /// outside the scope on purpose (a log that must survive a rollback).
  ///
  /// The scope only covers the async calls of [callback] (it is a [Zone]):
  /// queries of other requests on the same `db` are not affected. Concurrent
  /// calls inside the scope (`Future.wait`) share the transaction's
  /// connection, one at a time.
  ///
  /// ```dart
  /// await db.transactionScope((ctx) async {
  ///   await processoRepository.encaminhar(dados); // uses `db` inside
  ///   // db.transaction inside becomes a SAVEPOINT:
  ///   await pecaRepository.juntar(dados);
  ///   await db.outsideTransaction(() => logRepository.gravar(evento));
  /// });
  /// ```
  Future<T> transactionScope<T>(Future<T> Function(Connection ctx) callback,
      [int? timeoutInSeconds]) {
    final root = _root ?? this;
    return transaction<T>(
        (ctx) => root._runInScope(ctx, () => callback(ctx)), timeoutInSeconds);
  }

  /// Runs [callback] outside the [transactionScope] the current code is in:
  /// queries on this connection's `db` inside it use the connection
  /// normally (another connection of the pool), and are not rolled back with
  /// the scope. Outside a scope it just runs [callback].
  ///
  /// Inside a scope it needs a pool of at least 2 connections (`'pool':
  /// true`, `'poolsize' >= 2`): with a single connection there is no
  /// "outside" while the transaction holds it, so it throws [StateError]
  /// instead of waiting for the transaction forever. With a pool it still
  /// waits for a free connection: when every connection of the pool is held
  /// by a transaction that calls `outsideTransaction`, they wait for each
  /// other until the pool's connect/acquire timeout. Size the pool above the
  /// number of such transactions running at the same time.
  Future<T> outsideTransaction<T>(FutureOr<T> Function() callback) async {
    final root = _root ?? this;
    if (root.isInTransactionScope && !root._poolHasSecondConnection()) {
      throw StateError(
          'outsideTransaction() inside a transactionScope needs a connection '
          "pool of at least 2 connections ('pool': true, 'poolsize' >= 2): "
          'the transaction holds the only connection, so the query would '
          'wait for the transaction to end.');
    }
    return await runZoned(callback, zoneValues: {root._scopeKey: null});
  }

  /// Whether the PDO is a pool that can hand out a connection while the
  /// transaction holds another one (the adapters default to a pool of one).
  bool _poolHasSecondConnection() {
    final config = pdo.getConfig();
    return config.pool == true && (config.poolSize ?? 1) >= 2;
  }

  /// Whether the current code runs inside a [transactionScope] of this
  /// connection.
  bool get isInTransactionScope {
    final root = _root ?? this;
    if (_openScopes == 0) return false;
    final scope = Zone.current[root._scopeKey];
    return scope is _AmbientScope && scope.active;
  }

  Future<T> _runInScope<T>(Connection ctx, Future<T> Function() body) async {
    final scope = _AmbientScope(ctx);
    _openScopes++;
    try {
      return await runZoned(body, zoneValues: {_scopeKey: scope});
    } finally {
      scope.active = false;
      _openScopes--;
    }
  }

  /// Creates a connection of this same kind (grammar, processor, config) over
  /// another PDO context, such as a transaction context.
  Connection newConnectionForPdo(PDOExecutionContext pdoContext) {
    return Connection(
        pdoContext, this._databaseName, this._tablePrefix, this._config);
  }

  /// Returns the transaction depth of this connection: `0` outside a
  /// transaction, `1` in the callback of a top-level [transaction], `2+`
  /// inside SAVEPOINTs.
  @override
  int transactionLevel() {
    return _ambient()?.transactionLevel() ?? pdo.transactionLevel;
  }

  /// Whether this connection runs inside a transaction (the `ctx` given to a
  /// [transaction] callback, or `db` inside a [transactionScope]).
  @override
  bool get isInTransaction =>
      _ambient()?.isInTransaction ?? pdo.isInTransaction;

  /// Whether [transaction] can nest via SAVEPOINT on this connection.
  @override
  bool get supportsSavepoints => pdo.supportsSavepoints;

  /// Runs [callback] in "dry run" mode and returns the queries it would have
  /// run.
  ///
  /// [callback] receives this connection (or takes no parameters). No
  /// statement reaches the database: selects return no rows and other
  /// statements report nothing done. The result holds query log entries
  /// ([queryLog]); the connection's own query log is not changed.
  ///
  /// The dry run covers only the async calls of [callback] (it is a
  /// [Zone], as in [transactionScope]): queries of other requests on the
  /// same connection run normally, and a nested `pretend` returns its own
  /// queries and leaves the outer one pretending. A query started in
  /// [callback] but run after it returned (an unawaited future) is not
  /// pretended.
  Future<dynamic> pretend(Function callback) async {
    final scope = _PretendScope();
    _openPretends++;
    try {
      // Basically to make the database connection "pretend", we will just
      // return the default values for all the query methods, then we will
      // return the queries that were "executed" within the callback.
      await runZoned(
          () async =>
              await (callback is Function() ? callback() : callback(this)),
          zoneValues: {(_root ?? this)._pretendKey: scope});
    } finally {
      scope.active = false;
      _openPretends--;
    }
    return scope.log;
  }

  /// Zone key of the [pretend] calls of this (root) connection.
  final Object _pretendKey = Object();

  /// [pretend] calls running in this isolate; while 0 no query looks up the
  /// zone.
  static int _openPretends = 0;

  /// The [pretend] call the current code runs in, on this connection or the
  /// one it was made from for a transaction.
  _PretendScope? _pretendScope() {
    if (_openPretends == 0) return null;
    final scope = Zone.current[(_root ?? this)._pretendKey];
    return scope is _PretendScope && scope.active ? scope : null;
  }

  /// Runs [query] through [callback] and returns what it returns.
  ///
  /// The statement is timed and reported to the query log and the
  /// [listen] listeners when any is active. A unique constraint violation
  /// is rethrown as a [UniqueConstraintViolationException]. After a lost
  /// connection it reconnects; the statement is run again only when the
  /// driver refused it before sending it, since a write may have been
  /// committed before the connection dropped (see
  /// [tryAgainIfCausedByLostConnection]).
  Future<dynamic> run(
      String query,
      dynamic bindings,
      Future<dynamic> Function(Connection con, String query, dynamic bindings,
              int? timeoutInSeconds)
          callback,
      [int? timeoutInSeconds]) {
    return _run(query, bindings, callback, timeoutInSeconds);
  }

  /// [run], with the ambient transaction and [pretend] applied.
  Future<dynamic> _run(
      String query,
      dynamic bindings,
      Future<dynamic> Function(Connection con, String query, dynamic bindings,
              int? timeoutInSeconds)
          callback,
      int? timeoutInSeconds) async {
    final ambient = _ambient();
    if (ambient != null) {
      return ambient._run(query, bindings, callback, timeoutInSeconds);
    }
    final pretend = _pretendScope();
    // Fast path: nothing observes the queries, so nothing is timed.
    if (!_observers.active && pretend == null) {
      return _runUnobserved(query, bindings, callback, timeoutInSeconds);
    }
    final watch = Stopwatch()..start();
    Object? error;
    try {
      return await _runUnobserved(query, bindings, callback, timeoutInSeconds);
    } catch (e) {
      error = e;
      rethrow;
    } finally {
      watch.stop();
      _reportQuery(query, bindings, watch.elapsed, error, pretend);
    }
  }

  Future<dynamic> _runUnobserved(
      String query,
      dynamic bindings,
      Future<dynamic> Function(Connection con, String query, dynamic bindings,
              int? timeoutInSeconds)
          callback,
      int? timeoutInSeconds) async {
    var result;
    // Here we will run this query. If an exception occurs we'll determine if
    // it was caused by a connection that has been lost. If that is the cause,
    // we'll try to re-establish connection and, when that is safe, re-run
    // the query with a fresh connection.
    try {
      result = await this
          .runQueryCallback(query, bindings, callback, timeoutInSeconds);
    } catch (e, stackTrace) {
      final unique = UniqueConstraintViolationException.fromDriverError(
          e, query, bindings);
      if (unique != null) Error.throwWithStackTrace(unique, stackTrace);
      return await this.tryAgainIfCausedByLostConnection(
          e, query, bindings, callback, timeoutInSeconds,
          stackTrace: stackTrace);
    }

    return result;
  }

  /// Calls [callback] with this connection, [query], [bindings] and
  /// [timeoutInSeconds] and returns its result.
  Future<dynamic> runQueryCallback(
      String query,
      bindings,
      Future<dynamic> Function(Connection con, String query, dynamic bindings,
              int? timeoutInSeconds)
          callback,
      int? timeoutInSeconds) async {
    // The callback runs the SQL against the PDO connection; [run] times and
    // logs it.
    var result;
    result = await callback(this, query, bindings, timeoutInSeconds);

    return result;
  }

  /// Reconnects and runs the statement again after [e] if [e] was caused by
  /// a lost connection and running it again is safe.
  ///
  /// Rethrows [e] (with [stackTrace]) when it was not caused by a lost
  /// connection, inside a transaction (the transaction was lost with the
  /// connection) or without a [reconnector].
  ///
  /// A statement that may have reached the server is not run again: a write
  /// the server committed just before the connection dropped would be
  /// written twice, and a select can have side effects too (`nextval`, a
  /// function that writes). Then it reconnects, so the next statement
  /// works, and rethrows [e]. A statement is run again only when the driver
  /// refused it before sending it, because it already knew the connection
  /// was closed (the server ended an idle session; see
  /// [causedByLostConnectionBeforeSending]).
  ///
  /// With `'pool': true` and `pool_reconnect: 'keep'` (the default) it does
  /// not reconnect: the pool already discarded the dead connection, and the
  /// statement runs again on another one (see [parsePoolReconnect]).
  ///
  /// Otherwise it reconnects and runs [callback] again, up to
  /// [tryReconnectLimit] times, waiting [delay] milliseconds times the
  /// attempt number (at most 5 s) before each one. An error not caused by a
  /// lost connection is rethrown at once; when the attempts run out, the
  /// last error is thrown.
  Future<dynamic> tryAgainIfCausedByLostConnection(
      dynamic e,
      String query,
      bindings,
      Future<dynamic> Function(
              Connection, String, dynamic, int? timeoutInSeconds)
          callback,
      int? timeoutInSeconds,
      {int delay = 1000,
      StackTrace? stackTrace}) async {
    // Inside a transaction the lost connection took the transaction with it:
    // re-running only this statement on a new connection would be wrong.
    if (!this.causedByLostConnection(e) ||
        this.isInTransaction ||
        this.reconnector == null) {
      Error.throwWithStackTrace(e as Object, stackTrace ?? StackTrace.current);
    }
    if (!causedByLostConnectionBeforeSending(e)) {
      await _reconnectForNextStatement();
      Error.throwWithStackTrace(e as Object, stackTrace ?? StackTrace.current);
    }

    // Counted per call: concurrent statements retry independently.
    final keepPool = _keepsPool;
    Object lastError = e;
    for (var attempt = 1; attempt <= tryReconnectLimit; attempt++) {
      // Linear backoff, capped at 5 s. A kept pool hands another connection
      // at once, so its first attempt does not wait.
      final wait = keepPool && attempt == 1 ? 0 : delay * attempt;
      await Future.delayed(Duration(milliseconds: wait > 5000 ? 5000 : wait));
      try {
        // A kept pool already discarded the dead connection.
        if (!keepPool) await this.reconnect();
      } catch (error) {
        // Nothing was sent: try again while the server cannot be reached.
        if (!this.causedByLostConnection(error)) rethrow;
        lastError = error;
        continue;
      }
      try {
        return await this
            .runQueryCallback(query, bindings, callback, timeoutInSeconds);
      } catch (error) {
        if (!this.causedByLostConnection(error)) rethrow;
        if (!causedByLostConnectionBeforeSending(error)) {
          await _reconnectForNextStatement();
          rethrow;
        }
        lastError = error;
      }
    }
    throw lastError;
  }

  /// [reconnect] after a statement was lost and is not run again; a failure
  /// is left to the next statement, which reconnects again. Nothing to do
  /// for a kept pool ([parsePoolReconnect]).
  Future<void> _reconnectForNextStatement() async {
    if (_keepsPool) return;
    try {
      await this.reconnect();
    } catch (_) {}
  }

  /// Messages (lower case) of the driver adapters that refuse a statement
  /// without sending it, because the connection is already closed.
  static const _notSentMessages = [
    // postgres (postgres_fork), postgres_v3
    'but connection is not open',
    // mysql_dart
    'can not execute query: connection closed',
    // dpgsql (checked before the command is written)
    'the connection to the server was lost',
    // dargres (the exception prints the server's last notice instead)
    'connection is closed, cannot execute',
    // a pool that could not open a connection
    "can't create a connection",
    'connection refused',
  ];

  /// PostgreSQL 14+ idle_session_timeout: the server only ends a session
  /// that is waiting for a command, so the statement did not run.
  static final _idleSessionTimeout = RegExp(r'\b57P05\b');

  /// Whether [e], caused by a lost connection, means the statement was not
  /// sent (or did not run), so running it again cannot repeat a write.
  ///
  /// It recognizes the errors the adapters throw for a connection the
  /// server already closed (`Attempting to execute query, but connection is
  /// not open` on postgres and postgres_v3, `connection closed` before the
  /// query on mysql_dart, `the connection to the server was lost` on
  /// dpgsql, `Connection is closed, cannot execute query` on dargres) and
  /// the idle-session timeout (57P05). An error raised while waiting for
  /// the reply (`terminating connection due to administrator command`, a
  /// socket closed during the read) is not one of them.
  bool causedByLostConnectionBeforeSending(dynamic e) {
    final text = StringBuffer('$e');
    try {
      final message = e.message;
      if (message is String) text.write('\n$message');
    } catch (_) {
      // The exception has no message field.
    }
    final all = text.toString();
    if (_idleSessionTimeout.hasMatch(all)) return true;
    final lower = all.toLowerCase();
    for (final message in _notSentMessages) {
      if (lower.contains(message)) return true;
    }
    return false;
  }

  /// Closes the LISTEN listener and the PDOs of this connection ([pdo] and
  /// a distinct [readPdo]).
  ///
  /// An error closing the listener or a PDO is printed, not thrown, and
  /// does not keep the others open.
  Future<void> disconnect() async {
    // Both read before the first await: a reconnection may give this
    // connection new PDOs while the old ones close.
    final pdoInstance = this.pdo.pdoInstance;
    final readInstance = this.readPdo?.pdoInstance;
    final listener = _notificationListeners[pdoInstance];
    if (listener != null) {
      _notificationListeners[pdoInstance] = null;
      try {
        await listener.close();
      } catch (e, s) {
        print('eloquent@disconnect error $e $s');
      }
    }
    await _close(pdoInstance);
    if (readInstance != null && !identical(readInstance, pdoInstance)) {
      await _close(readInstance);
    }
  }

  static Future<void> _close(PDOInterface pdoInstance) async {
    try {
      await pdoInstance.close();
    } catch (e, s) {
      print('eloquent@disconnect error $e $s');
    }
  }

  /// Reconnects through [reconnector] (the manager's
  /// [DatabaseManager.reconnect]: with `'pool': true` it replaces the whole
  /// pool, and the statements other requests run on it fail). A lost
  /// connection only calls it with `pool_reconnect: 'replace'` (see
  /// [parsePoolReconnect]); calling it directly always reconnects.
  ///
  /// Throws a [LogicException] when there is no [reconnector].
  Future<void> reconnect() async {
    //print('Connection@reconnect() ${this.reconnector}');
    if (this.reconnector != null) {
      return await this.reconnector!(this);
    }

    throw LogicException('Lost connection and no reconnector available.');
  }

  /// Adds [query] to the query log when logging is on; [time] is in
  /// milliseconds.
  dynamic logQuery(String query, bindings, [time = null]) {
    if (this.loggingQueries) {
      this.queryLog.add({'query': query, 'bindings': bindings, 'time': time});
    }
  }

  /// Logs the statement (to the log of [pretend] when given) and calls the
  /// listeners. A listener that throws does not change the statement's
  /// outcome: its error goes to the listener's `onError`, or is printed.
  void _reportQuery(
      String query, dynamic bindings, Duration elapsed, Object? error,
      [_PretendScope? pretend]) {
    final observers = _observers;
    observers.total += elapsed;
    final list = bindings is List ? bindings : const <dynamic>[];
    if (pretend != null) {
      pretend.log.add({
        'query': query,
        'bindings': list,
        'time': elapsed.inMicroseconds / 1000
      });
    } else if (observers.logging) {
      logQuery(query, list, elapsed.inMicroseconds / 1000);
    }
    if (observers.listeners.isEmpty) return;
    final event = QueryExecuted(
      sql: query,
      bindings: List<dynamic>.unmodifiable(list),
      time: elapsed,
      connection: this,
      error: error,
    );
    // A copy: a listener may unsubscribe itself while being called.
    for (final listener in List.of(observers.listeners)) {
      try {
        listener.callback(event);
      } catch (e, s) {
        final onError = listener.onError;
        if (onError != null) {
          try {
            onError(e, s);
            continue;
          } catch (_) {
            // Printed below with the listener's error.
          }
        }
        // Not Zone.handleUncaughtError: in the root zone that ends the
        // program, and a log listener must not take a server down.
        print('eloquent: query listener error: $e\n$s');
      }
    }
  }

  /// Registers a database query listener with the connection.
  ///
  /// [callback] receives every statement run on this connection (and on the
  /// connections given to its transaction callbacks), with its time and
  /// error. Returns a function that removes the listener.
  ///
  /// An error thrown by [callback] does not change the statement's outcome
  /// (the statement already ran: failing it would make a caller retry a
  /// committed write) and does not stop the other listeners. It goes to
  /// [onError] when given, else it is printed.
  ///
  /// ```dart
  /// final stop =
  ///     db.listen((q) => print('${q.time.inMilliseconds} ms ${q.sql}'));
  /// ```
  void Function() listen(void Function(QueryExecuted query) callback,
      {void Function(Object error, StackTrace stackTrace)? onError}) {
    final listener = _QueryListener(callback, onError);
    _observers.listeners.add(listener);
    return () => _observers.listeners.remove(listener);
  }

  /// Calls [handler] for every statement slower than [threshold].
  void Function() onSlowQuery(
      Duration threshold, void Function(QueryExecuted query) handler) {
    return listen((query) {
      if (query.time > threshold) handler(query);
    });
  }

  /// Total time spent running statements on this connection (and its
  /// transaction connections) while a query log or listener was active.
  Duration totalQueryDuration() => _observers.total;

  /// Resets [totalQueryDuration].
  void resetTotalQueryDuration() {
    _observers.total = Duration.zero;
  }

  /// Not implemented: throws [UnimplementedError].
  void fireConnectionEvent(String event) {
    throw UnimplementedError();
  }

  /// Returns the milliseconds elapsed since [start], a [Utils.microtime]
  /// value (microseconds), rounded to 2 decimal places as in Laravel.
  double getElapsedTime(int start) {
    return ((Utils.microtime() - start) / 10).round() / 100;
  }

  /// Returns true: the Doctrine schema port is part of this package.
  bool isDoctrineAvailable() {
    return true;
  }

  /// Returns the column [column] of [table] as the Doctrine schema manager
  /// reads it.
  Future<Column> getDoctrineColumn(String table, String column) async {
    final schema = getDoctrineSchemaManager();
    final tableDetails = await schema.listTableDetails(table);
    return tableDetails.getColumn(column);
  }

  /// Returns the Doctrine schema manager of this connection's driver,
  /// created on first use.
  ///
  /// Throws an [UnsupportedError] on drivers other than PostgreSQL and
  /// MySQL/MariaDB.
  AbstractSchemaManager getDoctrineSchemaManager() {
    doctrineSchemaManager ??= _createDoctrineSchemaManager();
    return doctrineSchemaManager!;
  }

  AbstractPlatform? _databasePlatform;

  /// The Doctrine platform of this connection's driver: DDL for [Schema],
  /// [Table] and [SchemaDiff], type declarations and SQL expressions.
  AbstractPlatform getDatabasePlatform() {
    return _databasePlatform ??= switch (getDriverName()) {
      'pgsql' => PostgreSQLPlatform(),
      'mysql' => MySQLPlatform(),
      final driver =>
        throw UnsupportedError('No database platform for driver "$driver".'),
    };
  }

  /// Returns the Doctrine connection over this connection's PDO, created on
  /// first use.
  doctrine.DoctrineConnection getDoctrineConnection() {
    doctrineConnection ??= doctrine.DoctrineConnection(
      pdo: pdo,
      driver: getDriverName(),
      database: getDatabaseName(),
      config: getConfigs(),
    );
    return doctrineConnection!;
  }

  AbstractSchemaManager _createDoctrineSchemaManager() {
    final driver = getDriverName();

    switch (driver) {
      case 'pgsql':
      case 'postgres':
      case 'postgresql':
      case 'postgres_v3':
      case 'dargres':
      case 'dpgsql':
        return PostgreSQLSchemaManager(this);
      case 'mysql':
      case 'mariadb':
        return MySqlSchemaManager(this);
    }

    throw UnsupportedError(
        'Doctrine schema manager is not available for driver "$driver".');
  }

  /// Returns [pdo].
  PDOExecutionContext getPdo() {
    return this.pdo;
  }

  /// Returns the PDO context for reads: [readPdo] when set, else [pdo];
  /// inside a transaction always [pdo].
  PDOExecutionContext getReadPdo() {
    if (isInTransaction) {
      return this.getPdo();
    }

    return this.readPdo ?? this.pdo;
  }

  /// Replaces [pdo] and drops the cached Doctrine connection and schema
  /// manager.
  ///
  /// Throws an [Exception] inside a transaction.
  dynamic setPdo(PDOExecutionContext pdo) {
    if (isInTransaction) {
      //RuntimeException
      throw Exception("Can't swap PDO instance while within transaction.");
    }

    this.pdo = pdo;
    this.doctrineConnection = null;
    this.doctrineSchemaManager = null;

    return this;
  }

  /// Sets [readPdo]; null makes reads use [pdo].
  dynamic setReadPdo(PDOExecutionContext? pdo) {
    this.readPdo = pdo;
    return this;
  }

  /// Sets [reconnector].
  dynamic setReconnector(Future<dynamic> Function(Connection) reconnectorP) {
    this.reconnector = reconnectorP;
    return this;
  }

  /// Returns the connection name (the `name` option), or null.
  dynamic getName() {
    return this.getConfig('name');
  }

  /// Returns the configuration option [option], or null when it is not set.
  dynamic getConfig(String option) {
    //print('getConfig ${this._config}');
    //throw UnimplementedError();
    return this._config[option];
  }

  Map<String, dynamic> getConfigs() {
    return this._config;
  }

  /// Returns the driver name in lower case.
  ///
  /// It is the `driver` option, else the driver of the PDO configuration,
  /// else derived from the `driver_implementation` option (the PostgreSQL
  /// implementations give `'pgsql'`), else `''`.
  String getDriverName() {
    final configuredDriver = getConfig('driver')?.toString().toLowerCase();
    if (configuredDriver != null && configuredDriver.isNotEmpty) {
      return configuredDriver;
    }

    final pdoDriver = pdo.getConfig().driver.toLowerCase();
    if (pdoDriver.isNotEmpty) {
      return pdoDriver;
    }

    final implementation =
        getConfig('driver_implementation')?.toString().toLowerCase();
    if (implementation == null || implementation.isEmpty) {
      return '';
    }

    switch (implementation) {
      case 'postgres':
      case 'postgres_v3':
      case 'dargres':
      case 'dpgsql':
        return 'pgsql';
    }

    return implementation;
  }

  /// Returns the query grammar used by the connection.
  QueryGrammar getQueryGrammar() {
    return this.queryGrammar;
  }

  /// Sets the query grammar used by the connection.
  void setQueryGrammar(QueryGrammar grammarP) {
    this.queryGrammar = grammarP;
  }

  /// Returns the schema grammar used by the connection.
  ///
  /// Fails when none is set yet; [getSchemaBuilder] sets the default one.
  SchemaGrammar getSchemaGrammar() {
    return this.schemaGrammar!;
  }

  /// Sets the schema grammar used by the connection.
  void setSchemaGrammar(SchemaGrammar grammarP) {
    this.schemaGrammar = grammarP;
  }

  /// Returns the query post processor used by the connection.
  dynamic getPostProcessor() {
    return this.postProcessor;
  }

  /// Sets the query post processor used by the connection.
  dynamic setPostProcessor(Processor processor) {
    this.postProcessor = processor;
  }

  /// Returns the event dispatcher given to [setEventDispatcher].
  dynamic getEventDispatcher() {
    return this._events;
  }

  /// The dispatcher given to [setEventDispatcher] (kept for Laravel parity;
  /// query events are delivered through [listen]).
  dynamic _events;

  /// Sets the event dispatcher (kept for Laravel parity; query events are
  /// delivered through [listen]).
  dynamic setEventDispatcher($events) {
    this._events = $events;
  }

  /// Returns whether the current code runs in a "dry run"; see [pretend].
  bool pretending() {
    return _pretendScope() != null || _observers.pretending;
  }

  /// Returns the query log; see [queryLog].
  dynamic getQueryLog() {
    return this.queryLog;
  }

  /// Clears the query log.
  dynamic flushQueryLog() {
    this.queryLog = [];
  }

  /// Enables the query log on the connection.
  dynamic enableQueryLog() {
    this.loggingQueries = true;
  }

  /// Disables the query log on the connection.
  void disableQueryLog() {
    this.loggingQueries = false;
  }

  /// Returns whether queries are being logged.
  bool logging() {
    return this.loggingQueries;
  }

  /// Returns the name of the connected database.
  String getDatabaseName() {
    return this._databaseName;
  }
  // String getDatabaseName() {
  //   // PDOConfig config;
  //   return pdo.getConfig().database;
  // }

  /// Sets the name of the connected database.
  void setDatabaseName(String database) {
    this._databaseName = database;
  }

  /// Returns the table prefix for the connection.
  String getTablePrefix() {
    return this._tablePrefix;
  }

  /// Sets the table prefix of the connection and of its query and schema
  /// grammars.
  void setTablePrefix(String prefix) {
    this._tablePrefix = prefix;

    this.getQueryGrammar().setTablePrefix(prefix);
    this.schemaGrammar?.setTablePrefix(prefix);
  }

  /// Sets this connection's table prefix on [grammar] and returns it.
  dynamic withTablePrefix(BaseGrammar grammar) {
    grammar.setTablePrefix(this._tablePrefix);

    return grammar;
  }
}

/// Query log and listeners of a connection and of the connections created
/// for its transactions.
class _QueryObservers {
  bool logging = false;
  List log = [];

  /// Set through the deprecated `Connection.pretendingProp`: the whole
  /// connection pretends.
  bool pretending = false;
  Duration total = Duration.zero;
  final List<_QueryListener> listeners = <_QueryListener>[];

  /// Whether statements must be timed and reported.
  bool get active => logging || listeners.isNotEmpty;
}

/// A [Connection.listen] callback and its error handler.
final class _QueryListener {
  _QueryListener(this.callback, this.onError);

  final void Function(QueryExecuted query) callback;
  final void Function(Object error, StackTrace stackTrace)? onError;
}

/// A [Connection.pretend] call, kept in the zone.
final class _PretendScope {
  /// The queries the callback would have run.
  final List<Map<String, dynamic>> log = [];

  /// False once the callback returned: a query started inside it and run
  /// later (an unawaited future) runs normally, whether or not another
  /// pretend is running then.
  bool active = true;
}

/// The transaction of a [Connection.transactionScope], kept in the zone.
final class _AmbientScope {
  _AmbientScope(this.connection);

  /// The `ctx` of the scope's transaction.
  final Connection connection;

  /// False once the scope's callback returned.
  bool active = true;
}
