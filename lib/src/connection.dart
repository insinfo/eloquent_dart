import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/schema/schema_builder.dart';

/// posgresql Connection implementation
class Connection implements ConnectionInterface {
  ///
  /// The active PDO connection.
  ///
  /// @var PDO
  ///
  late PDO pdo;

  ///
  /// The active PDO connection used for reads.
  ///
  /// @var PDO
  ///
  PDO? readPdo;

  ///
  /// The reconnector instance for the connection.
  ///
  /// @var callable
  ///
  Function? reconnector;

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
  /// The default fetch mode of the connection.
  ///
  /// @var int
  ///
  int fetchMode = 0; // PDO::FETCH_OBJ;

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
  late String databaseProp;

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
  String tablePrefix = '';

  ///
  /// The database connection configuration options.
  ///
  /// @var array
  ///
  Map<String, dynamic> config = {};

  ///
  /// Create a new database connection instance.
  ///
  /// @param  \PDO     $pdo
  /// @param  String   $database
  /// @param  String   $tablePrefix
  /// @param  array    $config
  /// @return void
  ///
  Connection(PDO pdoP,
      [String databaseNameP = '',
      String tablePrefixP = '',
      Map<String, dynamic> configP = const {}]) {
    this.pdo = pdoP;

    // First we will setup the default properties. We keep track of the DB
    // name we are connected to since it is needed when some reflective
    // type commands are run such as checking whether a table exists.
    this.databaseProp = databaseNameP;
    this.tablePrefix = tablePrefixP;
    this.config = configP;

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
    return new QueryBuilder(
        this, this.getQueryGrammar(), this.getPostProcessor());
  }

  ///
  /// Get a new raw query expression.
  ///
  /// @param  mixed  $value
  /// @return \Illuminate\Database\Query\Expression
  ///
  QueryExpression raw($value) {
    return QueryExpression($value);
  }

  ///
  /// Run a select statement and return a single result.
  ///
  /// @param  String  $query
  /// @param  array   $bindings
  /// @return mixed
  ///
  dynamic selectOne(String query, [bindings = const []]) {
    var records = this.select(query, bindings);
    return Utils.count(records) > 0 ? Utils.reset(records) : null;
  }

