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
    //var newSql = '$sql returning "$sequence"';
    final resp = await query.getConnection().insert(sql, values);
    // var results = query.getConnection().selectFromWriteConnection(sql, values);
    final id = resp.isNotEmpty ? resp.first[sequence] : null;
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
