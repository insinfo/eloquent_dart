import 'package:eloquent/eloquent.dart';

class PostgresProcessor extends Processor {
  ///
  /// Process an "insert get ID" query.
  ///
  /// @param  \Illuminate\Database\Query\Builder  $query
  /// @param  string  $sql
  /// @param  array   $values
  /// [sequence] is name of column
  /// @return int
  ///
  Future<dynamic> processInsertGetId(
      QueryBuilder query, String sql, List values,
      [String sequence = 'id']) async {
    var newSql = '$sql returning "$sequence"';
    var results = await query.getConnection().insert(newSql, values);
    // var results = query.getConnection().selectFromWriteConnection(sql, values);
    var result = results[0];
    var id = result[sequence];
    return id;
  }

  ///
  /// Process the results of a column listing query.
  ///
  /// @param  array  $results
  /// @return array
  ///
  List processColumnListing(List results) {
    var mapping = (item) {
      var r = item;
      return r.column_name;
    };

    return Utils.array_map(mapping, results);
  }
}
