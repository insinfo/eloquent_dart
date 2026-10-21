import 'package:eloquent/eloquent.dart';
import 'package:postgres_fork/postgres.dart';

import 'dependencies/postgres_pool/postgres_pool.dart';
import 'postgres_pdo.dart';

class PostgresPDOTransaction extends PDOTransactionContext {
  final PostgreSQLExecutionContext transactionContext;

  @override
  PDOConfig getConfig() {
    return super.pdoInstance.config;
  }

  PostgresPDOTransaction(this.transactionContext, PDOInterface pdo) {
    super.pdoInstance = pdo;
  }

  /// postgres_fork's own savepoint: the driver rolls back its whole
  /// transaction after any SQL error unless the error happens inside a
  /// savepoint it knows about, so a plain `SAVEPOINT` statement could not
  /// keep the transaction usable. [name] is not used (the driver names its
  /// savepoints).
  @override
  Future<T> runInSavepoint<T>(String name, Future<T> Function() body,
          [int? timeoutInSeconds]) =>
      pgSavepoint(transactionContext, body);

  Future<int> execute(String statement, [int? timeoutInSeconds]) {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = (pdoInstance as PostgresV2PDO).queryTimeoutInSeconds;
    }
    return transactionContext.execute(
      statement,
      timeoutInSeconds: timeoutInSeconds,
      placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
    );
  }

  /// Prepares and executes an SQL statement without placeholders
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]) async {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = (pdoInstance as PostgresV2PDO).queryTimeoutInSeconds;
    }
    // final rows = await connection.mappedResultsQuery(
    //   query,
    //   substitutionValues: params,
    //   timeoutInSeconds: timeoutInSeconds,
    //   placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
    // );

    final rs = await transactionContext.query(
      query,
      substitutionValues: params,
      // allowReuse: allowReuse ?? false,
      timeoutInSeconds: timeoutInSeconds,
      placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
    );

    // Same mapping as outside a transaction (PostgresV2PDO.query) and as the
    // other drivers: one entry per column name, the last duplicate wins.
    final maps = rs.map((row) => row.toColumnMap()).toList();

    final pdoResult = PDOResults(maps, rs.affectedRowCount);
    return pdoResult;
  }
}
