// ignore_for_file: unused_element

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

class FakeConnection implements ConnectionInterface {
  // Propriedades para "espionar" a chamada a insert
  String? lastInsertSql;
  List<dynamic>? lastInsertBindings;
  int insertCallCount = 0;

  @override
  QueryBuilder table(String table) {
    // Retorne um builder funcional para subqueries, mas usando esta conexão fake
    return QueryBuilder(this, QueryPostgresGrammar(), Processor()).from(table);
  }

  @override
  QueryExpression raw(value) {
    return QueryExpression(value);
  }

  @override
  Future<Map<String, dynamic>?> selectOne(String query,
      [List bindings = const [], int? timeoutInSeconds]) async {
    //print('FakeConnection.selectOne called (unimplemented)');
    return null; // Ou um valor simulado se necessário
  }

  @override
  Future<List<Map<String, dynamic>>> select(String query,
      [List bindings = const [],
      bool useReadPdo = true,
      int? timeoutInSeconds]) async {
    //print('FakeConnection.select called (unimplemented)');
    return []; // Ou um valor simulado
  }

  // *** MODIFICAÇÃO PRINCIPAL AQUI ***
  @override
  Future<PDOResults> insert(String query,
      [List bindings = const [], int? timeoutInSeconds]) async {
    // Grava os argumentos passados
    lastInsertSql = query;
    lastInsertBindings = List.from(bindings); // Cria uma cópia
    insertCallCount++;

    //print('FakeConnection.insert CALLED with SQL: $query');
    //print('FakeConnection.insert CALLED with Bindings: $bindings');

    // Retorna um resultado simulado (não importa muito para este teste)
    // O importante é que seja um Future<PDOResults>
    return PDOResults([], 1); // Ex: 1 linha afetada
  }
  // *** FIM DA MODIFICAÇÃO ***

  @override
  Future<dynamic> update(String query,
      [List bindings = const [], int? timeoutInSeconds]) async {
    //print('FakeConnection.update called (unimplemented)');
    return 0; // Ex: 0 linhas afetadas
  }

  @override
  Future<int> delete(String query,
      [List bindings = const [], int? timeoutInSeconds]) async {
    // print('FakeConnection.delete called (unimplemented)');
    return 0;
  }

  @override
  Future<PDOResults> statement(String query,
      [List bindings = const [], int? timeoutInSeconds]) async {
    // print('FakeConnection.statement called (unimplemented)');
    return PDOResults([], 0);
  }

  @override
  Future<int> affectingStatement(String query,
      [List bindings = const [], int? timeoutInSeconds]) async {
    // print('FakeConnection.affectingStatement called (unimplemented)');
    return 0;
  }

  @override
  Future<int> unprepared(String query, int? timeoutInSeconds) async {
    // print('FakeConnection.unprepared called (unimplemented)');
    return 0;
  }

  @override
  dynamic prepareBindings(List bindings) {
    // Implementação simples para testes: apenas retorna os bindings
    // A implementação real faria conversões (DateTime -> String, bool -> int/bool)
    return bindings;
  }

  @override
  Future<dynamic> transaction(Future<dynamic> Function(Connection ctx) callback,
      [int? timeoutInSeconds]) async {
    //print('FakeConnection.transaction called (simulating success)');
    // Simula a execução do callback dentro de uma transação fake
    return await callback(
        this as Connection); // Passa a própria fake connection
  }

  @override
  int transactionLevel() {
    return 0; // Simula que não há transação ativa
  }

  @override
  Future<dynamic> pretend(Function callback) async {
    //print('FakeConnection.pretend called (unimplemented)');
    return [];
  }

  @override
  String getDatabaseName() {
    return 'fakedb'; // Nome dummy
  }

  @override
  SchemaGrammar getSchemaGrammar() {
    // Retorna a gramática de schema apropriada para evitar erros
    // na gramática de query que pode precisar dela.
    return SchemaPostgresGrammar(); // Ou a SchemaGrammar relevante
  }

  // Método `getConfig` adicionado para compatibilidade, se necessário
  dynamic getConfig(String option) {
    // Retorna um valor dummy ou um mapa vazio, dependendo do que a gramática precisa
    // Exemplo básico:
    if (option == 'schema' || option == 'database') return 'fakedb';
    if (option == 'charset') return 'utf8'; // Exemplo
    return null; // Ou {}
  }

  // Adiciona um método para resetar o estado antes de cada teste
  void reset() {
    lastInsertSql = null;
    lastInsertBindings = null;
    insertCallCount = 0;
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
