import 'dart:collection';

/// this is Result set of Rows from database
class PDOResults extends ListBase<Map<String, dynamic>> {
  final List<Map<String, dynamic>> rows;
  final int rowsAffected;

  PDOResults(this.rows, this.rowsAffected);

  int get length => rows.length;

  @override
  operator [](int index) {
    return rows[index];
  }

  @override
  void add(Map<String, dynamic> element) {
    rows.add(element);
  }

  @override
  void addAll(Iterable<Map<String, dynamic>> iterable) {
    rows.addAll(iterable);
  }

  @override
  void operator []=(int index, value) {
    rows[index] = value;
  }

  @override
  set length(int newLength) {
    UnimplementedError();
  }
}
