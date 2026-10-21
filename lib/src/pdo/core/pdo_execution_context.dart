import '../../driver/driver_access.dart';
import '../../exceptions/unsupported_nested_transaction_exception.dart';
import 'pdo_config.dart';
import 'pdo_interface.dart';
import 'pdo_result.dart';

abstract class PDOExecutionContext {
  late PDOInterface pdoInstance;

  /// Executa uma instrução SQL e retornar o número de linhas afetadas
  Future<int> execute(String statement, [int? timeoutInSeconds]);
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]);

  /// Stream rows from a query using a server-side cursor / incremental reader,
  /// keeping memory roughly constant regardless of result-set size.
  ///
  /// Default: [UnsupportedError]. Driver adapters that expose an incremental
  /// reader (e.g. dpgsql's `executeReader`) override this. [fetchSize] is a
  /// hint for the number of rows to buffer per network round-trip.
  Stream<Map<String, dynamic>> queryStream(String query,
      [dynamic params, int? fetchSize]) {
    throw UnsupportedError(
      'Streaming (cursor) is not supported by this driver adapter.',
    );
  }

  /// Whether [queryStream] is implemented (an incremental reader). Without
  /// it, `Connection.cursor` falls back to an SQL cursor (`DECLARE ...
  /// FETCH`) on PostgreSQL.
  bool get supportsQueryStream => false;

  /// Direct, driver-specific access (COPY, pipelining, LISTEN/NOTIFY, raw
  /// connection). Returns `null` when the adapter has no such capabilities.
  DriverAccess? driverAccess() => null;

  PDOConfig getConfig();

  /// Whether this context runs inside a database transaction. The state
  /// belongs to the context object itself, never to global/static state, so
  /// concurrent requests each see their own transaction.
  bool get isInTransaction => false;

  /// Transaction depth: `0` outside a transaction, `1` for the transaction
  /// opened by `runInTransaction`, `2+` for each nested SAVEPOINT.
  int get transactionLevel => 0;

  /// Whether [createSavepoint]/[rollbackToSavepoint]/[releaseSavepoint] work
  /// on this context.
  bool get supportsSavepoints => false;

  Future<void> createSavepoint(String name, [int? timeoutInSeconds]) =>
      Future<void>.error(UnsupportedNestedTransactionException());

  Future<void> rollbackToSavepoint(String name, [int? timeoutInSeconds]) =>
      Future<void>.error(UnsupportedNestedTransactionException());

  Future<void> releaseSavepoint(String name, [int? timeoutInSeconds]) =>
      Future<void>.error(UnsupportedNestedTransactionException());
}

final RegExp _savepointName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

String _checkedSavepointName(String name) {
  if (!_savepointName.hasMatch(name)) {
    throw ArgumentError.value(name, 'name', 'Invalid SAVEPOINT name.');
  }
  return name;
}

/// Base for the context a driver hands to `runInTransaction` (transaction
/// level 1). SAVEPOINTs are issued as plain SQL on the same transaction, which
/// PostgreSQL and MySQL both accept.
abstract class PDOTransactionContext extends PDOExecutionContext {
  @override
  bool get isInTransaction => true;

  @override
  int get transactionLevel => 1;

  @override
  bool get supportsSavepoints => true;

  @override
  Future<void> createSavepoint(String name, [int? timeoutInSeconds]) async {
    await execute('SAVEPOINT ${_checkedSavepointName(name)}', timeoutInSeconds);
  }

  @override
  Future<void> rollbackToSavepoint(String name, [int? timeoutInSeconds]) async {
    await execute('ROLLBACK TO SAVEPOINT ${_checkedSavepointName(name)}',
        timeoutInSeconds);
  }

  @override
  Future<void> releaseSavepoint(String name, [int? timeoutInSeconds]) async {
    await execute(
        'RELEASE SAVEPOINT ${_checkedSavepointName(name)}', timeoutInSeconds);
  }
}

/// A nested transaction (SAVEPOINT) over an enclosing transaction context.
///
/// Every operation runs on the enclosing context; only [transactionLevel]
/// differs, so this works for any driver without knowing its classes.
class NestedPDOTransaction extends PDOExecutionContext {
  NestedPDOTransaction(this.parent, this.transactionLevel) {
    pdoInstance = parent.pdoInstance;
  }

  /// The enclosing transaction (level `transactionLevel - 1`).
  final PDOExecutionContext parent;

  @override
  final int transactionLevel;

  @override
  bool get isInTransaction => true;

  @override
  bool get supportsSavepoints => parent.supportsSavepoints;

  @override
  Future<int> execute(String statement, [int? timeoutInSeconds]) =>
      parent.execute(statement, timeoutInSeconds);

  @override
  Future<PDOResults> query(String query,
          [dynamic params, int? timeoutInSeconds]) =>
      parent.query(query, params, timeoutInSeconds);

  @override
  Stream<Map<String, dynamic>> queryStream(String query,
          [dynamic params, int? fetchSize]) =>
      parent.queryStream(query, params, fetchSize);

  @override
  bool get supportsQueryStream => parent.supportsQueryStream;

  @override
  DriverAccess? driverAccess() => parent.driverAccess();

  @override
  PDOConfig getConfig() => parent.getConfig();

  @override
  Future<void> createSavepoint(String name, [int? timeoutInSeconds]) =>
      parent.createSavepoint(name, timeoutInSeconds);

  @override
  Future<void> rollbackToSavepoint(String name, [int? timeoutInSeconds]) =>
      parent.rollbackToSavepoint(name, timeoutInSeconds);

  @override
  Future<void> releaseSavepoint(String name, [int? timeoutInSeconds]) =>
      parent.releaseSavepoint(name, timeoutInSeconds);
}
