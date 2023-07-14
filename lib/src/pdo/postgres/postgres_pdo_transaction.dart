import 'package:eloquent/eloquent.dart';
import 'package:postgres/postgres.dart';

import 'postgres_pdo.dart';

class PostgresPDOTransaction extends PDOExecutionContext {
  final PostgreSQLExecutionContext transactionContext;

  PostgresPDOTransaction(this.transactionContext, PDOInterface pdo) {
    super.pdoInstance = pdo;
  }

  Future<int> execute(String statement, [int? timeoutInSeconds]) {
    if (timeoutInSeconds == null) {
      timeoutInSeconds = PostgresPDO.defaultTimeoutInSeconds;
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
      timeoutInSeconds = PostgresPDO.defaultTimeoutInSeconds;
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

    final rows = rs.map((row) => row.toTableColumnMap()).toList();

    final maps = <Map<String, dynamic>>[];
    if (rows.isNotEmpty) {
      for (var item in rows) {
        //Combine/merge multiple maps into 1 map
        maps.add(item.values.reduce((map1, map2) => map1..addAll(map2)));
      }
    }

    final pdoResult = PDOResults(maps, rs.affectedRowCount);
    return pdoResult;
  }
}
