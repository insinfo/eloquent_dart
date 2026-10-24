import 'package:eloquent/src/pdo/core/pdo_config.dart';
import 'package:eloquent/src/pdo/core/pdo_execution_context.dart';
import 'package:eloquent/src/pdo/core/pdo_interface.dart';
import 'package:eloquent/src/pdo/core/pdo_result.dart';
import 'package:postgres/postgres.dart';
import 'postgres_v3_pdo.dart';
import 'postgres_v3_values.dart';

/// `ROLLBACK [WORK | TRANSACTION] TO [SAVEPOINT] name`.
final RegExp _rollbackToSavepoint = RegExp(
    r'^\s*rollback\s+(?:work\s+|transaction\s+)?to\s',
    caseSensitive: false);

class PostgresV3PDOTransaction extends PDOTransactionContext {
  /// The connection reserved for the transaction (taken from the pool, or
  /// the single connection under the adapter's lock), between the BEGIN and
  /// the COMMIT that [PostgresV3PDO] sends on it.
  final Session transactionContext;

  /// The error that aborted the transaction on the server, or null while it
  /// can still commit.
  ///
  /// After any error PostgreSQL rejects every statement until a ROLLBACK TO
  /// SAVEPOINT, and answers COMMIT with a ROLLBACK, not with an error. The
  /// package does not expose the transaction status of the server, so it is
  /// tracked here: an error sets it, a ROLLBACK TO SAVEPOINT that succeeds
  /// clears it. That is exact, because no SAVEPOINT can be created in an
  /// aborted transaction: any savepoint rolled back to was created before
  /// the error.
  Object? abortedBy;

  @override
  PDOConfig getConfig() {
    return super.pdoInstance.config;
  }

  PostgresV3PDOTransaction(this.transactionContext, PDOInterface pdo) {
    super.pdoInstance = pdo;
  }

  Future<R> _tracked<R>(String statement, Future<R> Function() run) async {
    try {
      final result = await run();
      if (_rollbackToSavepoint.hasMatch(statement)) abortedBy = null;
      return result;
    } catch (e) {
      abortedBy ??= e;
      rethrow;
    }
  }

  Future<int> execute(String statement, [int? timeoutInSeconds]) {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = (pdoInstance as PostgresV3PDO).queryTimeoutInSeconds;
    }
    // Simple query protocol, as in PostgresV3PDO.execute.
    return _tracked(statement, () async {
      final res = await transactionContext.execute(
        statement,
        queryMode: QueryMode.simple,
        timeout: Duration(seconds: timeoutInSeconds!),
      );
      return res.affectedRows;
    });
  }

  /// Prepares and executes an SQL statement with placeholders
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]) {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = (pdoInstance as PostgresV3PDO).queryTimeoutInSeconds;
    }

    return _tracked(query, () async {
      final rs = await transactionContext.execute(
        Sql.indexed(query, substitution: '?'),
        parameters: params,
        timeout: Duration(seconds: timeoutInSeconds!),
      );
      return PDOResults(postgresV3Rows(getConfig(), rs), rs.affectedRows);
    });
  }
}
