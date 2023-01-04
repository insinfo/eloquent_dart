import 'package:dargres/dargres.dart';



///
class PDOStatement {
  final Query? postgresQuery;

  int rowsAffected = 0;

  //Results? _results;

  PDOStatement(this.postgresQuery);

  /// Executes a prepared statement
  // Future<dynamic> executeStatement([params]) async {
  //   //print('PDOStatement@execute params: $params');
  //   _postgresQuery.addPreparedParams(params);
  //   _results = await _postgresQuery.executeStatement();
  //   // print('PDOStatement@execute _results: $_results');
  //   return true;
  // }

  // Future<dynamic> fetchAll(int fetchMode) async {
  //   print('PDOStatement@fetchAll fetchMode $fetchMode');
  //   //throw UnimplementedError();
  //   switch (fetchMode) {
  //     case PDO_FETCH_ASSOC:
  //       return _results!.toMaps();
  //     case PDO_FETCH_ASSOC:
  //       return _results;
  //   }
  //   return _results;
  // }

  // /// Returns the number of rows affected by the last SQL statement
  // Future<int> rowCount() async {
  //   return _results != null ? _results!.rowsAffected.value : 0;
  // }
}
