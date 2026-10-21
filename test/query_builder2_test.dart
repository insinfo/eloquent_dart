import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/query/grammars/query_mysql_grammar.dart';
import 'package:test/test.dart';

import 'helper.dart';

void main() {
  final connection = FakeConnection();
  QueryBuilder2 pg([String table = 'usuarios']) => QueryBuilder2.using(
      () => QueryBuilder(connection, QueryPostgresGrammar(), Processor()),
      table);
  QueryBuilder2 mysql([String table = 'usuarios']) => QueryBuilder2.using(
      () => QueryBuilder(connection, QueryMySqlGrammar(), Processor()), table);

  group('where', () {
    test('the documented example', () {
      final q = pg()
          .select(['id', 'nome', 'idade'])
          .where('ativo', true)
          .where('idade', 18, operator: ComparisonOperator.greaterThanOrEqualTo)
          .whereIn('perfil', ['administrador', 'operador'])
          .whereNull('excluido_em')
          .whereGroup((w) =>
              w.where('cidade', 'Rio das Ostras').orWhere('cidade', 'Macaé'))
          .orderBy('nome')
          .limit(50);
      expect(
          q.toSql(),
          'select "id", "nome", "idade" from "usuarios" where "ativo" = ? '
          'and "idade" >= ? and "perfil" in (?, ?) and "excluido_em" is null '
          'and ("cidade" = ? or "cidade" = ?) order by "nome" asc limit 50');
      expect(q.getBindings(), [
        true, 18, 'administrador', 'operador', 'Rio das Ostras', 'Macaé' //
      ]);
    });

    test('the value is always a value', () {
      // QueryBuilder.whereFlex('simbolo', '=') read "=" as the operator.
      final q = pg('ativos').where('simbolo', '=');
      expect(q.toSql(), 'select * from "ativos" where "simbolo" = ?');
      expect(q.getBindings(), ['=']);

      final column = pg().where('nome', 'apelido');
      expect(column.toSql(), endsWith('where "nome" = ?'));
      expect(pg().whereColumn('nome', 'apelido').toSql(),
          endsWith('where "nome" = "apelido"'));
    });

    test('descriptive methods', () {
      final q = pg()
          .whereEqualTo('a', 1)
          .whereNotEqualTo('b', 2)
          .whereGreaterThan('c', 3)
          .orWhereGreaterThanOrEqualTo('d', 4)
          .whereLessThan('e', 5)
          .orWhereLessThanOrEqualTo('f', 6);
      expect(
          q.toSql(),
          'select * from "usuarios" where "a" = ? and "b" <> ? and "c" > ? '
          'or "d" >= ? and "e" < ? or "f" <= ?');
      expect(q.getBindings(), [1, 2, 3, 4, 5, 6]);
    });

    test('null', () {
      expect(pg().where('x', null).toSql(), endsWith('where "x" is null'));
      expect(
          pg()
              .where('x', null, operator: ComparisonOperator.notEqualTo)
              .toSql(),
          endsWith('where "x" is not null'));
      expect(pg().whereNotEqualTo('x', null).orWhereNull('y').toSql(),
          endsWith('where "x" is not null or "y" is null'));
      expect(
          () => pg().where('x', null, operator: ComparisonOperator.greaterThan),
          throwsArgumentError);
    });

    test('subqueries, callbacks and raw SQL are not values', () {
      expect(() => pg().where('x', pg('y')), throwsArgumentError);
      expect(() => pg().where('x', () => 1), throwsArgumentError);
      expect(
          () => pg().where('x', QueryExpression('now()')), throwsArgumentError);
      expect(() => pg().where(' ', 1), throwsArgumentError);
    });

    test('a List value is one binding', () {
      final q = pg().whereSqlOperator('tags', '@>', ['a', 'b']);
      expect(q.toSql(), endsWith('where "tags" @> ?'));
      expect(q.getBindings(), [
        ['a', 'b']
      ]);
    });

    test('in, between, like', () {
      expect(pg().whereIn('id', <int>[]).toSql(), endsWith('where 0 = 1'));
      expect(pg().whereNotIn('id', <int>[]).toSql(), endsWith('where 1 = 1'));
      expect(pg().whereIn('id', {1, 2}).getBindings(), [1, 2]);
      expect(() => pg().whereIn('id', [1, null]), throwsArgumentError);

      final between =
          pg().whereBetween('idade', 18, 65).orWhereNotBetween('n', 1, 2);
      expect(between.toSql(),
          endsWith('where "idade" between ? and ? or "n" not between ? and ?'));
      expect(between.getBindings(), [18, 65, 1, 2]);

      expect(pg().whereLike('nome', 'isa%').toSql(),
          endsWith('where "nome"::text ilike ?'));
      expect(pg().whereLike('nome', 'Isa%', caseSensitive: true).toSql(),
          endsWith('where "nome"::text like ?'));
      expect(mysql().whereNotLike('nome', 'isa%').toSql(),
          endsWith('where `nome` not like ?'));
    });

    test('groups', () {
      final q = pg()
          .where('ativo', true)
          .whereGroup((w) => w.where('perfil', 'administrador').orWhereGroup(
              (inner) => inner
                  .where('perfil', 'supervisor')
                  .whereNotNull('assinado_em')))
          .orWhereNotGroup((w) => w.where('bloqueado', true))
          .whereGroup((_) {});
      expect(
          q.toSql(),
          'select * from "usuarios" where "ativo" = ? and ("perfil" = ? or '
          '("perfil" = ? and "assinado_em" is not null)) or not ("bloqueado" = ?)');
      expect(q.getBindings(), [true, 'administrador', 'supervisor', true]);
    });

    test('exists and in subquery; subqueries are copied when added', () {
      final pedidos = pg('pedidos').select(['cliente_id']).where('pago', true);
      final q = pg('clientes')
          .whereExists(
              pg('pedidos').whereColumn('pedidos.cliente_id', 'clientes.id'))
          .whereNotInSubquery('id', pedidos);
      pedidos.where('cancelado', false); // later change: not in q
      expect(
          q.toSql(),
          'select * from "clientes" where exists (select * from "pedidos" '
          'where "pedidos"."cliente_id" = "clientes"."id") and "id" not in '
          '(select "cliente_id" from "pedidos" where "pago" = ?)');
      expect(q.getBindings(), [true]);
    });

    test('whereSqlOperator accepts predicate operators of the dialect', () {
      expect(pg().whereSqlOperator('email', '~*', '@gmail').toSql(),
          endsWith('where "email" ~* ?'));
      expect(pg().whereSqlOperator('nome', 'NOT  ILIKE', 'a%').toSql(),
          endsWith('where "nome" not ilike ?'));
      expect(pg().whereSqlOperator('a', 'is distinct from', null).getBindings(),
          [null]);
      expect(mysql().whereSqlOperator('a', '<=>', null).toSql(),
          endsWith('where `a` <=> ?'));

      // Arithmetic is not a condition; "?" is the placeholder; regex
      // operators are PostgreSQL only.
      expect(() => pg().whereSqlOperator('a', '-', 1).toSql(),
          throwsArgumentError);
      expect(
          () => pg().whereSqlOperator('dados', '?', 'k').toSql(),
          throwsA(isA<ArgumentError>()
              .having((e) => e.message, 'message', contains('jsonb_exists'))));
      expect(() => mysql().whereSqlOperator('a', '~', 'x').toSql(),
          throwsArgumentError);
    });

    test('whereRaw', () {
      final q = pg()
          .whereRaw('jsonb_exists(dados, ?)', ['telefone']).orWhereRaw('1 = 1');
      expect(q.toSql(), endsWith('where jsonb_exists(dados, ?) or 1 = 1'));
      expect(q.getBindings(), ['telefone']);
    });
  });

  group('select, joins, grouping and paging', () {
    test('select items and from subquery', () {
      final q = pg('pedidos as p')
          .select(['p.id'])
          .addSelect(['p.total as valor'])
          .selectRaw('coalesce(p.desconto, ?) as desconto', [0])
          .selectSubquery(
              pg('itens')
                  .selectRaw('count(*)')
                  .whereColumn('itens.pedido_id', 'p.id'),
              'qtd')
          .distinct();
      expect(
          q.toSql(),
          'select distinct "p"."id", "p"."total" as "valor", '
          'coalesce(p.desconto, ?) as desconto, (select count(*) from "itens" '
          'where "itens"."pedido_id" = "p"."id") as "qtd" from "pedidos" as "p"');
      expect(q.getBindings(), [0]);

      final sub = pg()
          .fromSubquery(pg('vendas').where('ano', 2026), 'v')
          .where('v.total', 10, operator: ComparisonOperator.greaterThan);
      expect(sub.toSql(),
          'select * from (select * from "vendas" where "ano" = ?) as "v" where "v"."total" > ?');
      expect(sub.getBindings(), [2026, 10]);
    });

    test('joins: join bindings come before where bindings', () {
      final q = pg('pedidos')
          .where('pedidos.pago', true)
          .join('clientes', 'clientes.id', 'pedidos.cliente_id')
          .leftJoinOn(
              'enderecos',
              (j) => j
                  .on('enderecos.cliente_id', 'clientes.id')
                  .where('enderecos.tipo', 'entrega')
                  .whereNull('enderecos.excluido_em'))
          .crossJoin('parametros');
      expect(
          q.toSql(),
          'select * from "pedidos" inner join "clientes" on "clientes"."id" = '
          '"pedidos"."cliente_id" left join "enderecos" on '
          '"enderecos"."cliente_id" = "clientes"."id" and "enderecos"."tipo" = ? '
          'and "enderecos"."excluido_em" is null cross join "parametros" '
          'where "pedidos"."pago" = ?');
      expect(q.getBindings(), ['entrega', true]);
      expect(() => pg().joinOn('x', (_) {}), throwsArgumentError);
    });

    test('group, having, order, page, lock', () {
      final q = pg('vendas')
          .select(['vendedor'])
          .selectRaw('sum(total) as soma')
          .groupBy(['vendedor'])
          .havingRaw('sum(total) > ?', [1000])
          .orHavingRaw('count(*) > ?', [10])
          .having('vendedor', 'teste', operator: ComparisonOperator.notEqualTo)
          .orderByDescending('soma')
          .orderBy('vendedor')
          .forPage(3, 20)
          .lockForUpdate(skipLocked: true);
      expect(
          q.toSql(),
          'select "vendedor", sum(total) as soma from "vendas" group by '
          '"vendedor" having sum(total) > ? or count(*) > ? and "vendedor" <> ? '
          'order by "soma" desc, "vendedor" asc limit 20 offset 40 '
          'for update skip locked');
      expect(q.getBindings(), [1000, 10, 'teste']);
      expect(pg().orderBy('a').reorder().toSql(), 'select * from "usuarios"');
      expect(() => pg().forPage(0, 10), throwsArgumentError);
    });
  });

  group('conditional and clone', () {
    test('when and whenNotNull', () {
      String? situacao = 'A';
      int? ano;
      final q = pg()
          .whenNotNull(situacao, (q, s) => q.where('situacao', s))
          .whenNotNull(ano, (q, a) => q.where('ano', a))
          .when(false, (q) => q.where('x', 1), (q) => q.whereNull('x'));
      expect(q.toSql(), endsWith('where "situacao" = ? and "x" is null'));
      expect(q.getBindings(), ['A']);
    });

    test('clone is independent', () {
      final base = pg().where('ativo', true);
      final copy = base.clone().where('perfil', 'admin').orderBy('nome');
      expect(base.toSql(), 'select * from "usuarios" where "ativo" = ?');
      expect(copy.toSql(),
          'select * from "usuarios" where "ativo" = ? and "perfil" = ? order by "nome" asc');
    });

    test('toQueryBuilder gives an equivalent QueryBuilder', () {
      final q = pg().where('a', 1).toQueryBuilder();
      expect(q, isA<QueryBuilder>());
      expect(q.toSql(), 'select * from "usuarios" where "a" = ?');
    });

    test('MySQL dialect', () {
      final q =
          mysql().where('a', 1).orderByDescending('b').limit(5).sharedLock();
      expect(q.toSql(),
          'select * from `usuarios` where `a` = ? order by `b` desc limit 5 lock in share mode');
    });
  });
}
