import 'dart:async';

import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/doctrine/connection.dart' as doctrine;
import 'package:eloquent/src/doctrine/schema/mysql_schema_manager.dart';
import 'package:eloquent/src/doctrine/schema/postgres_schema_manager.dart';

/// posgresql Connection implementation
class Connection with DetectsLostConnections implements ConnectionInterface {
  /// default query Timeout =  300 seconds
  static const defaultTimeout = const Duration(seconds: 300);

  ///
  /// The active PDO connection.
  ///
  /// @var PDO
  ///
  PDOExecutionContext pdo;

  ///
  /// The active PDO connection used for reads.
  ///
  /// @var PDO
  ///
  PDOExecutionContext? readPdo;

  ///
  /// The reconnector instance for the connection.
  ///
  /// @var callable
  ///
  Future<dynamic> Function(Connection)? reconnector;

  ///
  /// The query grammar implementation.
  ///
  /// @var \Illuminate\Database\Query\Grammars\Grammar
  ///
  late QueryGrammar queryGrammar;

  ///
  /// The schema grammar implementation.
  ///
  /// @var \Illuminate\Database\Schema\Grammars\Grammar
  ///
  SchemaGrammar? schemaGrammar;

  ///
  /// The query post processor implementation.
  ///
  /// @var \Illuminate\Database\Query\Processors\Processor
  ///
  Processor? postProcessor;

  ///
  /// The event dispatcher instance.
  ///
  /// @var \Illuminate\Contracts\Events\Dispatcher
  ///
  //protected events;

  ///
  /// The number of active transactions.
  ///
  @Deprecated('Use transactionLevel() / isInTransaction.')
  int get transactions => transactionLevel();

  /// Query log, listeners and pretend state. Shared with the connections
  /// handed to transaction callbacks, so queries run through `ctx` are logged
  /// and reported like the others.
  _QueryObservers _observers = _QueryObservers();

  ///
  /// All of the queries run against the connection: maps with `query`,
  /// `bindings` and `time` (milliseconds), as in Laravel.
  ///
  List get queryLog => _observers.log;
  set queryLog(List value) => _observers.log = value;

  ///
  /// Indicates whether queries are being logged.
  ///
  bool get loggingQueries => _observers.logging;
  set loggingQueries(bool value) => _observers.logging = value;

  ///
  /// Indicates if the connection is in a "dry run".
  ///
  /// @var bool
  ///
  bool get pretendingProp => _observers.pretending;
  set pretendingProp(bool value) => _observers.pretending = value;

  ///
  /// The name of the connected database.
  ///
  /// @var string
  ///
  late String _databaseName;

  ///
  /// The table prefix for the connection.
  ///
  /// @var string
  ///
  String _tablePrefix = '';

  ///
  /// The database connection configuration options.
  ///
  /// @var array
  ///
  Map<String, dynamic> _config = {};

  String? _cachedDriverName;

  doctrine.DoctrineConnection? doctrineConnection;
  AbstractSchemaManager? doctrineSchemaManager;

  int tryReconnectLimit = 10;
  int tryReconnectCount = 0;

