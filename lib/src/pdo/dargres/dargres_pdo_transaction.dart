import 'package:dargres/dargres.dart';
import 'package:eloquent/eloquent.dart';

class DargresPDOTransaction extends PDOExecutionContext {
  final TransactionContext transactionContext;
  
  @override
  PDOConfig getConfig() {
    return super.pdoInstance.config;
  }

  DargresPDOTransaction(this.transactionContext, PDOInterface pdo) {
    super.pdoInstance = pdo;
  }

  Future<int> execute(String statement, [int? timeoutInSeconds]) {
    return transactionContext.execute(statement);
  }

  /// Prepares and executes an SQL statement without placeholders
  Future<PDOResults> query(String query,
      [dynamic params, int? timeoutInSeconds]) async {
    final results = await transactionContext.queryNamed(query, params ?? [],
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark);
    final pdoResult = PDOResults(results.toMaps(), results.rowsAffected.value);
    return pdoResult;
  }
}
