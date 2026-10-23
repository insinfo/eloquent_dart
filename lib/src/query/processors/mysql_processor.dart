import 'package:eloquent/eloquent.dart';

class MySqlProcessor extends Processor {
  /// Runs the insert [sql] with [values] and returns the generated id, read
  /// from the insert result; [sequence] is unused.
  ///
  /// When the result has no id it falls back to `SELECT LAST_INSERT_ID()`.
  Future<dynamic> processInsertGetId(
      QueryBuilder query, String sql, List values,
      [String sequence = 'id']) async {
    // The id comes with the INSERT result (OK packet). A separate
    // `SELECT LAST_INSERT_ID()` could run on another pooled connection, or
    // after another caller's insert on the same connection, and return
    // someone else's id.
    final result = await query.getConnection().insert(sql, values);
    if (result.insertId != null) return result.insertId;
    final resp =
        await query.getConnection().select('SELECT LAST_INSERT_ID() as id;');
    return resp.isNotEmpty ? resp.first['id'] : null;
  }
}
