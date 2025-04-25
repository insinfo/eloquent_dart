// ignore_for_file: unused_element

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

// helper.dart (ou onde sua FakeConnection está definida)
//import 'package:eloquent/eloquent.dart';
import 'dart:async';

class FakeConnection implements ConnectionInterface {
  // --- Propriedades para insert (existentes) ---
  String? lastInsertSql;
  List<dynamic>? lastInsertBindings;
  int insertCallCount = 0;

  // --- NOVAS Propriedades para select ---
  String? lastSelectSql;
  List<dynamic>? lastSelectBindings;
  int selectCallCount = 0;
  // Você pode adicionar mocks para o resultado se precisar testar a resposta
  List<Map<String, dynamic>> mockSelectResult = [];

  @override
  QueryBuilder table(String table) {
    // Use a gramática correta aqui
    return QueryBuilder(this, QueryPostgresGrammar(), Processor()).from(table);
  }

  @override
  QueryExpression raw(value) {
    return QueryExpression(value);
  }

  @override
  Future<Map<String, dynamic>?> selectOne(String query,
      [List bindings = const [], int? timeoutInSeconds]) async {
    // Pode espionar aqui também se precisar testar selectOne
    lastSelectSql = query;
    lastSelectBindings = List.from(bindings);
    selectCallCount++;
    // Retorna o primeiro item do mock ou null
    return mockSelectResult.isNotEmpty ? mockSelectResult.first : null;
  }

  @override
  Future<List<Map<String, dynamic>>> select(String query,
      [List bindings = const [],
      bool useReadPdo = true,
      int? timeoutInSeconds]) async {
    // *** LÓGICA DE CAPTURA PARA SELECT ***
    lastSelectSql = query;
    lastSelectBindings = List.from(bindings); // Copia os bindings
    selectCallCount++;

    // print('--- FakeConnection.select CALLED ---');
    // print('SQL: $query');
    // print('Bindings: $bindings');
    // print('------------------------------------');

    // Retorna o resultado mockado
    // Para o teste de count, ele espera um resultado como [{'aggregate': valor}]
    // Para get, ele espera a lista de mapas. Ajuste mockSelectResult se necessário
    // antes de chamar builder.count() ou builder.get() no teste,
    // ou simplesmente retorne um valor genérico como [] se o resultado não importar.
    // Se o SQL for um COUNT, simule a resposta correta:
    if (query.toLowerCase().contains('count(*) as aggregate') ||
        query.toLowerCase().contains('count("')) {
      //print('FakeConnection returning mocked COUNT result.');
      return Future.value([
        {'aggregate': 10}
      ]); // Exemplo: 10 registros
    }

    //print('FakeConnection returning mocked GET result (length: ${mockSelectResult.length}).');
    return Future.value(
        mockSelectResult); // Retorna a lista mock (pode estar vazia)
  }

  @override
  Future<PDOResults> insert(String query,
      [List bindings = const [], int? timeoutInSeconds]) async {
    lastInsertSql = query;
    lastInsertBindings = List.from(bindings);
    insertCallCount++;
    // print('--- FakeConnection.insert CALLED ---');
    // print('SQL: $query');
    // print('Bindings: $bindings');
    // print('------------------------------------');
    // Retorna sucesso simulado com 1 linha afetada e sem linhas retornadas
    return PDOResults([], 1);
  }

  @override
  Future<dynamic> update(String query,
      [List bindings = const [], int? timeoutInSeconds]) async {
    // Poderia adicionar captura aqui se necessário
    return 1; // Simula 1 linha afetada
  }

  @override
  Future<int> delete(String query,
      [List bindings = const [], int? timeoutInSeconds]) async {
    // Poderia adicionar captura aqui se necessário
    return 1; // Simula 1 linha afetada
  }

  @override
  Future<PDOResults> statement(String query,
      [List bindings = const [], int? timeoutInSeconds]) async {
    // Poderia adicionar captura aqui se necessário
    return PDOResults([], 0);
  }

  @override
  Future<int> affectingStatement(String query,
      [List bindings = const [], int? timeoutInSeconds]) async {
    // Poderia adicionar captura aqui se necessário
    return 0;
  }

  @override
  Future<int> unprepared(String query, int? timeoutInSeconds) async {
    // Poderia adicionar captura aqui se necessário
    return 0;
  }

  @override
  dynamic prepareBindings(List bindings) {
    return bindings; // Implementação simples para testes
  }

  @override
  Future<dynamic> transaction(Future<dynamic> Function(Connection ctx) callback,
      [int? timeoutInSeconds]) async {
    // Simula execução direta sem transação real
    return await callback(this as Connection);
  }

  @override
  int transactionLevel() {
    return 0;
  }

  @override
  Future<dynamic> pretend(Function callback) async {
    // Simula o modo pretend retornando queries vazias (ou mocks se necessário)
    //print("FakeConnection: Pretend mode called (returning empty list)");
    try {
      await callback(this); // Executa o callback para gerar chamadas internas
    } catch (e) {
      // Ignora erros dentro do pretend, pois o objetivo é capturar SQL
      //print("FakeConnection: Ignored error during pretend: $e");
    }
    // No pretend real, você coletaria o SQL gerado. Aqui, retornamos vazio.
    return [];
  }

  @override
  String getDatabaseName() {
    return 'fakedb';
  }

  @override
  SchemaGrammar getSchemaGrammar() {
    return SchemaPostgresGrammar(); // Usa a gramática correta
  }

  // Método `getConfig` adicionado para compatibilidade
  dynamic getConfig(String option) {
    if (option == 'schema') return 'public'; // Exemplo, ajuste se necessário
    if (option == 'database') return 'fakedb';
    if (option == 'charset') return 'utf8';
    return null;
  }

  // *** ATUALIZAÇÃO no reset ***
  void reset() {
    lastInsertSql = null;
    lastInsertBindings = null;
    insertCallCount = 0;
    // Reseta os novos campos de select
    lastSelectSql = null;
    lastSelectBindings = null;
    selectCallCount = 0;
    mockSelectResult = []; // Limpa o mock de resultado
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