  ///
  /// Create a new database connection instance.
  ///
  /// @param  \PDO     pdo
  /// @param  String   database
  /// @param  String   tablePrefix
  /// @param  array    config
  /// @return void
  ///
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
  }

  ///
  /// Set the query grammar to the default implementation.
  ///
  /// @return void
  ///
  void useDefaultQueryGrammar() {
    this.queryGrammar = getDefaultQueryGrammar();
  }

  ///
  /// Get the default query grammar instance.
  ///
  /// @return \Illuminate\Database\Query\Grammars\Grammar
  ///
  QueryGrammar getDefaultQueryGrammar() {
    return QueryGrammar();
  }

  ///
  /// Set the schema grammar to the default implementation.
  ///
  /// @return void
  ///
  void useDefaultSchemaGrammar() {
    this.schemaGrammar = getDefaultSchemaGrammar();
  }

  ///
  /// Get the default schema grammar instance.
  ///
  /// @return \Illuminate\Database\Schema\Grammars\Grammar
  ///
  dynamic getDefaultSchemaGrammar() {}

  ///
  /// Set the query post processor to the default implementation.
  ///
  /// @return void
  ///
  void useDefaultPostProcessor() {
    this.postProcessor = getDefaultPostProcessor();
  }

  ///
  /// Get the default post processor instance.
  ///
  /// @return \Illuminate\Database\Query\Processors\Processor
  ///
  Processor getDefaultPostProcessor() {
    return Processor();
  }

  ///
  /// Get a schema builder instance for the connection.
  ///
  /// @return \Illuminate\Database\Schema\Builder
  ///
  SchemaBuilder getSchemaBuilder() {
    if (Utils.is_null(schemaGrammar)) {
      useDefaultSchemaGrammar();
    }
    return SchemaBuilder(this);
  }

  ///
  /// Begin a fluent query against a database table.
  ///
  /// @param  String  $table
  /// @return \Illuminate\Database\Query\Builder
  ///
  QueryBuilder table(String table) {
    return this.query().from(table);
  }

  /// A [QueryBuilder2] (Dart 3 API: enums, named parameters with a fixed
  /// meaning, typed results) on [table].
  QueryBuilder2 table2(String table) {
    return QueryBuilder2(this, table);
  }

  ///
  /// Get a new query builder instance.
  ///
  /// @return \Illuminate\Database\Query\Builder
  ///
  QueryBuilder query() {
    return QueryBuilder(this, this.getQueryGrammar(), this.getPostProcessor());
  }

  ///
  /// Get a new raw query expression.
  ///
  /// @param  mixed  $value
  /// @return \Illuminate\Database\Query\Expression
  ///
  QueryExpression raw(dynamic value) {
    return QueryExpression(value);
  }

  ///
  /// Run a select statement and return a single result.
  ///
  /// @param  String  $query
  /// @param  array   $bindings
  /// @return mixed
  ///
  Future<Map<String, dynamic>?> selectOne(String query,
      [bindings = const [], int? timeoutInSeconds]) async {
    final records = await this.select(query, bindings, true, timeoutInSeconds);
    return records.isNotEmpty ? records.first : null;
  }

  ///
  /// Run a select statement against the database.
  ///
  /// @param  String  $query
  /// @param  array   $bindings
  /// @return array
  ///
  Future<List<Map<String, dynamic>>> selectFromWriteConnection(query,
      [bindings = const []]) {
    return this.select(query, bindings, false);
  }

  ///
  /// Run a select statement against the database.
  ///
  /// @param  String  $query
  /// @param  array  $bindings
  /// @param  bool  $useReadPdo
  /// @return array
  ///
  Future<List<Map<String, dynamic>>> select(String query,
      [List bindings = const [],
      bool useReadPdo = true,
      int? timeoutInSeconds]) async {
    //print('Connection@select timeout $timeoutInSeconds');

    final res = await this.run(query, bindings,
        (me, query, bindings, timeoutInSeconds) async {
      if (me.pretending()) {
        return <Map<String, dynamic>>[];
      }
      // For select statements, we'll simply execute the query and return an array
      // of the database result set. Each element in the array will be a single
      // row from the database table, and will either be an array or objects.
      final pdoL = me.getPdoForSelect(useReadPdo);
      final params = me.prepareBindings(bindings);
      return pdoL.query(query, params, timeoutInSeconds);
    }, timeoutInSeconds);

    return res as List<Map<String, dynamic>>;
  }

  ///
  /// Stream a select statement's rows using a server-side cursor / incremental
  /// reader, keeping memory roughly constant regardless of result-set size.
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
      _reportQuery(query, bindings, Duration.zero, null);
      return;
    }
    final pdoL = this.getPdoForSelect(useReadPdo);
    if (!pdoL.supportsQueryStream) {
      yield* _sqlCursor(query, bindings, fetchSize);
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
  /// loop, inside the current transaction or one opened for the stream (and
  /// closed when it ends or is cancelled). Rows are fetched [fetchSize]
  /// (default 1000) at a time and only when the consumer asks for them.
  Stream<Map<String, dynamic>> _sqlCursor(
      String query, List bindings, int? fetchSize) {
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
    var cancelled = false;
    controller = StreamController<Map<String, dynamic>>(
      onListen: () {
        transaction((ctx) async {
          await for (final row
              in _fetchCursor(ctx, name, query, bindings, size)) {
            if (cancelled) break;
            controller.add(row);
            if (controller.isPaused) {
              await (resumed = Completer<void>()).future;
            }
          }
        }).then((_) => controller.close(), onError: (Object e, StackTrace s) {
          if (!cancelled) controller.addError(e, s);
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

  ///
  /// Direct, driver-specific access (COPY, pipelining, LISTEN/NOTIFY, raw
  /// connection). Returns `null` when the active driver adapter has no such
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

  ///
  /// PostgreSQL `NOTIFY` via `pg_notify(channel, payload)`. Inside a
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
  ///
  Future<void> notify(String channel, [String payload = '']) async {
    _assertNotifications('notify');
    await this.select('select 1 from pg_notify(?::text, ?::text)',
        [channel, payload], false);
  }

  ///
  /// PostgreSQL `LISTEN` on [channel]: a stream of the notifications sent to
  /// it. All channels share one dedicated connection (outside the pool) that
  /// reconnects by itself; see [notificationListener] for `ready()`,
  /// `onReconnect` and `onError`.
  ///
  /// ```dart
  /// final sub = db.notifications('tramita_fila').listen((n) => acordarWorker());
  /// await db.notificationListener.ready();
  /// // ...
  /// await sub.cancel(); // UNLISTEN
  /// ```
  ///
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

  ///
  /// Get the PDO connection to use for a select query.
  ///
  /// @param  bool  $useReadPdo
  /// @return \PDO
  ///
  PDOExecutionContext getPdoForSelect([bool useReadPdo = true]) {
    return useReadPdo ? this.getReadPdo() : this.getPdo();
  }

  ///
  /// Run an insert statement against the database.
  ///
  /// @param  String  $query
  /// @param  array   $bindings
  /// @return bool
  ///
  Future<PDOResults> insert(query,
      [bindings = const [], int? timeoutInSeconds]) async {
    return this.statement(query, bindings, timeoutInSeconds);
  }

  /// alias for statement
  Future<PDOResults> rawQuery(query,
      [bindings = const [], int? timeoutInSeconds]) async {
    return this.statement(query, bindings, timeoutInSeconds);
  }

  ///
  /// Run an update statement against the database.
  ///
  /// @param  String  $query
  /// @param  array   $bindings
  /// @return int
  ///
  Future<int> update(String query,
      [List bindings = const [], int? timeoutInSeconds]) {
    return this.affectingStatement(query, bindings, timeoutInSeconds);
  }

  ///
  /// Run a delete statement against the database.
  ///
  /// @param  String  $query
  /// @param  array   $bindings
  /// @return int
  ///
  Future<int> delete(String query,
      [List bindings = const [], int? timeoutInSeconds]) {
    return this.affectingStatement(query, bindings, timeoutInSeconds);
  }

  ///
  /// Execute an SQL statement and return the boolean result.
  ///
  /// @param  String  $query
  /// @param  array   $bindings
  /// @return bool
  ///
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

  /// simple execute command on database
  ///  Executa uma instrução SQL e retornar o número de linhas afetadas
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

  ///
  /// Run an SQL statement and get the number of rows affected.
  ///
  /// @param  String  $query
  /// @param  array   $bindings
  /// @return int
  ///
  Future<int> affectingStatement(String query,
      [List<dynamic> bindingsP = const [], int? timeoutInSeconds]) async {
    final resp = await this.run(query, bindingsP,
        (me, query, bindings, timeoutInSeconds) async {
      if (me.pretending()) {
        return 0;
      }

      // For update or delete statements, we want to get the number of rows affected
      // by the statement and return that back to the developer. We'll first need
      // to execute the statement and then we'll use PDO to fetch the affected.
      final _pdo = me.getPdo();
      final params = me.prepareBindings(bindings);
      final res = await _pdo.query(query, params, timeoutInSeconds);
      return res.rowsAffected;
    }, timeoutInSeconds);

    return resp as int;
  }

  ///
  /// Run a raw, unprepared query against the PDO connection.
  ///
  /// @param  String  $query
  /// @return bool
  ///
  Future<int> unprepared(String query, [int? timeoutInSeconds]) async {
    final resp = await this.run(query, [],
        (me, query, bindings, timeoutInSeconds) async {
      if (me.pretending()) {
        return true;
      }

      return me.getPdo().execute(query, timeoutInSeconds);
    }, timeoutInSeconds);
    return resp as int;
  }

  ///
  /// Prepare the query bindings for execution.
  ///
  /// @param  array  bindings
  /// @return array
  ///
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

  ///
  /// Execute a Closure within a transaction.
  ///
  /// @param  Function  callback
  /// @return mixed
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
    return pdo.pdoInstance.runInTransaction<T>(
        (pdoCtx) => callback(_childConnection(pdoCtx)), timeoutInSeconds);
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
    final name = savepointName(level);
    await parent.createSavepoint(name, timeoutInSeconds);

    final T result;
    try {
      result = await callback(
          _childConnection(NestedPDOTransaction(parent, level)));
    } catch (error, stackTrace) {
      try {
        await parent.rollbackToSavepoint(name, timeoutInSeconds);
      } catch (_) {
        // Keep the callback error; the outer transaction will report its own
        // state if it cannot continue.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    await parent.releaseSavepoint(name, timeoutInSeconds);
    return result;
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

  ///
  /// [transaction] with an *ambient* transaction: while [callback] runs, the
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
  ///   await pecaRepository.juntar(dados);         // db.transaction -> SAVEPOINT
  ///   await db.outsideTransaction(() => logRepository.gravar(evento));
  /// });
  /// ```
  ///
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
  /// Inside a scope it needs a pool (`'pool': true`): with a single
  /// connection there is no "outside" while the transaction holds it, so it
  /// throws [StateError] instead of waiting for the transaction forever.
  Future<T> outsideTransaction<T>(FutureOr<T> Function() callback) async {
    final root = _root ?? this;
    if (root.isInTransactionScope && root.getConfig('pool') != true) {
      throw StateError(
          'outsideTransaction() inside a transactionScope needs a connection '
          "pool ('pool': true): with a single connection the query would wait "
          'for the transaction to end.');
    }
    return await runZoned(callback, zoneValues: {root._scopeKey: null});
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

  ///
  /// Start a new database transaction.
  ///
  /// @return void
  ///
  // Future<dynamic> beginTransaction() async {
  // this.transactions++;
  // if (this.transactions == 1) {
  //   this.pdo!.beginTransaction();
  // } else if (this.transactions > 1 &&
  //     this.queryGrammar.supportsSavepoints()) {
  //   this.pdo!.exec(this
  //       .queryGrammar
  //       .compileSavepoint('trans' + this.transactions.toString()));
  // }
  // this.fireConnectionEvent('beganTransaction');
  //throw UnimplementedError();
  // this.pdo!.beginTransaction();
  // }

  ///
  /// Commit the active database transaction.
  ///
  /// @return void
  ///
  // Future<dynamic> commit([dynamic transaction]) async {
  // if (this.transactions == 1) {
  //   this.pdo!.commit();
  // }
  // --this.transactions;
  // this.fireConnectionEvent('committed');
  //throw UnimplementedError();
  // return this.pdo!.commit(transaction);
  //}

  ///
  /// Rollback the active database transaction.
  ///
  /// @return void
  ///
  //Future<dynamic> rollBack([dynamic transaction]) async {
  // if (this.transactions == 1) {
  //   await this.pdo!.rollBack();
  // } else if (this.transactions > 1 &&
  //     this.queryGrammar.supportsSavepoints()) {
  //   //  await this.pdo!.exec(this
  //   //       .queryGrammar
  //   //       .compileSavepointRollBack('trans' + this.transactions.toString()));
  //   throw UnimplementedError();
  // }

  // this.transactions = Utils.int_max(0, this.transactions - 1);
  // this.fireConnectionEvent('rollingBack');
  //return this.pdo!.rollBack(transaction);
  //}

  ///
  /// Transaction depth of this connection: `0` outside a transaction, `1` in
  /// the callback of a top-level [transaction], `2+` inside SAVEPOINTs.
  ///
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

  ///
  /// Execute the given callback in "dry run" mode.
  ///
  /// @param  \Closure  $callback
  /// @return array
  ///
  Future<dynamic> pretend(Function callback) async {
    final loggingQueries = this.loggingQueries;
    final previousLog = this.queryLog;

    this.enableQueryLog();
    this.pretendingProp = true;
    this.queryLog = [];

    // Basically to make the database connection "pretend", we will just return
    // the default values for all the query methods, then we will return an
    // array of queries that were "executed" within the Closure callback.
    // The callback is awaited (it used to return before an async callback
    // ran, giving an empty log).
    final List log;
    try {
      await callback(this);
    } finally {
      log = this.queryLog;
      this.pretendingProp = false;
      this.loggingQueries = loggingQueries;
      this.queryLog = previousLog;
    }
    return log;
  }

  ///
  /// Run a SQL statement and log its execution context.
  ///
  /// @param  String    $query
  /// @param  array     $bindings
  /// @param  \Closure  $callback
  /// @return mixed
  ///
  /// @throws \Illuminate\Database\QueryException
  ///
  Future<dynamic> run(
      String query,
      dynamic bindings,
      Future<dynamic> Function(Connection con, String query, dynamic bindings,
              int? timeoutInSeconds)
          callback,
      [int? timeoutInSeconds]) async {
    final ambient = _ambient();
    if (ambient != null) {
      return ambient.run(query, bindings, callback, timeoutInSeconds);
    }
    // Fast path: nothing observes the queries, so nothing is timed.
    if (!_observers.active) {
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
      _reportQuery(query, bindings, watch.elapsed, error);
    }
  }

  Future<dynamic> _runUnobserved(
      String query,
      dynamic bindings,
      Future<dynamic> Function(Connection con, String query, dynamic bindings,
              int? timeoutInSeconds)
          callback,
      int? timeoutInSeconds) async {
    //this.reconnectIfMissingConnection();

    //var start = Utils.microtime();
    var result;
    // Here we will run this query. If an exception occurs we'll determine if it was
    // caused by a connection that has been lost. If that is the cause, we'll try
    // to re-establish connection and re-run the query with a fresh connection.
    try {
      // print('Connection@run');
      result = await this
          .runQueryCallback(query, bindings, callback, timeoutInSeconds);
      //print('Connection@run $result');
    } catch (e, stackTrace) {
      return await this.tryAgainIfCausedByLostConnection(
          e, query, bindings, callback, timeoutInSeconds,
          stackTrace: stackTrace);
    }

    return result;
  }

  ///
  /// Run a SQL statement.
  ///
  /// @param  String    $query
  /// @param  array     $bindings
  /// @param  \Closure  $callback
  /// @return mixed
  ///
  /// @throws \Illuminate\Database\QueryException
  ///
  Future<dynamic> runQueryCallback(
      String query,
      bindings,
      Future<dynamic> Function(Connection con, String query, dynamic bindings,
              int? timeoutInSeconds)
          callback,
      int? timeoutInSeconds) async {
    // To execute the statement, we'll simply call the callback, which will actually
    // run the SQL against the PDO connection. Then we can calculate the time it
    // took to execute and log the query SQL, bindings and time in our memory.
    var result;
    //try {
    result = await callback(this, query, bindings, timeoutInSeconds);
    //}

    // If an exception occurs when attempting to run a query, we'll format the error
    // message to include the bindings with SQL, which will make this exception a
    // lot more helpful to the developer instead of just the database's errors.
    // catch (e) {
    //   throw new QueryException(query, this.prepareBindings(bindings), e);
    // }

    return result;
  }

  ///
  /// Handle a query exception that occurred during query execution.
  ///
  /// @param  \Illuminate\Database\QueryException  $e
  /// @param  String    $query
  /// @param  array     $bindings
  /// @param  \Closure  $callback
  /// @return mixed
  ///
  /// @throws \Illuminate\Database\QueryException
  ///
  Future<dynamic> tryAgainIfCausedByLostConnection(
      dynamic e,
      String query,
      bindings,
      Future<dynamic> Function(
              Connection, String, dynamic, int? timeoutInSeconds)
          callback,
      int? timeoutInSeconds,
      {int delay = 1000, StackTrace? stackTrace}) async {
    // Inside a transaction the lost connection took the transaction with it:
    // re-running only this statement on a new connection would be wrong.
    if (!this.causedByLostConnection(e) ||
        this.isInTransaction ||
        this.reconnector == null) {
      Error.throwWithStackTrace(e as Object, stackTrace ?? StackTrace.current);
    }

    Object lastError = e;
    tryReconnectCount = 0;
    while (tryReconnectCount < tryReconnectLimit) {
      tryReconnectCount++;
      // Linear backoff, capped at 5 s.
      final wait = delay * tryReconnectCount;
      await Future.delayed(Duration(milliseconds: wait > 5000 ? 5000 : wait));
      try {
        await this.reconnect();
        final result = await this
            .runQueryCallback(query, bindings, callback, timeoutInSeconds);
        tryReconnectCount = 0;
        return result;
      } catch (error) {
        if (!this.causedByLostConnection(error)) {
          tryReconnectCount = 0;
          rethrow;
        }
        lastError = error;
      }
    }
    tryReconnectCount = 0;
    throw lastError;
  }

  ///
  /// Disconnect from the underlying PDO connection.
  ///
  /// @return void
  ///
  Future<void> disconnect() async {
    final pdoInstance = this.pdo.pdoInstance;
    final listener = _notificationListeners[pdoInstance];
    if (listener != null) {
      _notificationListeners[pdoInstance] = null;
      await listener.close();
    }
    try {
      await pdoInstance.close();
    } catch (e, s) {
      print('eloquent@disconnect error $e $s');
    }
  }

  ///
  /// Reconnect to the database.
  ///
  /// @return void
  ///
  /// @throws \LogicException
  ///
  Future<void> reconnect() async {
    //print('Connection@reconnect() ${this.reconnector}');
    if (this.reconnector != null) {
      return await this.reconnector!(this);
    }

    throw LogicException('Lost connection and no reconnector available.');
  }

  ///
  /// Reconnect to the database if a PDO connection is missing.
  ///
  /// @return void
  ///
  Future<void> reconnectIfMissingConnection() async {
    if (Utils.is_null(this.getPdo()) || Utils.is_null(this.getReadPdo())) {
      await this.reconnect();
    }
  }

  ///
  /// Log a query in the connection's query log.
  ///
  /// @param  String  $query
  /// @param  array   $bindings
  /// @param  float|null  $time
  /// @return void
  ///
  dynamic logQuery(String query, bindings, [time = null]) {
    if (this.loggingQueries) {
      this.queryLog.add({'query': query, 'bindings': bindings, 'time': time});
    }
  }

  void _reportQuery(
      String query, dynamic bindings, Duration elapsed, Object? error) {
    final observers = _observers;
    observers.total += elapsed;
    final list = bindings is List ? bindings : const <dynamic>[];
    if (observers.logging) {
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
      listener(event);
    }
  }

  ///
  /// Register a database query listener with the connection.
  ///
  /// @param  \Closure  $callback
  /// @return void
  ///
  ///
  /// [callback] receives every statement run on this connection (and on the
  /// connections given to its transaction callbacks), with its time and
  /// error. Returns a function that removes the listener.
  ///
  /// ```dart
  /// final stop = db.listen((q) => print('${q.time.inMilliseconds} ms ${q.sql}'));
  /// ```
  ///
  void Function() listen(void Function(QueryExecuted query) callback) {
    _observers.listeners.add(callback);
    return () => _observers.listeners.remove(callback);
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

  ///
  /// Fire an event for this connection.
  ///
  /// @param  String  $event
  /// @return void
  ///
  void fireConnectionEvent(String event) {
    // if (! isset(this.events)) {
    //     return;
    // }

    // switch ($event) {
    //     case 'beganTransaction':
    //         return this.events->fire(new Events\TransactionBeginning($this));
    //     case 'committed':
    //         return this.events->fire(new Events\TransactionCommitted($this));
    //     case 'rollingBack':
    //         return this.events->fire(new Events\TransactionRolledBack($this));
    // }
    throw UnimplementedError();
  }

  ///
  /// Get the elapsed time since a given starting point.
  ///
  /// @param  int    $start
  /// @return float
  ///
  dynamic getElapsedTime(int start) {
    return Utils.round((Utils.microtime() - start) * 1000);
  }

  ///
  /// Is Doctrine available?
  ///
  /// @return bool
  ///
  bool isDoctrineAvailable() {
    return true;
  }

  ///
  /// Get a Doctrine Schema Column instance.
  ///
  /// @param  String  $table
  /// @param  String  $column
  /// @return \Doctrine\DBAL\Schema\Column
  ///
  Future<Column> getDoctrineColumn(String table, String column) async {
    final schema = getDoctrineSchemaManager();
    final tableDetails = await schema.listTableDetails(table);
    return tableDetails.getColumn(column);
  }

  ///
  /// Get the Doctrine DBAL schema manager for the connection.
  ///
  /// @return \Doctrine\DBAL\Schema\AbstractSchemaManager
  ///
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
      final driver => throw UnsupportedError(
          'No database platform for driver "$driver".'),
    };
  }

  ///
  /// Get the Doctrine DBAL database connection instance.
  ///
  /// @return \Doctrine\DBAL\Connection
  ///
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

  ///
  /// Get the current PDO connection.
  ///
  /// @return \PDO
  ///
  PDOExecutionContext getPdo() {
    return this.pdo;
  }

  ///
  /// Get the current PDO connection used for reading.
  ///
  /// @return \PDO
  ///
  PDOExecutionContext getReadPdo() {
    if (isInTransaction) {
      return this.getPdo();
    }

    return this.readPdo ?? this.pdo;
  }

  ///
  /// Set the PDO connection.
  ///
  /// @param  \PDO|null  $pdo
  /// @return $this
  ///
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

  ///
  /// Set the PDO connection used for reading.
  ///
  /// @param  \PDO|null  $pdo
  /// @return $this
  ///
  dynamic setReadPdo(PDOExecutionContext? pdo) {
    this.readPdo = pdo;
    return this;
  }

  ///
  /// Set the reconnect instance on the connection.
  ///
  /// @param  callable  $reconnector
  /// @return $this
  ///
  dynamic setReconnector(Future<dynamic> Function(Connection) reconnectorP) {
    this.reconnector = reconnectorP;
    return this;
  }

  ///
  /// Get the database connection name.
  ///
  /// @return string|null
  ///
  dynamic getName() {
    return this.getConfig('name');
  }

  ///
  /// Get an option from the configuration options.
  ///
  /// @param  String  $option
  /// @return mixed
  ///
  dynamic getConfig(String option) {
    //return Arr::get(this.config, $option);
    //print('getConfig ${this._config}');
    //throw UnimplementedError();
    return this._config[option];
  }

  Map<String, dynamic> getConfigs() {
    return this._config;
  }

  ///
  /// Get the PDO driver name.
  ///
  /// @return string
  ///
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

  ///
  /// Get the query grammar used by the connection.
  ///
  /// @return \Illuminate\Database\Query\Grammars\Grammar
  ///
  QueryGrammar getQueryGrammar() {
    return this.queryGrammar;
  }

  ///
  /// Set the query grammar used by the connection.
  ///
  /// @param  \Illuminate\Database\Query\Grammars\Grammar  $grammar
  /// @return void
  ///
  void setQueryGrammar(QueryGrammar grammarP) {
    this.queryGrammar = grammarP;
  }

  ///
  /// Get the schema grammar used by the connection.
  ///
  /// @return \Illuminate\Database\Schema\Grammars\Grammar
  ///
  SchemaGrammar getSchemaGrammar() {
    return this.schemaGrammar!;
  }

  ///
  /// Set the schema grammar used by the connection.
  ///
  /// @param  \Illuminate\Database\Schema\Grammars\Grammar  $grammar
  /// @return void
  ///
  void setSchemaGrammar(SchemaGrammar grammarP) {
    this.schemaGrammar = grammarP;
  }

  ///
  /// Get the query post processor used by the connection.
  ///
  /// @return \Illuminate\Database\Query\Processors\Processor
  ///
  dynamic getPostProcessor() {
    return this.postProcessor;
  }

  ///
  /// Set the query post processor used by the connection.
  ///
  /// @param  \Illuminate\Database\Query\Processors\Processor  $processor
  /// @return void
  ///
  dynamic setPostProcessor(Processor processor) {
    this.postProcessor = processor;
  }

  ///
  /// Get the event dispatcher used by the connection.
  ///
  /// @return \Illuminate\Contracts\Events\Dispatcher
  ///
  dynamic getEventDispatcher() {
    return this._events;
  }

  /// The dispatcher given to [setEventDispatcher] (kept for Laravel parity;
  /// query events are delivered through [listen]).
  dynamic _events;

  ///
  /// Set the event dispatcher instance on the connection.
  ///
  /// @param  \Illuminate\Contracts\Events\Dispatcher  $events
  /// @return void
  ///
  dynamic setEventDispatcher($events) {
    this._events = $events;
  }

  ///
  /// Determine if the connection in a "dry run".
  ///
  /// @return bool
  ///
  bool pretending() {
    return this.pretendingProp == true;
  }

  ///
  /// Get the connection query log.
  ///
  /// @return array
  ///
  dynamic getQueryLog() {
    return this.queryLog;
  }

  ///
  /// Clear the query log.
  ///
  /// @return void
  ///
  dynamic flushQueryLog() {
    this.queryLog = [];
  }

  ///
  /// Enable the query log on the connection.
  ///
  /// @return void
  ///
  dynamic enableQueryLog() {
    this.loggingQueries = true;
  }

  ///
  /// Disable the query log on the connection.
  ///
  /// @return void
  ///
  void disableQueryLog() {
    this.loggingQueries = false;
  }

  ///
  /// Determine whether we're logging queries.
  ///
  /// @return bool
  ///
  bool logging() {
    return this.loggingQueries;
  }

  ///
  /// Get the name of the connected database.
  ///
  /// @return string
  ///
  String getDatabaseName() {
    return this._databaseName;
  }
  // String getDatabaseName() {
  //   // PDOConfig config;
  //   return pdo.getConfig().database;
  // }

  ///
  /// Set the name of the connected database.
  ///
  /// @param  String  $database
  /// @return string
  ///
  void setDatabaseName(String database) {
    this._databaseName = database;
  }

  ///
  /// Get the table prefix for the connection.
  ///
  /// @return string
  ///
  String getTablePrefix() {
    return this._tablePrefix;
  }

  ///
  /// Set the table prefix in use by the connection.
  ///
  /// @param  String  $prefix
  /// @return void
  ///
  void setTablePrefix(String prefix) {
    this._tablePrefix = prefix;

    this.getQueryGrammar().setTablePrefix(prefix);
  }

  ///
  /// Set the table prefix and return the grammar.
  ///
  /// @param  \Illuminate\Database\Grammar  $grammar
  /// @return \Illuminate\Database\Grammar
  ///
  dynamic withTablePrefix(BaseGrammar grammar) {
    grammar.setTablePrefix(this._tablePrefix);

    return grammar;
  }
}

/// Query log, listeners and pretend state of a connection and of the
/// connections created for its transactions.
class _QueryObservers {
  bool logging = false;
  List log = [];
  bool pretending = false;
  Duration total = Duration.zero;
  final List<void Function(QueryExecuted)> listeners =
      <void Function(QueryExecuted)>[];

  /// Whether statements must be timed and reported.
  bool get active => logging || listeners.isNotEmpty;
}

/// The transaction of a [Connection.transactionScope], kept in the zone.
final class _AmbientScope {
  _AmbientScope(this.connection);

  /// The `ctx` of the scope's transaction.
  final Connection connection;

  /// False once the scope's callback returned.
  bool active = true;
}
