import 'package:eloquent/eloquent.dart';

class PostgresProcessor extends Processor {
  ///
  /// Process an "insert get ID" query.
  ///
  /// @param  \Illuminate\Database\Query\Builder  $query
  /// @param  string  $sql
  /// @param  array   $values
  /// @param  string  $sequence
  /// @return int
  ///
  int processInsertGetId(QueryBuilder query, String sql, List values,
      [String? sequenceP]) {
    // var results = query.getConnection().selectFromWriteConnection(sql, values);
    // var sequence = sequenceP ?? 'id';
    // var result = results[0];
    // var id = result[sequence];
    //return is_numeric(id) ?  id  as int: id;
    return -1;
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
