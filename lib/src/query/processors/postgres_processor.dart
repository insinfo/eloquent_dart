import 'package:eloquent/eloquent.dart';

class PostgresProcessor extends Processor {
  /// Runs the insert [sql] (compiled with `returning "<sequence>"`) with
  /// [values] and returns the [sequence] column of the first returned row,
  /// or null without rows.
  Future<dynamic> processInsertGetId(
      QueryBuilder query, String sql, List values,
      [String sequence = 'id']) async {
    //var newSql = '$sql returning "$sequence"';
    final resp = await query.getConnection().insert(sql, values);
    final id = resp.isNotEmpty ? resp.first[sequence] : null;
    return id;
  }

  /// Maps each row (a map) of a column listing query to its `column_name`.
  List processColumnListing(List results) {
    return [for (final row in results) (row as Map)['column_name']];
  }
}
