import 'package:dargres/dargres.dart';
import 'package:eloquent/src/pdo/pdo_statement.dart';

import 'pdo.dart';
import 'pdo_constants.dart';
import 'pdo_execution_context.dart';

class PDOTransaction extends PDOExecutionContext {
  final TransactionContext transactionContext;

  int rowsAffected = 0;

  PDOTransaction(this.transactionContext, PDO pdo) {
    super.pdoInstance = pdo;
  }

  Future<int> execute(String statement,
      [Duration? timeout = PDO.defaultTimeout]) {
    return transactionContext.execute(statement, timeout: timeout);
  }

  Future<PDOStatement> prepareStatement(String query, dynamic params,
      [Duration? timeout = PDO.defaultTimeout]) async {
    //print('PDO@prepare query: $query');
    //throw UnimplementedError();
    final postgresQuery = await transactionContext.prepareStatement(
        query, params,
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
        timeout: timeout);
    return PDOStatement(postgresQuery);
  }

  Future<dynamic> executeStatement(PDOStatement statement,
      [int? fetchMode, Duration? timeout = PDO.defaultTimeout]) async {
    var results = await transactionContext
        .executeStatement(statement.postgresQuery!, timeout: timeout);
    statement.rowsAffected = results.rowsAffected.value;
    switch (fetchMode) {
      case PDO_FETCH_ASSOC:
        return results.toMaps();
      case PDO_FETCH_ASSOC:
        return results;
    }
    return results;
  }

  /// Prepares and executes an SQL statement without placeholders
  Future<dynamic> query(String query,
      [int? fetchMode, Duration? timeout = PDO.defaultTimeout]) async {
    var results =
        await transactionContext.queryNamed(query, [], timeout: timeout);
    switch (fetchMode) {
      case PDO_FETCH_ASSOC:
        return results.toMaps();
      case PDO_FETCH_ASSOC:
        return results;
    }
    return results;
  }

  Future<dynamic> queryNamed(String query, dynamic params,
      [int? fetchMode, Duration? timeout = PDO.defaultTimeout]) async {
    var results = await transactionContext.queryNamed(query, params,
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
        timeout: timeout);
    rowsAffected = results.rowsAffected.value;
    switch (fetchMode) {
      case PDO_FETCH_ASSOC:
        return results.toMaps();
      case PDO_FETCH_ASSOC:
        return results;
    }
    return results;
  }

  Future<dynamic> queryUnnamed(String query, dynamic params,
      [int? fetchMode, Duration? timeout = PDO.defaultTimeout]) async {
    //  print('PDOTransaction@queryNamed timeout $timeout');
    var results = await transactionContext.queryUnnamed(query, params,
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
        timeout: timeout);
    rowsAffected = results.rowsAffected.value;
    switch (fetchMode) {
      case PDO_FETCH_ASSOC:
        return results.toMaps();
      case PDO_FETCH_ASSOC:
        return results;
    }
    return results;
  }
}
