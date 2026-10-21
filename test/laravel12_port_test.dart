// Unit tests (no database) for the query-builder features ported from
// Laravel 12: when/unless/tap, whereAny/All/None/Not, whereLike, orderBy
// subqueries / reorder, select/addSelect/from with subqueries, join subs,
// having variants, whereIntegerInRaw, incrementEach, toRawSql, lazyById /
// chunkById paging and sole/firstOrFail.

import 'dart:typed_data';

import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/query/grammars/query_mysql_grammar.dart';
import 'package:eloquent/src/query/processors/mysql_processor.dart';
import 'package:eloquent/src/query/processors/postgres_processor.dart';
import 'package:test/test.dart';

import 'helper.dart';

void main() {
  late FakeConnection conn;
  setUp(() => conn = FakeConnection());

  QueryBuilder pg([String table = 't']) =>
      QueryBuilder(conn, QueryPostgresGrammar(), PostgresProcessor())
          .from(table);
  QueryBuilder my([String table = 't']) =>
      QueryBuilder(conn, QueryMySqlGrammar(), MySqlProcessor()).from(table);

  group('when / unless / tap', () {
    test('truthiness and the value argument', () {
      expect(
          pg().when('', (q) => q.where('a', 1)).toSql(), 'select * from "t"');
      expect(pg().when(<int>[], (q) => q.where('a', 1)).toSql(),
          'select * from "t"');
      final q = pg().when('ana', (QueryBuilder q, String nome) {
        q.where('nome', nome);
      });
      expect(q.toSql(), 'select * from "t" where "nome" = ?');
      expect(q.getBindings(), ['ana']);
    });

    test('otherwise, unless and tap', () {
      expect(
          pg()
              .when(null, (q) => q.where('a', 1), (q) => q.where('b', 2))
              .toSql(),
          'select * from "t" where "b" = ?');
      expect(pg().unless(false, (q) => q.where('c', 3)).toSql(),
          'select * from "t" where "c" = ?');
      void ativos(QueryBuilder q) => q.where('ativo', true);
      expect(pg().tap(ativos).toSql(), 'select * from "t" where "ativo" = ?');
    });
  });

  group('whereAny / whereAll / whereNone / whereNot', () {
    test('groups the columns in parentheses', () {
      final q = pg()
          .where('status', 'ativo')
          .whereAny(['nome', 'email'], 'like', '%ana%');
      expect(q.toSql(),
          'select * from "t" where "status" = ? and ("nome" like ? or "email" like ?)');
      expect(q.getBindings(), ['ativo', '%ana%', '%ana%']);
      expect(pg().whereAll(['a', 'b'], 1).toSql(),
          'select * from "t" where ("a" = ? and "b" = ?)');
      expect(pg().whereNone(['a', 'b'], '>', 1).toSql(),
          'select * from "t" where not ("a" > ? or "b" > ?)');
      expect(pg().where('x', 0).orWhereAny(['a', 'b'], 1).toSql(),
          'select * from "t" where "x" = ? or ("a" = ? or "b" = ?)');
    });

    test('whereNot negates a clause or a group', () {
      expect(
          pg().whereNot('a', 1).toSql(), 'select * from "t" where not "a" = ?');
      expect(
          pg()
              .where('x', 0)
              .whereNot((QueryBuilder q) => q.where('a', 1).orWhere('b', 2))
              .toSql(),
          'select * from "t" where "x" = ? and not ("a" = ? or "b" = ?)');
      expect(pg().where('x', 0).orWhereNot('a', 1).toSql(),
          'select * from "t" where "x" = ? or not "a" = ?');
    });
  });

  group('whereLike', () {
    test('PostgreSQL uses ilike on ::text, like when case-sensitive', () {
      expect(pg().whereLike('nome', '%ana%').toSql(),
          'select * from "t" where "nome"::text ilike ?');
      expect(pg().whereLike('nome', '%ana%', caseSensitive: true).toSql(),
          'select * from "t" where "nome"::text like ?');
      expect(
          pg().whereNotLike('nome', 'a%').orWhereLike('email', '%@x').toSql(),
          'select * from "t" where "nome"::text not ilike ? or "email"::text ilike ?');
    });

    test('MySQL uses like / like binary', () {
      expect(my().whereLike('nome', '%ana%').toSql(),
          'select * from `t` where `nome` like ?');
      expect(my().whereLike('nome', '%ana%', caseSensitive: true).toSql(),
          'select * from `t` where `nome` like binary ?');
    });
  });

  group('orderBy', () {
    test('orderByDesc, reorder and invalid directions', () {
      expect(pg().orderByDesc('id').toSql(),
          'select * from "t" order by "id" desc');
      expect(pg().orderBy('a').orderByRaw('b + ?', [1]).reorder('c').toSql(),
          'select * from "t" order by "c" asc');
      expect(pg().orderBy('a').reorder().getBindings(), isEmpty);
      expect(pg().orderBy('a').reorderDesc('b').toSql(),
          'select * from "t" order by "b" desc');
      expect(() => pg().orderBy('a', 'ascending'), throwsArgumentError);
    });

    test('orderBy a subquery binds after the wheres', () {
      final q = pg('users').where('ativo', true).orderByDesc((QueryBuilder s) =>
          s
              .from('logins')
              .selectRaw('max(created_at)')
              .whereColumn('logins.user_id', 'users.id')
              .where('ok', true));
      expect(q.toSql(),
          'select * from "users" where "ativo" = ? order by (select max(created_at) from "logins" where "logins"."user_id" = "users"."id" and "ok" = ?) desc');
      expect(q.getBindings(), [true, true]);
    });
  });

  group('select / from with subqueries', () {
    test('addSelect {alias: subquery} keeps table.*', () {
      final q = pg('users').addSelect({
        'ultimo': (QueryBuilder s) => s
            .from('logins')
            .selectRaw('max(created_at)')
            .whereColumn('logins.user_id', 'users.id'),
      });
      expect(q.toSql(),
          'select "users".*, (select max(created_at) from "logins" where "logins"."user_id" = "users"."id") as "ultimo" from "users"');
    });

    test('select map with aliases and subqueries resets select bindings', () {
      final q = pg('users').selectRaw('? as x', [1]).select(
          {'n': 'nome', 'c': pg('logins').selectRaw('count(*)')});
      expect(q.toSql(),
          'select "nome" as "n", (select count(*) from "logins") as "c" from "users"');
      expect(q.getBindings(), isEmpty);
    });

    test('fromSub / from(subquery, as) / join subs', () {
      final sub = pg('vendas').select(['cliente_id']).where('ano', 2026);
      expect(pg().fromSub(sub, 'v').toSql(),
          'select * from (select "cliente_id" from "vendas" where "ano" = ?) as "v"');
      expect(pg().from((QueryBuilder q) => q.from('a'), 'x').toSql(),
          'select * from (select * from "a") as "x"');
      expect(() => pg().from((QueryBuilder q) => q.from('a')),
          throwsArgumentError);
      final j = pg('clientes')
          .leftJoinSub(sub, 'v', 'v.cliente_id', '=', 'clientes.id')
          .where('ativo', true);
      expect(j.toSql(),
          'select * from "clientes" left join (select "cliente_id" from "vendas" where "ano" = ?) as "v" on "v"."cliente_id" = "clientes"."id" where "ativo" = ?');
      expect(j.getBindings(), [2026, true]);
      expect(pg('a').crossJoinSub(pg('b'), 'bb').toSql(),
          'select * from "a" cross join (select * from "b") as "bb"');
    });
  });

  group('having', () {
    test('two arguments, between, null and nested', () {
      final q = pg()
          .groupBy('status')
          .having('status', 'ok')
          .havingBetween('total', [1, 10])
          .orHavingNull('x')
          .having((QueryBuilder h) => h.having('a', '>', 1).orHaving('b', 2));
      expect(q.toSql(),
          'select * from "t" group by "status" having "status" = ? and "total" between ? and ? or "x" is null and ("a" > ? or "b" = ?)');
      expect(q.getBindings(), ['ok', 1, 10, 1, 2]);
      expect(pg().groupBy('a').havingNotBetween('n', [1, 2]).toSql(),
          'select * from "t" group by "a" having "n" not between ? and ?');
      expect(pg().groupBy('a').havingNotNull(['a', 'b']).toSql(),
          'select * from "t" group by "a" having "a" is not null and "b" is not null');
    });
  });

  group('whereIntegerInRaw / incrementEach', () {
    test('inlines integers and rejects other values', () {
      final q = pg().whereIntegerInRaw('id', [1, '2', 3]);
      expect(q.toSql(), 'select * from "t" where "id" in (1, 2, 3)');
      expect(q.getBindings(), isEmpty);
      expect(pg().whereIntegerNotInRaw('id', []).toSql(),
          'select * from "t" where 1 = 1');
      expect(() => pg().whereIntegerInRaw('id', ['1; drop table t']),
          throwsArgumentError);
    });

    test('incrementEach / decrementEach', () async {
      await pg().where('id', 1).incrementEach({'a': 1, 'b': 2.5}, {'c': 'x'});
      expect(conn.lastUpdateSql,
          'update "t" set "a" = "a" + 1, "b" = "b" + 2.5, "c" = ? where "id" = ?');
      expect(conn.lastUpdateBindings, ['x', 1]);
      await pg().decrementEach({'a': 3});
      expect(conn.lastUpdateSql, 'update "t" set "a" = "a" - 3');
    });
  });

  group('toRawSql', () {
    test('PostgreSQL literals', () {
      final q = pg()
          .where('nome', "D'Ávila")
          .where('ativo', true)
          .whereNull('x')
          .where('n', '>', 1.5)
          .whereRaw("obs <> '?'")
          .where('b', Uint8List.fromList([0, 255]))
          .where('tags', '@>', ['a', 'b"c']);
      expect(q.toRawSql(),
          "select * from \"t\" where \"nome\" = 'D''Ávila' and \"ativo\" = true and \"x\" is null and \"n\" > 1.5 and obs <> '?' and \"b\" = '\\x00ff'::bytea and \"tags\" @> '{\"a\",\"b\\\"c\"}'");
    });

    test('MySQL literals', () {
      expect(my().where('p', r"C:\x'y").where('ok', false).toRawSql(),
          r"select * from `t` where `p` = 'C:\\x''y' and `ok` = 0");
    });
  });

  group('sole / firstOrFail / exists variants', () {
    test('sole', () async {
      conn.mockSelectResult = [];
      await expectLater(pg().sole(), throwsA(isA<RecordsNotFoundException>()));
      conn.mockSelectResult = [
        {'id': 1},
        {'id': 2}
      ];
      await expectLater(
          pg().sole(), throwsA(isA<MultipleRecordsFoundException>()));
      expect(conn.lastSelectSql, 'select * from "t" limit 2');
      conn.mockSelectResult = [
        {'id': 7}
      ];
      expect(await pg().sole(), {'id': 7});
      expect(await pg().soleValue('id'), 7);
    });

    test('firstOrFail / findOr / doesntExist', () async {
      conn.mockSelectResult = [];
      await expectLater(
          pg().firstOrFail(), throwsA(isA<RecordsNotFoundException>()));
      expect(await pg().findOr(5, () => 'nada'), 'nada');
      conn.mockSelectResult = [
        {'exists': false}
      ];
      expect(await pg().doesntExist(), isTrue);
      expect(await pg().existsOr(() => 'nao'), 'nao');
    });
  });

  group('chunkById / lazyById paging', () {
    test('every page is a clone: the builder keeps no paging state', () async {
      conn.mockSelectResult = [
        {'id': 1},
        {'id': 2}
      ];
      final q = pg().where('ativo', true);
      final seen = <dynamic>[];
      await q.chunkById(2, (rows) {
        seen.addAll(rows.map((r) => r['id']));
        // Stop after the first page (the fake returns the same rows forever).
        return false;
      });
      expect(seen, [1, 2]);
      expect(conn.lastSelectSql,
          'select * from "t" where "ativo" = ? order by "id" asc limit 2');
      expect(q.toSql(), 'select * from "t" where "ativo" = ?');

      final rows = await pg().lazyByIdDesc(5).toList();
      expect(rows, hasLength(2)); // fewer than chunkSize: a single page
      expect(
          conn.lastSelectSql, 'select * from "t" order by "id" desc limit 5');
    });

    test('a missing id column fails clearly', () async {
      conn.mockSelectResult = [
        {'nome': 'a'},
        {'nome': 'b'}
      ];
      await expectLater(pg().chunkById(2, (rows) => true), throwsStateError);
    });
  });
}
