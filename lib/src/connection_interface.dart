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
  dynamic selectOne(String query, [List bindings = listVoid]);

  ///
  /// Run a select statement against the database.
  ///
  /// [query]  String
  /// [bindings]  List
  /// @return array
  ///
  dynamic select(String query,
      [List bindings = listVoid, bool useReadPdo = true]);

  ///
  /// Run an insert statement against the database.
  ///
  /// [query]  String
  /// [bindings]  List
  /// @return bool
  ///
  bool insert(String query, [List bindings = listVoid]);

  ///
  /// Run an update statement against the database.
  ///
  /// [query]  String
  /// [bindings]  List
  /// @return int
  ///
  int update(String query, [List bindings = listVoid]);

  ///
  /// Run a delete statement against the database.
  ///
  /// [query]  String
  /// [bindings]  List
  /// @return int
  ///
  int delete(String query, [List bindings = listVoid]);

  ///
  /// Execute an SQL statement and return the boolean result.
  ///
  /// [query] string
  /// [bindings]  List
  /// @return bool
  ///
  bool statement(String query, [List bindings = listVoid]);

  ///
  /// Run an SQL statement and get the number of rows affected.
  ///
  /// [query] String
  /// [bindings]  List
  /// @return int
  ///
  int affectingStatement(String query, [List bindings = listVoid]);

  ///
  /// Run a raw, unprepared query against the PDO connection.
  ///
  /// [query]  String
  /// @return bool
  ///
  bool unprepared(String query);

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
  dynamic transaction(Function callback);

  ///
  /// Start a new database transaction.
  ///
  /// Returns `void`
  ///
  void beginTransaction();

  ///
  /// Commit the active database transaction.
  ///
  /// Returns `void`
  ///
  void commit();

  ///
  /// Rollback the active database transaction.
  ///
  /// Returns `void`
  ///
  void rollBack();

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
  dynamic pretend(Function callback);
}
