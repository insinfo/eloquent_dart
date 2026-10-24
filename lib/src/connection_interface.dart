import 'package:eloquent/eloquent.dart';

const listVoid = [];

abstract class ConnectionInterface {
  /// Returns a [QueryBuilder] on [table].
  QueryBuilder table(String table);

  /// Returns a raw SQL expression: [value] goes into the query as written,
  /// not as a binding.
  QueryExpression raw(dynamic value);

  /// Runs a select statement and returns its first row, or null when there
  /// is none.
  Future<Map<String, dynamic>?> selectOne(String query,
      [List bindings = listVoid, int? timeoutInSeconds]);

  /// Runs a select statement and returns its rows.
  ///
  /// With [useReadPdo] it runs on the read connection.
  Future<List<Map<String, dynamic>>> select(String query,
      [List bindings = listVoid,
      bool useReadPdo = true,
      int? timeoutInSeconds]);

  /// Streams the rows of a select statement through a server-side cursor or
  /// incremental reader, keeping memory roughly constant for very large
  /// result sets.
  ///
  /// [fetchSize] is an advisory hint for the rows fetched per round trip.
  Stream<Map<String, dynamic>> cursor(String query,
      [List bindings = listVoid, bool useReadPdo = true, int? fetchSize]);

  /// Returns direct, driver-specific access (COPY, pipelining, LISTEN/NOTIFY,
  /// raw connection), or `null` when the active driver has none.
  DriverAccess? driver();

  /// Runs an insert statement and returns its [PDOResults].
  Future<PDOResults> insert(String query,
      [List bindings = listVoid, int? timeoutInSeconds]);

  /// Runs an update statement and returns the number of rows affected.
  Future<int> update(String query,
      [List bindings = listVoid, int? timeoutInSeconds]);

  /// Runs a delete statement and returns the number of rows affected.
  Future<int> delete(String query,
      [List bindings = listVoid, int? timeoutInSeconds]);

  /// Runs an SQL statement and returns its [PDOResults].
  Future<PDOResults> statement(String query,
      [List bindings = listVoid, int? timeoutInSeconds]);

  /// Runs an SQL statement and returns the number of rows affected.
  Future<int> affectingStatement(String query,
      [List bindings = listVoid, int? timeoutInSeconds]);

  /// Runs [query] as written, without bindings, and returns the number of
  /// rows affected; see [Connection.unprepared].
  Future<int> unprepared(String query, int? timeoutInSeconds);

  /// Returns [bindings] converted for the driver; see
  /// [Connection.prepareBindings].
  List prepareBindings(List bindings);

  /// Runs [callback] in a transaction and returns its result.
  ///
  /// Inside an existing transaction this nests through a SAVEPOINT; see
  /// [Connection.transaction].
  Future<T> transaction<T>(Future<T> Function(Connection ctx) callback,
      [int? timeoutInSeconds]);

  /// Runs [callback] in a transaction, reusing the current one (without a
  /// SAVEPOINT) when this connection is already inside a transaction.
  Future<T> transactionIfNeeded<T>(Future<T> Function(Connection ctx) callback,
      [int? timeoutInSeconds]);

  /// Returns the transaction depth: 0 outside a transaction, 1 in the outer
  /// transaction, 2+ inside nested SAVEPOINTs.
  int transactionLevel();

  /// Whether this connection runs inside a transaction.
  bool get isInTransaction;

  /// Whether [transaction] can nest through SAVEPOINT on this connection.
  bool get supportsSavepoints;

  /// Runs [callback] in "dry run" mode and returns the queries it would have
  /// run.
  Future<List<Map<String, dynamic>>> pretend(Function callback);

  String getDatabaseName();

  SchemaGrammar getSchemaGrammar();
}
