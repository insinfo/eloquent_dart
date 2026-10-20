import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

import 'helper.dart';

void main() {
  final connection = FakeConnection();
  QueryBuilder base() =>
      QueryBuilder(connection, QueryPostgresGrammar(), Processor());
  QueryBuilder2 pg([String? table]) => QueryBuilder2.using(base, table);

  test('union: order and limit apply to the combined result', () {
    final q = pg('ativos')
        .select(['id', 'nome'])
        .where('tipo', 'a')
        .unionAll(pg('arquivados').select(['id', 'nome']).where('tipo', 'b'))
        .orderByRaw('nome <-> ?', ['ana'])
        .limit(10);
    expect(
        q.toSql(),
        'select "id", "nome" from "ativos" where "tipo" = ? union all '
        'select "id", "nome" from "arquivados" where "tipo" = ? '
        'order by nome <-> ? limit 10');
    // The order binding comes after the union part's bindings.
    expect(q.getBindings(), ['a', 'b', 'ana']);
  });

  test('a union part with its own order/limit is wrapped', () {
    final q = pg('a')
        .select(['id'])
        .union(pg('b').select(['id']).orderByDescending('id').limit(3));
    expect(
        q.toSql(),
        'select "id" from "a" union select * from (select "id" from "b" '
        'order by "id" desc limit 3) as "union_part"');
  });

  test('QueryBuilder: union orderByRaw bindings come last', () {
    final q = base()
        .from('a')
        .where('x', 1)
        .union(base().from('b').where('y', 2))
        .orderByRaw('z = ?', [3]);
    expect(q.getBindings(), [1, 2, 3]);
    final copy = q.clone()..reorder();
    expect(copy.getBindings(), [1, 2]);
  });

  test('CTE and recursive CTE', () {
    final q = pg('pagos')
        .withExpression('pagos', pg('pedidos').where('pago', true),
            materialized: true)
        .where('total', 10, operator: ComparisonOperator.greaterThan);
    expect(
        q.toSql(),
        'with "pagos" as MATERIALIZED (select * from "pedidos" where "pago" = ?) '
        'select * from "pagos" where "total" > ?');
    expect(q.getBindings(), [true, 10]);

    final tree = pg('arvore').withRecursiveExpression(
        'arvore',
        pg('setor')
            .select(['id', 'pai_id'])
            .where('id', 1)
            .unionAll(pg('setor as s')
                .select(['s.id', 's.pai_id'])
                .join('arvore as a', 'a.id', 's.pai_id')),
        columns: ['id', 'pai_id']);
    expect(
        tree.toSql(),
        'with recursive "arvore" ("id", "pai_id") as (select "id", "pai_id" '
        'from "setor" where "id" = ? union all select "s"."id", "s"."pai_id" '
        'from "setor" as "s" inner join "arvore" as "a" on "a"."id" = '
        '"s"."pai_id") select * from "arvore"');
    expect(tree.getBindings(), [1]);
  });

  test('parts and CTEs are copied when added', () {
    final part = pg('b').where('y', 1);
    final q = pg('a').union(part);
    part.where('z', 2);
    expect(q.getBindings(), [1]);
  });

  test('PageResult', () {
    const page = PageResult(
        items: [{'id': 1}, {'id': 2}], total: 12, perPage: 5, currentPage: 3);
    expect(page.lastPage, 3);
    expect(page.hasMorePages, isFalse);
    expect(page.from, 11);
    expect(page.to, 12);
    expect(page.toMap()['last_page'], 3);
    const empty =
        PageResult(items: [], total: 0, perPage: 5, currentPage: 1);
    expect(empty.lastPage, 1);
    expect(empty.from, isNull);
  });
}
