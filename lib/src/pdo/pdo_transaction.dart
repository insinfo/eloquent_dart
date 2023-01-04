import 'package:dargres/dargres.dart';
import 'package:eloquent/src/pdo/pdo_statement.dart';

import 'pdo.dart';
import 'pdo_constants.dart';
import 'pdo_execution_context.dart';

class PDOTransaction extends PDOExecutionContext{

  final TransactionContext transactionContext;

  PDOTransaction(this.transactionContext,PDO pdo){
     super.pdoInstance = pdo;
  }
  
  
  Future<int> execute(String statement) {
   return transactionContext.execute(statement);
  }

  Future<PDOStatement> prepareStatement(String query, dynamic params) async {
    //print('PDO@prepare query: $query');
    //throw UnimplementedError();
    final postgresQuery = await transactionContext.prepareStatement(query, params,
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark);
    return PDOStatement(postgresQuery);
  }

  Future<dynamic> executeStatement(PDOStatement statement,
      [int? fetchMode]) async {
    var results = await transactionContext.executeStatement(statement.postgresQuery!);
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
  Future<dynamic> query(String query, [int? fetchMode]) async {
    var results = await transactionContext.queryUnnamed(query, []);
    switch (fetchMode) {
      case PDO_FETCH_ASSOC:
        return results.toMaps();
      case PDO_FETCH_ASSOC:
        return results;
    }
    return results;
  }

}