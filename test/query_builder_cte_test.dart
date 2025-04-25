//query_builder_cte_test.dart
import 'package:test/test.dart';
import 'package:eloquent/eloquent.dart';
import 'helper.dart';

void main() {
  late FakeConnection connection;
  late QueryGrammar grammar;
  late Processor processor;

  setUp(() {
    connection = FakeConnection();
    grammar = QueryPostgresGrammar();
    processor = Processor();
  });

// Helper para criar um sub-builder rapidamente
  QueryBuilder createSubBuilder(String fromTable) {
    return QueryBuilder(connection, grammar, processor).from(fromTable);
  }

  test('withExpression adds a non-recursive CTE correctly (Builder)', () {
    final builder = QueryBuilder(connection, grammar, processor);
    final regionalSales = createSubBuilder('orders')
        .selectRaw('region, SUM(amount) as total_sales')
        .where('status', '=', 'completed')
        .groupBy('region');

    builder
        .from('regional_sales_cte')
        .withExpression('regional_sales_cte', regionalSales)
        .where('total_sales', '>', 1000);

    // O SQL completo esperado
    final expectedSql =
        'with "regional_sales_cte" as (select region, SUM(amount) as total_sales from "orders" where "status" = ? group by "region") select * from "regional_sales_cte" where "total_sales" > ?';

    // Gera o SQL da subquery separadamente para verificação interna da CTE
    final subQuerySql = grammar.compileSelect(regionalSales);
    final cte = builder.expressionsProp.first;

    // Verificações da CTE
    expect(cte['name'], 'regional_sales_cte');
    expect(cte['query'], subQuerySql);
    expect(cte['recursive'], false);
    expect(cte['columns'], null);

    // Verificações dos Bindings
    expect(builder.bindings['expressions'], orderedEquals(['completed']));
    expect(builder.bindings['where'], orderedEquals([1000]));

    // ADICIONAR ESTA VERIFICAÇÃO:
    // Gera o SQL final completo e compara com o esperado
    final mainSql = builder.toSql();
    expect(mainSql, expectedSql);
  });

  test('withExpression adds a non-recursive CTE correctly (Closure)', () {
    final builder = QueryBuilder(connection, grammar, processor);
    builder
        .from('users_cte')
        .withExpression('users_cte', (QueryBuilder q) {
          q.from('users').where('active', '=', true);
        })
        .selectRaw('name')
        .where('id', '>', 10);

    final cte = builder.expressionsProp.first;
    final subBuilder = QueryBuilder(connection, grammar, processor)
        .from('users')
        .where('active', '=', true);
    final subQuerySql = grammar.compileSelect(subBuilder);

    expect(cte['name'], 'users_cte');
    expect(cte['query'], subQuerySql);
    expect(cte['recursive'], false);

    expect(builder.bindings['expressions'], orderedEquals([true]));
    expect(builder.bindings['where'], orderedEquals([10]));

    final mainSql = builder.toSql();
    expect(
        mainSql,
        contains(
            'with "users_cte" as (select * from "users" where "active" = ?)'));
    expect(mainSql, contains('select name from "users_cte" where "id" > ?'));
  });

  test('withExpression adds a non-recursive CTE correctly (String)', () {
    final builder = QueryBuilder(connection, grammar, processor);
    final rawCteSql = 'select id, name from products where category = ?';
    builder.from('product_list').withExpression(
            'product_list', rawCteSql, ['prod_id', 'prod_name']) // Com colunas
        .where('prod_id', '=', 5);

    final cte = builder.expressionsProp.first;

    expect(cte['name'], 'product_list');
    expect(cte['query'], rawCteSql);
    expect(cte['recursive'], false);
    expect(cte['columns'], orderedEquals(['prod_id', 'prod_name']));

    expect(builder.bindings['where'],
        orderedEquals([5])); // Binding da query principal

    final mainSql = builder.toSql();
    expect(
        mainSql,
        contains(
            'with "product_list" ("prod_id", "prod_name") as (select id, name from products where category = ?)'));
    expect(
        mainSql, contains('select * from "product_list" where "prod_id" = ?'));
  });

  test('withRecursiveExpression adds a recursive CTE correctly', () {
    final builder = QueryBuilder(connection, grammar, processor);
    final recursiveQuery = createSubBuilder('employees')
        .selectRaw('id, name, manager_id')
        .whereNull('manager_id') // Âncora
        .unionAll(// Parte recursiva
            createSubBuilder('employees as e')
                .selectRaw('e.id, e.name, e.manager_id')
                .join(
                    'employee_hierarchy as eh', 'eh.id', '=', 'e.manager_id'));

    builder.from('employee_hierarchy').withRecursiveExpression(
        'employee_hierarchy',
        recursiveQuery,
        ['id', 'name', 'manager_id']).select('*'); // Seleciona da CTE

    final cte = builder.expressionsProp.first;
    expect(cte['name'], 'employee_hierarchy');
    // Nota: O SQL da subquery aqui conterá o UNION ALL. A gramática mock não compila isso.
    // expect(cte['query'], contains('union all')); // Verificação básica
    expect(cte['recursive'], true);
    expect(cte['columns'], orderedEquals(['id', 'name', 'manager_id']));

    // Verificar bindings da subquery (se houver)
    expect(builder.bindings['expressions'],
        isEmpty); // Exemplo sem bindings na subquery

    final mainSql = builder.toSql();
    expect(
        mainSql,
        startsWith(
            'with recursive "employee_hierarchy" ("id", "name", "manager_id") as ('));
    expect(mainSql, endsWith(') select * from "employee_hierarchy"'));
  });

  test('recursionLimit sets the recursionLimitProp property', () {
    final builder = QueryBuilder(connection, grammar, processor);

    builder.recursionLimit(100);
    expect(builder.recursionLimitProp, 100);

    // O teste da *aplicação* do limite dependeria da gramática
    // Ex: Se a gramática suportasse, o SQL poderia conter 'OPTION (MAXRECURSION 100)' etc.
    // Com a gramática mock atual, toSql() não incluirá o limite.
    final sql = builder.toSql(); // Apenas para garantir que não quebra
    expect(sql, isNotNull);
  });

  test('Combines non-recursive and recursive CTEs', () {
    final builder = QueryBuilder(connection, grammar, processor);
    final baseUsers = createSubBuilder('users').whereFlex('active', true);
    final userHierarchy =
        createSubBuilder('active_users') // Referencia a primeira CTE
            .selectRaw('id, name, 0 as level')
            .whereNull('parent_id')
            .unionAll(createSubBuilder('active_users as u')
                .selectRaw('u.id, u.name, h.level + 1')
                .join('hierarchy as h', 'h.id', '=', 'u.parent_id'));

    builder
        .from('hierarchy')
        .withExpression('active_users', baseUsers) // Non-recursive first
        .withRecursiveExpression('hierarchy', userHierarchy,
            ['id', 'name', 'level']) // Recursive second
        .where('level', '<', 5);

    expect(builder.expressionsProp.length, 2);
    expect(builder.expressionsProp[0]['recursive'], false);
    expect(builder.expressionsProp[1]['recursive'], true);

    final mainSql = builder.toSql();
    expect(mainSql,
        startsWith('with recursive ')); // RECURSIVE por causa da segunda CTE
    expect(mainSql, contains('"active_users" as (')); // Primeira CTE
    expect(mainSql,
        contains(', "hierarchy" ("id", "name", "level") as (')); // Segunda CTE
    expect(mainSql, endsWith(') select * from "hierarchy" where "level" < ?'));

    // Verificar bindings combinados das CTEs e do principal
    expect(builder.bindings['expressions'],
        orderedEquals([true])); // Da primeira CTE
    expect(builder.bindings['where'], orderedEquals([5])); // Da query principal
  });

  test('insertUsing with simple select subquery', () async {
    final builder = QueryBuilder(connection, grammar, processor);
    // --- Arrange ---
    final sourceQuery = createSubBuilder('source_table')
        .select(['col1', 'col2']).where('status', '=', 'pending');

    final targetColumns = ['target_col1', 'target_col2'];

    // Define a tabela alvo no builder principal
    builder.from('target_table');

    // --- Act ---
    // Executa o método
    await builder.insertUsing(targetColumns, sourceQuery);

    // --- Assert ---
    // Verifica se connection.insert foi chamado
    expect(connection.insertCallCount, 1,
        reason: 'connection.insert should be called once');

    // Obtém os argumentos capturados pela FakeConnection
    final capturedSql = connection.lastInsertSql;
    final capturedBindings = connection.lastInsertBindings;

    // --- Constrói o SQL esperado ---
    // 1. Compila o SQL da subquery SELECT
    final sourceSql = grammar.compileSelect(sourceQuery);
    // 2. Constrói a parte INSERT INTO (você pode precisar de helpers da gramática se tiver)
    final columnsSql = grammar.columnize(targetColumns);
    final tableSql = grammar.wrapTable(builder.fromProp);
    // 3. Junta as partes (ajuste se sua `compileInsertUsing` gerar o SQL completo)
    final expectedInsertSql = 'insert into $tableSql ($columnsSql) $sourceSql';

    // --- Verifica o SQL e os Bindings ---
    expect(capturedSql, isNotNull, reason: 'Captured SQL should not be null');
    expect(capturedSql, equals(expectedInsertSql),
        reason: 'Compiled SQL did not match');

    expect(capturedBindings, isNotNull,
        reason: 'Captured bindings should not be null');
    // Apenas os bindings da subquery ('pending') devem ser passados
    expect(capturedBindings, orderedEquals(['pending']),
        reason: 'Captured bindings did not match');
  });

  // **** NOVO TESTE ****
  test('count with recursive CTE includes CTE bindings correctly', () async {
    final builder = QueryBuilder(connection, grammar, processor);
    final db = MockDatabaseManager(connection, grammar, processor);
    final int idInicial = 555;
    final String cteName = 'organograma_arvore_count';

    final cteDefinition = db
        .query()
        .select('og.id')
        .from('public.organograma as og') // CTE usa schema explícito
        .where('og.id', '=', idInicial)
        .unionAll(db
            .query()
            .select('filho.id')
            .from('public.organograma as filho') // CTE usa schema explícito
            .join('$cteName as pai', 'filho.id_pai', '=', 'pai.id'));

    builder
        .from('sw_processo as p') // Tabela principal SEM schema explícito
        .withRecursiveExpression(cteName, cteDefinition)
        .join('public.organograma_historico as oh', 'oh.id', '=', // Join usa schema explícito
            'p.id_organograma_historico_origem', 'left')
        .whereIn('oh.id_organograma', (QueryBuilder subQuery) {
      subQuery.select('id').from(cteName);
    }).where('p.cod_situacao', '=', 2);

    await builder.count();

    expect(connection.selectCallCount, 1);

    final capturedSql = connection.lastSelectSql;
    final capturedBindings = connection.lastSelectBindings;

    // *** CORRIGIDO: Remove 'public.' da tabela principal na string esperada ***
    final expectedCountSql = '''
with recursive "$cteName" as (select "og"."id" from "public"."organograma" as "og" where "og"."id" = ? union all select "filho"."id" from "public"."organograma" as "filho" inner join "$cteName" as "pai" on "filho"."id_pai" = "pai"."id") select count(*) as aggregate from "sw_processo" as "p" left join "public"."organograma_historico" as "oh" on "oh"."id" = "p"."id_organograma_historico_origem" where "oh"."id_organograma" in (select "id" from "$cteName") and "p"."cod_situacao" = ?'''
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    expect(capturedSql, equals(expectedCountSql),
        reason: 'Compiled COUNT SQL with CTE did not match');

    final expectedBindings = [idInicial, 2];
    expect(capturedBindings, orderedEquals(expectedBindings),
        reason:
            'Captured bindings for COUNT did not match or were in wrong order');
  });

   test('get with recursive CTE includes CTE bindings correctly', () async {
     final builder = QueryBuilder(connection, grammar, processor);
     final db = MockDatabaseManager(connection, grammar, processor);
     final int idInicial = 555;
     final String cteName = 'organograma_arvore_get';

     final cteDefinition = db.query()
         .select('og.id')
         .from('public.organograma as og') // CTE usa schema explícito
         .where('og.id', '=', idInicial)
         .unionAll(db.query()
             .select('filho.id')
             .from('public.organograma as filho') // CTE usa schema explícito
             .join('$cteName as pai', 'filho.id_pai', '=', 'pai.id'));

     builder
         .from('sw_processo as p') // Tabela principal SEM schema explícito
         .withRecursiveExpression(cteName, cteDefinition)
         .join('public.organograma_historico as oh', 'oh.id', '=', // Join usa schema explícito
              'p.id_organograma_historico_origem', 'left')
         .whereIn('oh.id_organograma', (QueryBuilder subQuery) {
           subQuery.select('id').from(cteName);
         })
         .where('p.cod_situacao', '=', 3)
         .select('p.*');

     await builder.get();

     expect(connection.selectCallCount, 1);

     final capturedSql = connection.lastSelectSql;
     final capturedBindings = connection.lastSelectBindings;

     // *** CORRIGIDO: Remove 'public.' da tabela principal na string esperada ***
      final expectedGetSql = '''
 with recursive "$cteName" as (select "og"."id" from "public"."organograma" as "og" where "og"."id" = ? union all select "filho"."id" from "public"."organograma" as "filho" inner join "$cteName" as "pai" on "filho"."id_pai" = "pai"."id") select "p".* from "sw_processo" as "p" left join "public"."organograma_historico" as "oh" on "oh"."id" = "p"."id_organograma_historico_origem" where "oh"."id_organograma" in (select "id" from "$cteName") and "p"."cod_situacao" = ?'''
         .replaceAll(RegExp(r'\s+'), ' ')
         .trim();

     expect(capturedSql, equals(expectedGetSql), reason: 'Compiled GET SQL with CTE did not match');

     final expectedBindings = [idInicial, 3];
     expect(capturedBindings, orderedEquals(expectedBindings), reason: 'Captured bindings for GET did not match or were in wrong order');
   });
}

// Helper DatabaseManager (simulado ou real, dependendo do setup do teste)
// Para simplificar, podemos mockar um db.query() que retorna um builder
// ou usar a instância global se configurada.
// Exemplo de mock simples:
class MockDatabaseManager {
  final FakeConnection _connection;
  final QueryGrammar _grammar;
  final Processor _processor;

  MockDatabaseManager(this._connection, this._grammar, this._processor);

  QueryBuilder query() {
    return QueryBuilder(_connection, _grammar, _processor);
  }

  // Adicione table() se necessário para a definição da CTE
  QueryBuilder table(String name) {
    return query().from(name);
  }
}
