import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/schema/schema_builder.dart';

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
  /// @var int
  ///
  int transactions = 0;

  ///
  /// All of the queries run against the connection.
  ///
  /// @var array
  ///
  List queryLog = [];

  ///
  /// Indicates whether queries are being logged.
  ///
  /// @var bool
  ///
  bool loggingQueries = false;

  ///
  /// Indicates if the connection is in a "dry run".
  ///
  /// @var bool
  ///
  bool pretendingProp = false;

  ///
  /// The name of the connected database.
  ///
  /// @var string
  ///
  late String _databaseName;

  ///
  /// The instance of Doctrine connection.
  ///
  /// @var \Doctrine\DBAL\Connection
  ///
  // protected doctrineConnection;

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
    //this.pdo = pdoP;
    // print('call Connection construct');
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
    final records = await this.select(
      query,
      bindings,
    );
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
        return [];
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
        return true;
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
  dynamic prepareBindings(List<dynamic> bindings) {
    var grammar = getQueryGrammar();

    for (var i = 0; i < bindings.length; i++) {
      var key = i;
      var value = bindings[key];
      // We need to transform all instances of DateTimeInterface into the actual
      // date string. Each query grammar maintains its own date string format
      // so we'll just ask the grammar for the format to get from the date.
      if (value is DateTime) {
        bindings[key] = Utils.formatDate(value, grammar.getDateFormat());
      } else if (value == false) {
        bindings[key] = 0;
      }
    }

    return bindings;
  }

  ///
  /// Execute a Closure within a transaction.
  ///
  /// @param  Function  callback
  /// @return mixed
  ///
  /// @throws \Throwable
  Future<dynamic> transaction(Future<dynamic> Function(Connection ctx) callback,
      [int? timeoutInSeconds]) async {
    var result = this.pdo.pdoInstance.runInTransaction((pdoCtx) {
      final newConnection = Connection(
          pdoCtx, this._databaseName, this._tablePrefix, this._config);
      return callback(newConnection);
    });

    return result;
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
  /// Get the number of active transactions.
  ///
  /// @return int
  ///
  int transactionLevel() {
    return this.transactions;
  }

  ///
  /// Execute the given callback in "dry run" mode.
  ///
  /// @param  \Closure  $callback
  /// @return array
  ///
  Future<dynamic> pretend(Function callback) async {
    var loggingQueries = this.loggingQueries;

    this.enableQueryLog();
    this.pretendingProp = true;
    this.queryLog = [];

    // Basically to make the database connection "pretend", we will just return
    // the default values for all the query methods, then we will return an
    // array of queries that were "executed" within the Closure callback.
    callback(this);
    this.pretendingProp = false;
    this.loggingQueries = loggingQueries;
    return this.queryLog;
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
    } catch (e) {
      //print('Connection@run error $e');
      result = await this
          .tryAgainIfCausedByLostConnection(e, query, bindings, callback, timeoutInSeconds);
    }

    // Once we have run the query we will calculate the time that it took to run and
    // then log the query, bindings, and execution time so we will report them on
    // the event that the developer needs them. We'll log time in milliseconds.
    //var time = this.getElapsedTime(start);

    //this.logQuery(query, bindings, time);

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
      {int delay = 1000}) async {
    if (this.causedByLostConnection(e) &&
        tryReconnectCount < tryReconnectLimit) {
      await Future.delayed(Duration(milliseconds: delay));
     // print('Eloquent@tryAgainIfCausedByLostConnection try reconnect...');
      tryReconnectLimit++;
      await this.reconnect();
      tryReconnectLimit = 0;
      return await this
          .runQueryCallback(query, bindings, callback, timeoutInSeconds);
    }
   // print('tryAgainIfCausedByLostConnection');
    throw e;
  }

  ///
  /// Disconnect from the underlying PDO connection.
  ///
  /// @return void
  ///
  Future<void> disconnect() async {
    // this.setPdo(null).setReadPdo(null);
    //throw UnimplementedError();
    //print('Connection@disconnect');
    try {
      await this.pdo.pdoInstance.close();
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
    // if (isset(this.events)) {
    //     this.events->fire(new Events\QueryExecuted(
    //         $query, $bindings, $time, $this
    //     ));
    // }

    if (this.loggingQueries) {
      this.queryLog.add({'query': query, 'bindings': bindings, 'time': time});
    }
  }

  ///
  /// Register a database query listener with the connection.
  ///
  /// @param  \Closure  $callback
  /// @return void
  ///
  dynamic listen(Function callback) {
    // if (isset(this.events)) {
    //     this.events->listen(Events\QueryExecuted::class, $callback);
    // }
    throw UnimplementedError();
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
    //return class_exists('Doctrine\DBAL\Connection');
    return false;
  }

  ///
  /// Get a Doctrine Schema Column instance.
  ///
  /// @param  String  $table
  /// @param  String  $column
  /// @return \Doctrine\DBAL\Schema\Column
  ///
  dynamic getDoctrineColumn($table, $column) {
    // $schema = this.getDoctrineSchemaManager();
    // return $schema->listTableDetails($table)->getColumn($column);
    return null;
  }

  ///
  /// Get the Doctrine DBAL schema manager for the connection.
  ///
  /// @return \Doctrine\DBAL\Schema\AbstractSchemaManager
  ///
  dynamic getDoctrineSchemaManager() {
    //return this.getDoctrineDriver()->getSchemaManager(this.getDoctrineConnection());
    return null;
  }

  ///
  /// Get the Doctrine DBAL database connection instance.
  ///
  /// @return \Doctrine\DBAL\Connection
  ///
  dynamic getDoctrineConnection() {
    // if (is_null(this.doctrineConnection)) {
    //     $driver = this.getDoctrineDriver();

    //     $data = ['pdo' => this.pdo, 'dbname' => this.getConfig('database')];

    //     this.doctrineConnection = new DoctrineConnection($data, $driver);
    // }

    // return this.doctrineConnection;
    return null;
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
    if (this.transactions >= 1) {
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
    if (this.transactions >= 1) {
      //RuntimeException
      throw Exception("Can't swap PDO instance while within transaction.");
    }

    this.pdo = pdo;

    return this;
  }

  ///
  /// Set the PDO connection used for reading.
  ///
  /// @param  \PDO|null  $pdo
  /// @return $this
  ///
  dynamic setReadPdo($pdo) {
    this.readPdo = $pdo;
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
    //return this.pdo->getAttribute(PDO::ATTR_DRIVER_NAME);
    return 'teste';
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
    //return this.events;
    throw UnimplementedError();
  }

  ///
  /// Set the event dispatcher instance on the connection.
  ///
  /// @param  \Illuminate\Contracts\Events\Dispatcher  $events
  /// @return void
  ///
  dynamic setEventDispatcher($events) {
    //this.events = $events;
    throw UnimplementedError();
  }

  ///
  /// Determine if the connection in a "dry run".
  ///
  /// @return bool
  ///
  bool pretending() {
    return this.pretending == true;
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
