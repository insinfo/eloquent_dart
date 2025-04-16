// ignore_for_file: unused_element

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

class FakeConnection implements ConnectionInterface {
  @override
  QueryBuilder table(String table) {
    throw UnimplementedError();
  }

  @override
  QueryExpression raw(value) {
    return QueryExpression(value);
  }

  @override
  Future<Map<String, dynamic>?> selectOne(String query,
      [List bindings = const [], int? timeoutInSeconds]) {
    throw UnimplementedError();
  }

  @override
  Future<List<Map<String, dynamic>>> select(String query,
      [List bindings = const [],
      bool useReadPdo = true,
      int? timeoutInSeconds]) {
    throw UnimplementedError();
  }

  @override
  Future<PDOResults> insert(String query,
      [List bindings = const [], int? timeoutInSeconds]) {
    throw UnimplementedError();
  }

  @override
  Future<dynamic> update(String query,
      [List bindings = const [], int? timeoutInSeconds]) {
    throw UnimplementedError();
  }

  @override
  Future<int> delete(String query,
      [List bindings = const [], int? timeoutInSeconds]) {
    throw UnimplementedError();
  }

  @override
  Future<PDOResults> statement(String query,
      [List bindings = const [], int? timeoutInSeconds]) {
    throw UnimplementedError();
  }

  @override
  Future<int> affectingStatement(String query,
      [List bindings = const [], int? timeoutInSeconds]) {
    throw UnimplementedError();
  }

  @override
  Future<int> unprepared(String query, int? timeoutInSeconds) {
    throw UnimplementedError();
  }

  @override
  dynamic prepareBindings(List bindings) {
    throw UnimplementedError();
  }

  @override
  Future<dynamic> transaction(Future<dynamic> Function(Connection ctx) callback,
      [int? timeoutInSeconds]) {
    throw UnimplementedError();
  }

  @override
  int transactionLevel() {
    throw UnimplementedError();
  }

  @override
  Future<dynamic> pretend(Function callback) {
    throw UnimplementedError();
  }

  @override
  String getDatabaseName() {
    throw UnimplementedError();
  }

  @override
  SchemaGrammar getSchemaGrammar() {
    throw UnimplementedError();
  }
}

class FakeQueryBuilder extends QueryBuilder {
  FakeQueryBuilder({List<String>? columns, String? from})
      : super(FakeConnection(), QueryPostgresGrammar(), Processor()) {
    columnsProp = columns;
    fromProp = from;
  }

  @override
  List<dynamic>? getColumns() {
    return columnsProp;
  }
}

// Helper para comparação ignorando case, útil para palavras-chave SQL
// Matcher equalsIgnoringCase(String expected) =>
//     _EqualsIgnoringCaseMatcher(expected);

class _EqualsIgnoringCaseMatcher extends Matcher {
  final String _expected;
  _EqualsIgnoringCaseMatcher(this._expected);

  @override
  Description describe(Description description) =>
      description.add('equals ignoring case ').addDescriptionOf(_expected);

  @override
  bool matches(item, Map matchState) {
    if (item is! String) return false;
    return item.toLowerCase() == _expected.toLowerCase();
  }

  @override
  Description describeMismatch(
      item, Description mismatchDescription, Map matchState, bool verbose) {
    if (item is! String) {
      return mismatchDescription.add('is not a String');
    }
    return mismatchDescription
        .add('is ')
        .addDescriptionOf(item)
        .add(' which does not equal ')
        .addDescriptionOf(_expected)
        .add(' ignoring case.');
  }
}

// Helper Matcher para verificação de substring ignorando case
Matcher containsIgnoringCase(String expectedSubstring) =>
    _ContainsIgnoringCaseMatcher(expectedSubstring);

class _ContainsIgnoringCaseMatcher extends Matcher {
  final String _expectedSubstringLower;

  _ContainsIgnoringCaseMatcher(String expectedSubstring)
      : _expectedSubstringLower = expectedSubstring.toLowerCase();

  @override
  Description describe(Description description) => description
      .add('contains ignoring case ')
      .addDescriptionOf(_expectedSubstringLower);

  @override
  bool matches(item, Map matchState) {
    if (item is! String) return false;
    return item.toLowerCase().contains(_expectedSubstringLower);
  }

  @override
  Description describeMismatch(
      item, Description mismatchDescription, Map matchState, bool verbose) {
    if (item is! String) {
      return mismatchDescription.add('is not a String');
    }
    return mismatchDescription
        .add('is ')
        .addDescriptionOf(item)
        .add(' which does not contain ')
        .addDescriptionOf(_expectedSubstringLower)
        .add(' ignoring case.');
  }
}
