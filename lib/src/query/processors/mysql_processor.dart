import 'package:eloquent/eloquent.dart';

class MySqlProcessor extends Processor {
  ///
  /// Process the results of a column listing query.
  ///
  /// @param  array  $results
  /// @return array
  ///
  // processColumnListing(results) {
  //   var mapping = ($r) {
  //     return $r.column_name;
  //   };

  //   return array_map(mapping, results);
  // }

  ///
  /// Process an  "insert get ID" query.
  ///
  /// @param  \Illuminate\Database\Query\Builder  $query
  /// @param  string  $sql
  /// @param  array   $values
  /// @param  string  $sequence
  /// @return int
  ///
  Future<dynamic> processInsertGetId(
      QueryBuilder query, String sql, List values,
      [String sequence = 'id']) async {
    await query.getConnection().insert(sql, values);
    final resp =
        await query.getConnection().select('SELECT LAST_INSERT_ID() as id;');
    final id = resp.isNotEmpty ? resp.first['id'] : null;
    return id;
    //var id = query.getConnection().getPdo().lastInsertId(sequence);
    //return is_numeric($id) ? (int) $id : $id;
    //return -1;
  }
}
