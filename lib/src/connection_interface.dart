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
  Future<dynamic> selectOne(String query,
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
  /// Run an insert statement against the database.
  ///
  /// [query]  String
  /// [bindings]  List
  /// @return bool
  ///
  Future<dynamic> insert(String query,
      [List bindings = listVoid, int? timeoutInSeconds]);

  ///
  /// Run an update statement against the database.
  ///
  /// [query]  String
  /// [bindings]  List
  /// @return int
  ///
  Future<dynamic> update(String query,
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
  Future<dynamic> statement(String query,
      [List bindings = listVoid, int? timeoutInSeconds]);

  ///
  /// Run an SQL statement and get the number of rows affected.
  ///
  /// [query] String
  /// [bindings]  List
  /// @return int
  ///
  Future<dynamic> affectingStatement(String query,
      [List bindings = listVoid, int? timeoutInSeconds]);

  ///
  /// Run a raw, unprepared query against the PDO connection.
  ///
  /// [query]  String
  /// @return bool
  ///
  Future<dynamic> unprepared(String query, int? timeoutInSeconds);

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
  Future<dynamic> transaction(
      Future<dynamic> Function(Connection ctx) callback, [int? timeoutInSeconds]);

  ///
  /// Start a new database transaction.
  ///
  /// Returns `void`
  ///
  //Future<dynamic> beginTransaction();

  ///
  /// Commit the active database transaction.
  ///
  /// Returns `void`
  ///
  //Future<dynamic> commit([dynamic transaction]);

  ///
  /// Rollback the active database transaction.
  ///
  /// Returns `void`
  ///
  //Future<dynamic> rollBack([dynamic transaction]);

  ///
  /// Get the number of active transactions.
  ///
  /// Returns `int`
  ///
  int transactionLevel();

  ///
  /// Execute the given callback in "dry run" mode.
  ///
  /// [callback]  Function
  /// Returns `List`
  ///
  Future<dynamic> pretend(Function callback);
}