  ///
  /// Run a select statement against the database.
  ///
  /// @param  String  $query
  /// @param  array   $bindings
  /// @return array
  ///
  dynamic selectFromWriteConnection(query, [bindings = const []]) {
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
  dynamic select(String query, [bindings = const [], bool useReadPdo = true]) {
    return this.run(query, bindings, (me, query, bindings) {
      if (me.pretending()) {
        return [];
      }

      // For select statements, we'll simply execute the query and return an array
      // of the database result set. Each element in the array will be a single
      // row from the database table, and will either be an array or objects.
      var statement = this.getPdoForSelect(useReadPdo).prepare(query);

      statement.execute(me.prepareBindings(bindings));

      return statement.fetchAll(me.getFetchMode());
    });
  }

  ///
  /// Get the PDO connection to use for a select query.
  ///
  /// @param  bool  $useReadPdo
  /// @return \PDO
  ///
  dynamic getPdoForSelect([bool useReadPdo = true]) {
    return useReadPdo ? this.getReadPdo() : this.getPdo();
  }

  ///
  /// Run an insert statement against the database.
  ///
  /// @param  String  $query
  /// @param  array   $bindings
  /// @return bool
  ///
  bool insert(query, [bindings = const []]) {
    return this.statement(query, bindings);
  }

  ///
  /// Run an update statement against the database.
  ///
  /// @param  String  $query
  /// @param  array   $bindings
  /// @return int
  ///
  int update(String query, [List bindings = const []]) {
    return this.affectingStatement(query, bindings);
  }

  ///
  /// Run a delete statement against the database.
  ///
  /// @param  String  $query
  /// @param  array   $bindings
  /// @return int
  ///
  int delete(String query, [List bindings = const []]) {
    return this.affectingStatement(query, bindings);
  }

  ///
  /// Execute an SQL statement and return the boolean result.
  ///
  /// @param  String  $query
  /// @param  array   $bindings
  /// @return bool
  ///
  bool statement(String query, [bindingsP = const []]) {
    return this.run(query, bindingsP, (me, query, bindings) {
      if (me.pretending()) {
        return true;
      }

      var bindi = me.prepareBindings(bindings);

      return me.getPdo().prepare(query).execute(bindi);
    });
  }

  ///
  /// Run an SQL statement and get the number of rows affected.
  ///
  /// @param  String  $query
  /// @param  array   $bindings
  /// @return int
  ///
  int affectingStatement(String query, [bindingsP = const []]) {
    return this.run(query, bindingsP, (me, query, bindings) {
      if (me.pretending()) {
        return 0;
      }

      // For update or delete statements, we want to get the number of rows affected
      // by the statement and return that back to the developer. We'll first need
      // to execute the statement and then we'll use PDO to fetch the affected.
      var statement = me.getPdo().prepare(query);

      statement.execute(me.prepareBindings(bindings));

      return statement.rowCount();
    });
  }

  ///
  /// Run a raw, unprepared query against the PDO connection.
  ///
  /// @param  String  $query
  /// @return bool
  ///
  bool unprepared(String query) {
    return this.run(query, [], (me, query) {
      if (me.pretending()) {
        return true;
      }

      return me.getPdo().exec(query);
    });
  }

  ///
  /// Prepare the query bindings for execution.
  ///
  /// @param  array  $bindings
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
  /// @param  \Closure  $callback
  /// @return mixed
  ///
  /// @throws \Throwable
  ///
  dynamic transaction(Function callback) {
    this.beginTransaction();
    var result;
    // We'll simply execute the given callback within a try / catch block
    // and if we catch any exception we can rollback the transaction
    // so that none of the changes are persisted to the database.
    try {
      result = callback(this);

      this.commit();
    } catch (ex) {
      // If we catch an exception, we will roll back so nothing gets messed
      // up in the database. Then we'll re-throw the exception so it can
      // be handled how the developer sees fit for their applications.
      this.rollBack();
      throw ex;
    }

    return result;
  }

  ///
  /// Start a new database transaction.
  ///
  /// @return void
  ///
  dynamic beginTransaction() {
    this.transactions++;

    if (this.transactions == 1) {
      this.pdo.beginTransaction();
    } else if (this.transactions > 1 &&
        this.queryGrammar.supportsSavepoints()) {
      this.pdo.exec(this
          .queryGrammar
          .compileSavepoint('trans' + this.transactions.toString()));
    }

    this.fireConnectionEvent('beganTransaction');
  }

  ///
  /// Commit the active database transaction.
  ///
  /// @return void
  ///
  dynamic commit() {
    if (this.transactions == 1) {
      this.pdo.commit();
    }

    --this.transactions;

    this.fireConnectionEvent('committed');
  }

  ///
  /// Rollback the active database transaction.
  ///
  /// @return void
  ///
  dynamic rollBack() {
    if (this.transactions == 1) {
      this.pdo.rollBack();
    } else if (this.transactions > 1 &&
        this.queryGrammar.supportsSavepoints()) {
      this.pdo.exec(this
          .queryGrammar
          .compileSavepointRollBack('trans' + this.transactions.toString()));
    }

    this.transactions = Utils.int_max(0, this.transactions - 1);

    this.fireConnectionEvent('rollingBack');
  }

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
  dynamic pretend(Function callback) {
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
  dynamic run(String query, dynamic bindings, Function callback) {
    this.reconnectIfMissingConnection();

    var start = Utils.microtime();
    var result;
    // Here we will run this query. If an exception occurs we'll determine if it was
    // caused by a connection that has been lost. If that is the cause, we'll try
    // to re-establish connection and re-run the query with a fresh connection.
    try {
      result = this.runQueryCallback(query, bindings, callback);
    } catch (e) {
      result =
          this.tryAgainIfCausedByLostConnection(e, query, bindings, callback);
    }

    // Once we have run the query we will calculate the time that it took to run and
    // then log the query, bindings, and execution time so we will report them on
    // the event that the developer needs them. We'll log time in milliseconds.
    var time = this.getElapsedTime(start);

    this.logQuery(query, bindings, time);

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
  dynamic runQueryCallback(String query, bindings, Function callback) {
    // To execute the statement, we'll simply call the callback, which will actually
    // run the SQL against the PDO connection. Then we can calculate the time it
    // took to execute and log the query SQL, bindings and time in our memory.
    var result;
    try {
      result = callback(this, query, bindings);
    }

    // If an exception occurs when attempting to run a query, we'll format the error
    // message to include the bindings with SQL, which will make this exception a
    // lot more helpful to the developer instead of just the database's errors.
    catch (e) {
      throw new QueryException(query, this.prepareBindings(bindings), e);
    }

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
  dynamic tryAgainIfCausedByLostConnection(
      dynamic e, String query, bindings, Function callback) {
    // if (this.causedByLostConnection($e->getPrevious())) {
    //     this.reconnect();

    //     return this.runQueryCallback(query, bindings, callback);
    // }

    // throw e;
    throw UnimplementedError();
  }

  ///
  /// Disconnect from the underlying PDO connection.
  ///
  /// @return void
  ///
  dynamic disconnect() {
    this.setPdo(null).setReadPdo(null);
  }

  ///
  /// Reconnect to the database.
  ///
  /// @return void
  ///
  /// @throws \LogicException
  ///
  dynamic reconnect() {
    if (this.reconnector is Function) {
      return this.reconnector!(this);
    }

    throw LogicException('Lost connection and no reconnector available.');
  }

  ///
  /// Reconnect to the database if a PDO connection is missing.
  ///
  /// @return void
  ///
  void reconnectIfMissingConnection() {
    if (Utils.is_null(this.getPdo()) || Utils.is_null(this.getReadPdo())) {
      this.reconnect();
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
  dynamic getPdo() {
    return this.pdo;
  }

  ///
  /// Get the current PDO connection used for reading.
  ///
  /// @return \PDO
  ///
  dynamic getReadPdo() {
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
  dynamic setPdo($pdo) {
    if (this.transactions >= 1) {
      //RuntimeException
      throw Exception("Can't swap PDO instance while within transaction.");
    }

    this.pdo = $pdo;

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
  dynamic setReconnector(Function reconnectorP) {
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
  dynamic getConfig($option) {
    //return Arr::get(this.config, $option);
    throw UnimplementedError();
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
  dynamic setPostProcessor(Processor $processor) {
    this.postProcessor = $processor;
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
  /// Get the default fetch mode for the connection.
  ///
  /// @return int
  ///
  dynamic getFetchMode() {
    return this.fetchMode;
  }

  ///
  /// Set the default fetch mode for the connection.
  ///
  /// @param  int  $fetchMode
  /// @return int
  ///
  dynamic setFetchMode($fetchMode) {
    this.fetchMode = $fetchMode;
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
    return this.databaseProp;
  }

  ///
  /// Set the name of the connected database.
  ///
  /// @param  String  $database
  /// @return string
  ///
  void setDatabaseName(String database) {
    this.databaseProp = database;
  }

  ///
  /// Get the table prefix for the connection.
  ///
  /// @return string
  ///
  dynamic getTablePrefix() {
    return this.tablePrefix;
  }

  ///
  /// Set the table prefix in use by the connection.
  ///
  /// @param  String  $prefix
  /// @return void
  ///
  dynamic setTablePrefix(String prefix) {
    this.tablePrefix = prefix;

    this.getQueryGrammar().setTablePrefix(prefix);
  }

  ///
  /// Set the table prefix and return the grammar.
  ///
  /// @param  \Illuminate\Database\Grammar  $grammar
  /// @return \Illuminate\Database\Grammar
  ///
  dynamic withTablePrefix(BaseGrammar grammar) {
    grammar.setTablePrefix(this.tablePrefix);

    return grammar;
  }
}
