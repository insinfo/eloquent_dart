import 'package:eloquent/eloquent.dart';

const listVoid = [];

abstract class ConnectionInterface {
  ///
  /// Begin a fluent query against a database table.
  ///
  /// [table]  String  table
  ///  @return \Illuminate\Database\Query\Builder
  ///
  QueryBuilder table(String table);

  ///
  /// Get a new raw query expression.
  ///
  /// [value]  dynamic
  /// @return Expression
  ///
  QueryExpression raw(dynamic value);

  ///
  /// Run a select statement and return a single result.
  ///
  /// [query]  String
  /// [bindings]  List
  /// @return dynamic
  ///
  Future<Map<String, dynamic>?> selectOne(String query,
      [List bindings = listVoid, int? timeoutInSeconds]);

  ///
  /// Run a select statement against the database.
  ///
  /// [query]  String
  /// [bindings]  List
  /// @return array
  ///
  Future<List<Map<String, dynamic>>> select(String query,
      [List bindings = listVoid,
      bool useReadPdo = true,
      int? timeoutInSeconds]);

  ///
  /// Stream a select statement's rows using a server-side cursor / incremental
  /// reader, keeping memory roughly constant for very large result sets.
  ///
  /// [query]  String
  /// [bindings]  List
  /// [useReadPdo]  bool
  /// [fetchSize]  advisory rows-per-round-trip hint
  /// @return Stream of row maps
  ///
  Stream<Map<String, dynamic>> cursor(String query,
      [List bindings = listVoid, bool useReadPdo = true, int? fetchSize]);

  ///
  /// Direct, driver-specific access (COPY, pipelining, LISTEN/NOTIFY, raw
  /// connection). Returns `null` when unsupported by the active driver.
  ///
  DriverAccess? driver();

  ///
  /// Run an insert statement against the database.
  ///
  /// [query]  String
  /// [bindings]  List
  /// @return bool
  ///
  Future<PDOResults> insert(String query,
      [List bindings = listVoid, int? timeoutInSeconds]);

  ///
  /// Run an update statement against the database.
  ///
  /// [query]  String
  /// [bindings]  List
  /// @return int
  ///
  Future<int> update(String query,
      [List bindings = listVoid, int? timeoutInSeconds]);

  ///
  /// Run a delete statement against the database.
  ///
  /// [query]  String
  /// [bindings]  List
  /// @return int
  ///
  Future<int> delete(String query,
      [List bindings = listVoid, int? timeoutInSeconds]);

  ///
  /// Execute an SQL statement and return the boolean result.
  ///
  /// [query] string
  /// [bindings]  List
  /// @return bool
  ///
  Future<PDOResults> statement(String query,
      [List bindings = listVoid, int? timeoutInSeconds]);

  ///
  /// Run an SQL statement and get the number of rows affected.
  ///
  /// [query] String
  /// [bindings]  List
  /// @return int
  ///
  Future<int> affectingStatement(String query,
      [List bindings = listVoid, int? timeoutInSeconds]);

  ///
  /// Run a raw, unprepared query against the PDO connection.
  ///
  /// [query]  String
  /// @return bool
  ///
  Future<int> unprepared(String query, int? timeoutInSeconds);

  ///
  /// Prepare the query bindings for execution.
  ///
  /// [bindings]  List
  ///  Returns `List`
  ///
  dynamic prepareBindings(List bindings);

  ///
  /// Execute a Closure within a transaction.
  ///
  /// [callback] Function \Closure
  /// Returns `dynamic`
  ///
  /// @throws \Throwable
  ///
  /// Inside an existing transaction this nests through a SAVEPOINT; see
  /// [Connection.transaction].
  ///
  Future<T> transaction<T>(Future<T> Function(Connection ctx) callback,
      [int? timeoutInSeconds]);

  ///
  /// Runs [callback] in a transaction, reusing the current one (without a
  /// SAVEPOINT) when this connection is already inside a transaction.
  ///
  Future<T> transactionIfNeeded<T>(Future<T> Function(Connection ctx) callback,
      [int? timeoutInSeconds]);

  ///
  /// Transaction depth: 0 outside a transaction, 1 in the outer transaction,
  /// 2+ inside nested SAVEPOINTs.
  ///
  /// Returns `int`
  ///
  int transactionLevel();

  /// Whether this connection runs inside a transaction.
  bool get isInTransaction;

  /// Whether [transaction] can nest through SAVEPOINT on this connection.
  bool get supportsSavepoints;

  ///
  /// Execute the given callback in "dry run" mode.
  ///
  /// [callback]  Function
  /// Returns `List`
  ///
  Future<dynamic> pretend(Function callback);

  String getDatabaseName();

  SchemaGrammar getSchemaGrammar();
}
