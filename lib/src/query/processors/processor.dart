import 'package:eloquent/eloquent.dart';

class Processor {
  /// Post-processes the rows of a select query; the default returns
  /// [results] unchanged.
  List<Map<String, dynamic>> processSelect(
      QueryBuilder query, List<Map<String, dynamic>> results) {
    return results;
  }

  /// Runs the insert [sql] with [values] and returns the generated id: the
  /// [sequence] column of the first returned row, or null without rows.
  Future<dynamic> processInsertGetId(
      QueryBuilder query, String sql, List values,
      [String sequence = 'id']) async {
    final resp = await query.getConnection().insert(sql, values);
    final id = resp.isNotEmpty ? resp.first[sequence] : null;
    return id;
  }

  /// Post-processes the rows of a column listing query; the default returns
  /// [results] unchanged.
  List processColumnListing(List results) {
    return results;
  }
}
