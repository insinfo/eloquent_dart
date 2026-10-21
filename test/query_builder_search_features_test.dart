// Unit tests (no database) for whereSearch / whereAnyLike / unaccent,
// orderByInput, whereInTuple / whereRowValues, whereAnyArray, between columns,
// explain, afterQuery, cursorPaginate and paginateWithWindowCount, in
// QueryBuilder and QueryBuilder2.

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
  QueryBuilder2 pg2([String table = 't']) => QueryBuilder2.using(
      () => QueryBuilder(conn, QueryPostgresGrammar(), PostgresProcessor()),
      table);
  QueryBuilder2 my2([String table = 't']) => QueryBuilder2.using(
      () => QueryBuilder(conn, QueryMySqlGrammar(), MySqlProcessor()), table);

  group('escapeLike / likePattern', () {
    test('escapes the wildcards and the escape character', () {
      expect(QueryBuilder.escapeLike(r'50%_a\b'), r'50\%\_a\\b');
      expect(QueryBuilder.likePattern('ana'), '%ana%');
      expect(QueryBuilder.likePattern('ana', SearchMatch.startsWith), 'ana%');
      expect(QueryBuilder.likePattern('ana', SearchMatch.endsWith), '%ana');
      expect(QueryBuilder.likePattern('a%', SearchMatch.exact), r'a\%');
      expect(QueryBuilder.likePattern(' maria   da_x ', SearchMatch.wordsInOrder),
          r'%maria%da\_x%');
    });
  });

  group('whereSearch', () {
    test('any column, escaped term, unaccent on PostgreSQL', () {
      final q = pg().where('ativo', true).whereSearch(
          ['c.nom_cgm', 'c.cpf'], ' José 10% ',
          unaccent: true);
      expect(
          q.toSql(),
          'select * from "t" where "ativo" = ? and '
          '(unaccent("c"."nom_cgm"::text) ilike unaccent(?) or '
          'unaccent("c"."cpf"::text) ilike unaccent(?))');
      expect(q.getBindings(), [true, r'%José 10\%%', r'%José 10\%%']);
    });

    test('null or blank term adds nothing', () {
      expect(pg().whereSearch(['a'], null).toSql(), 'select * from "t"');
      expect(pg().whereSearch(['a'], '   ').toSql(), 'select * from "t"');
      expect(pg2().whereSearch(['a'], '').toSql(), 'select * from "t"');
    });

    test('everyWord requires each word in some column', () {
      final q = pg().whereSearch(['nome', 'email'], 'ana silva',
          everyWord: true, match: SearchMatch.startsWith);
      expect(
          q.toSql(),
          'select * from "t" where (("nome"::text ilike ? or '
          '"email"::text ilike ?) and ("nome"::text ilike ? or '
          '"email"::text ilike ?))');
      expect(q.getBindings(), ['ana%', 'ana%', 'silva%', 'silva%']);
    });

    test('case sensitive, raw expression column, orWhereSearch', () {
      final q = pg()
          .where('a', 1)
          .orWhereSearch([QueryExpression('coalesce(x, y)')], 'Ab',
              caseSensitive: true);
      expect(q.toSql(),
          'select * from "t" where "a" = ? or (coalesce(x, y)::text like ?)');
    });

    test('MySQL ignores unaccent (the collation decides)', () {
      final q = my().whereSearch(['nome'], 'jose', unaccent: true);
      expect(q.toSql(), 'select * from `t` where (`nome` like ?)');
    });

    test('rejects empty or invalid columns', () {
      expect(() => pg().whereSearch([], 'a'), throwsArgumentError);
      expect(() => pg().whereSearch([' '], 'a'), throwsArgumentError);
      expect(() => pg().whereSearch([1], 'a'), throwsArgumentError);
    });

    test('whereAnyLike keeps the pattern; whereLike unaccent', () {
      final q = pg().whereAnyLike(['a', 'b'], 'x_%', unaccent: true);
      expect(
          q.toSql(),
          'select * from "t" where (unaccent("a"::text) ilike unaccent(?) or '
          'unaccent("b"::text) ilike unaccent(?))');
      expect(q.getBindings(), ['x_%', 'x_%']);
      expect(pg().whereNotLike('a', 'x', unaccent: true).toSql(),
          'select * from "t" where unaccent("a"::text) not ilike unaccent(?)');
    });

    test('lower: lower() on both sides with like', () {
      final q = pg().whereSearch(['c.nom_cgm'], 'Ana',
          lower: true, match: SearchMatch.startsWith);
      expect(q.toSql(),
          'select * from "t" where (lower("c"."nom_cgm"::text) like lower(?))');
      expect(q.getBindings(), ['Ana%']);
      expect(
          pg().whereSearch(['nome'], 'jose', lower: true, unaccent: true).toSql(),
          'select * from "t" where (lower(unaccent("nome"::text)) like '
          'lower(unaccent(?)))');
      expect(pg().whereNotLike('a', 'x', lower: true).toSql(),
          'select * from "t" where lower("a"::text) not like lower(?)');
      expect(my().whereSearch(['nome'], 'ana', lower: true).toSql(),
          'select * from `t` where (lower(`nome`) like lower(?))');
      expect(my().whereNotLike('nome', 'a%', lower: true).toSql(),
          'select * from `t` where lower(`nome`) not like lower(?)');
      expect(pg2().whereSearch(['nome'], 'ana', lower: true).toSql(),
          'select * from "t" where (lower("nome"::text) like lower(?))');
      expect(pg2().whereAnyLike(['a', 'b'], 'x%', lower: true).toSql(),
          'select * from "t" where (lower("a"::text) like lower(?) or '
          'lower("b"::text) like lower(?))');
      expect(() => pg().whereLike('a', 'x', lower: true, caseSensitive: true),
          throwsArgumentError);
      expect(() => pg2().whereLike('a', 'x', lower: true, caseSensitive: true),
          throwsArgumentError);
    });

    test('a custom unaccent function', () {
      final grammar = QueryPostgresGrammar()..unaccentFunction = 'public.f_unaccent';
      final q = QueryBuilder(conn, grammar, PostgresProcessor())
          .from('t')
          .whereSearch(['a'], 'b', unaccent: true);
      expect(q.toSql(),
          'select * from "t" where (public.f_unaccent("a"::text) ilike public.f_unaccent(?))');
      expect(() => grammar.unaccentFunction = 'x); drop table t; --',
          throwsArgumentError);
    });

    test('QueryBuilder2', () {
      final q = pg2().whereSearch(['nome', 'cpf'], 'ana', unaccent: true);
      expect(
          q.toSql(),
          'select * from "t" where (unaccent("nome"::text) ilike unaccent(?) '
          'or unaccent("cpf"::text) ilike unaccent(?))');
      expect(q.getBindings(), ['%ana%', '%ana%']);
      final words = pg2().whereSearch(['n'], 'a b', everyWord: true);
      expect(words.toSql(),
          'select * from "t" where (("n"::text ilike ?) and ("n"::text ilike ?))');
      expect(pg2().whereAnyLike(['a', 'b'], 'x%').toSql(),
          'select * from "t" where ("a"::text ilike ? or "b"::text ilike ?)');
    });
  });

  group('orderByInput', () {
    final allowed = <String, Object>{
      'nome': 'c.nom_cgm',
      'numero': ['p.ano_exercicio', 'p.cod_processo'],
      'idade': QueryExpression('age(c.dt_nascimento)'),
    };

    test('a known field, client direction', () {
      expect(pg().orderByInput('nome', 'DESC', allowed: allowed).toSql(),
          'select * from "t" order by "c"."nom_cgm" desc');
      expect(pg().orderByInput('numero', 'descending', allowed: allowed).toSql(),
          'select * from "t" order by "p"."ano_exercicio" desc, "p"."cod_processo" desc');
      expect(pg().orderByInput('idade', 'x', allowed: allowed).toSql(),
          'select * from "t" order by age(c.dt_nascimento) asc');
    });

    test('unknown, null or blank field uses the fallback', () {
      expect(
          pg()
              .orderByInput('nome; drop table t', 'desc',
                  allowed: allowed, fallback: 'c.numcgm')
              .toSql(),
          'select * from "t" order by "c"."numcgm" asc');
      expect(
          pg()
              .orderByInput(null, null,
                  allowed: allowed,
                  fallback: ['a', 'b'],
                  fallbackDirection: 'desc')
              .toSql(),
          'select * from "t" order by "a" desc, "b" desc');
      expect(pg().orderByInput(' ', 'asc', allowed: allowed).toSql(),
          'select * from "t"');
    });

    test('QueryBuilder2', () {
      expect(pg2().orderByInput('nome', 'desc', allowed: allowed).toSql(),
          'select * from "t" order by "c"."nom_cgm" desc');
      expect(
          pg2()
              .orderByInput('x', 'desc',
                  allowed: {'nome': 'nome'}, fallback: 'id')
              .toSql(),
          'select * from "t" order by "id" asc');
      // QueryBuilder2 takes columns only, never SQL.
      expect(
          () => pg2().orderByInput('idade', 'asc', allowed: allowed),
          throwsArgumentError);
    });
  });

  group('whereInTuple / whereRowValues', () {
    test('composite keys', () {
      final q = pg().whereInTuple([
        'cod_processo',
        'ano_exercicio'
      ], [
        [10, '2024'],
        [11, '2025']
      ]);
      expect(
          q.toSql(),
          'select * from "t" where ("cod_processo", "ano_exercicio") in '
          '((?, ?), (?, ?))');
      expect(q.getBindings(), [10, '2024', 11, '2025']);
      expect(my().whereNotInTuple(['a', 'b'], [
        [1, 2]
      ]).toSql(), 'select * from `t` where (`a`, `b`) not in ((?, ?))');
    });

    test('empty lists and wrong sizes', () {
      expect(pg().whereInTuple(['a', 'b'], []).toSql(),
          'select * from "t" where 0 = 1');
      expect(pg().whereNotInTuple(['a', 'b'], []).toSql(),
          'select * from "t" where 1 = 1');
      expect(
          () => pg().whereInTuple(['a', 'b'], [
                [1]
              ]),
          throwsArgumentError);
    });

    test('row comparison', () {
      final q = pg().whereRowValues(['ano', 'numero'], '>', [2024, 150]);
      expect(q.toSql(), 'select * from "t" where ("ano", "numero") > (?, ?)');
      expect(q.getBindings(), [2024, 150]);
      expect(() => pg().whereRowValues(['a'], 'like', [1]), throwsArgumentError);
      expect(() => pg().whereRowValues(['a', 'b'], '=', [1]),
          throwsArgumentError);
    });

    test('QueryBuilder2', () {
      final q = pg2().where('x', 1).orWhereInTuple(['a', 'b'], [
        [1, 2]
      ]).whereRowValues(['a', 'b'], [3, 4],
          operator: ComparisonOperator.lessThan);
      expect(
          q.toSql(),
          'select * from "t" where "x" = ? or ("a", "b") in ((?, ?)) and '
          '("a", "b") < (?, ?)');
      expect(q.getBindings(), [1, 1, 2, 3, 4]);
    });
  });

  group('whereAnyArray', () {
    test('one array parameter on PostgreSQL', () {
      final q = pg().whereAnyArray('id', {1, 2, 3});
      expect(q.toSql(), 'select * from "t" where "id" = any(?)');
      expect(q.getBindings(), [
        [1, 2, 3]
      ]);
      expect(pg().whereAnyArray('id', ['a'], elementType: 'uuid').toSql(),
          'select * from "t" where "id" = any(?::uuid[])');
      expect(pg().whereNotAnyArray('id', [1]).toSql(),
          'select * from "t" where "id" <> all(?)');
      expect(
          pg()
              .whereAnyArray('v', [1], elementType: 'numeric(10, 2)')
              .toSql(),
          'select * from "t" where "v" = any(?::numeric(10, 2)[])');
    });

    test('empty list, invalid type, MySQL fallback', () {
      final empty = pg().whereAnyArray('id', []);
      expect(empty.toSql(), 'select * from "t" where 0 = 1');
      expect(empty.getBindings(), isEmpty);
      expect(pg().whereNotAnyArray('id', []).toSql(),
          'select * from "t" where 1 = 1');
      expect(() => pg().whereAnyArray('id', [1], elementType: 'int[]); --'),
          throwsArgumentError);
      final q = my().whereAnyArray('id', [1, 2]);
      expect(q.toSql(), 'select * from `t` where `id` in (?, ?)');
      expect(q.getBindings(), [1, 2]);
    });

    test('QueryBuilder2', () {
      expect(pg2().whereAnyArray('id', [1, 2]).toSql(),
          'select * from "t" where "id" = any(?)');
      expect(my2().whereNotAnyArray('id', [1, 2]).toSql(),
          'select * from `t` where `id` not in (?, ?)');
    });
  });

  group('between columns / value between', () {
    test('QueryBuilder', () {
      expect(pg().whereBetweenColumns('valor', ['minimo', 'maximo']).toSql(),
          'select * from "t" where "valor" between "minimo" and "maximo"');
      expect(
          pg().whereNotBetweenColumns('valor', ['a', 'b']).toSql(),
          'select * from "t" where "valor" not between "a" and "b"');
      final q = pg().whereValueBetween(
          DateTime(2026, 1, 2), ['data_inicio', 'data_fim']);
      expect(q.toSql(),
          'select * from "t" where ? between "data_inicio" and "data_fim"');
      expect(q.getBindings(), [DateTime(2026, 1, 2)]);
      expect(pg().orWhereValueNotBetween(5, ['a', 'b']).toSql(),
          'select * from "t" where ? not between "a" and "b"');
      expect(() => pg().whereBetweenColumns('a', ['b']), throwsArgumentError);
    });

    test('QueryBuilder2', () {
      final q = pg2()
          .whereBetweenColumns('v', 'lo', 'hi')
          .whereValueBetween(3, 'lo', 'hi');
      expect(
          q.toSql(),
          'select * from "t" where "v" between "lo" and "hi" and ? between '
          '"lo" and "hi"');
      expect(q.getBindings(), [3]);
    });
  });

  group('QueryBuilder2 parity', () {
    test('whereAny / whereAll / whereNone', () {
      expect(pg2().whereAny(['a', 'b'], 1).toSql(),
          'select * from "t" where ("a" = ? or "b" = ?)');
      expect(
          pg2()
              .whereAll(['a', 'b'], 1,
                  operator: ComparisonOperator.greaterThan)
              .toSql(),
          'select * from "t" where ("a" > ? and "b" > ?)');
      expect(pg2().whereNone(['a', 'b'], 1).toSql(),
          'select * from "t" where not ("a" = ? or "b" = ?)');
    });

    test('dates', () {
      final q = pg2()
          .whereDate('criado', '2026-01-02')
          .whereYear('criado', 2026,
              operator: ComparisonOperator.greaterThanOrEqualTo)
          .whereMonth('criado', 1);
      expect(
          q.toSql(),
          'select * from "t" where "criado"::date = ? and extract(year from '
          '"criado") >= ? and extract(month from "criado") = ?');
      expect(q.getBindings(), ['2026-01-02', 2026, 1]);
    });

    test('JSON, arrays, full text, distinct on', () {
      final q = pg2()
          .distinctOn(['grupo'])
          .whereJsonContains('dados', {'a': 1})
          .whereJsonLength('lista', 2,
              operator: ComparisonOperator.greaterThan)
          .whereArrayContains('tags', ['x'])
          .whereFullText(['titulo'], 'casa', language: 'portuguese')
          .orderBy('grupo');
      expect(
          q.toSql(),
          'select distinct on ("grupo") * from "t" where ("dados")::jsonb @> ? '
          'and jsonb_array_length(("lista")::jsonb) > ? and "tags" @> ? and '
          "(to_tsvector('portuguese', \"titulo\")) @@ "
          "plainto_tsquery('portuguese', ?) order by \"grupo\" asc");
      expect(q.getBindings(), [
        '{"a":1}',
        2,
        ['x'],
        'casa'
      ]);
    });

    test('joinSub and LATERAL', () {
      final ultimo = pg2('andamento as a')
          .select(['a.cod_andamento'])
          .whereColumn('a.cod_processo', 'p.cod_processo')
          .where('a.tipo', 'x')
          .orderByDescending('a.cod_andamento')
          .limit(1);
      final q = pg2('processo as p')
          .joinSub(pg2('x').where('k', 1), 's', 's.id', 'p.id')
          .leftJoinLateral(ultimo, 'ultimo');
      expect(
          q.toSql(),
          'select * from "processo" as "p" inner join (select * from "x" '
          'where "k" = ?) as "s" on "s"."id" = "p"."id" left join LATERAL '
          '(select "a"."cod_andamento" from "andamento" as "a" where '
          '"a"."cod_processo" = "p"."cod_processo" and "a"."tipo" = ? order '
          'by "a"."cod_andamento" desc limit 1) as "ultimo" on TRUE');
      expect(q.getBindings(), [1, 'x']);
    });

    test('latest / oldest / inRandomOrder', () {
      expect(pg2().latest().toSql(),
          'select * from "t" order by "created_at" desc');
      expect(pg2().oldest('id').inRandomOrder().toSql(),
          'select * from "t" order by "id" asc, RANDOM()');
    });
  });

  group('explain, afterQuery, updateFrom', () {
    test('explain runs EXPLAIN with the bindings', () async {
      await pg().where('a', 1).explain();
      expect(conn.lastSelectSql, 'explain select * from "t" where "a" = ?');
      expect(conn.lastSelectBindings, [1]);
      await pg2().where('a', 1).explain(analyze: true);
      expect(conn.lastSelectSql,
          'explain analyze select * from "t" where "a" = ?');
    });

    test('afterQuery transforms the rows of get, not of count', () async {
      conn.mockSelectResult = [
        {'id': 1, 'nome': ' Ana '}
      ];
      final q = pg().afterQuery((rows) {
        for (final row in rows) {
          row['nome'] = (row['nome'] as String).trim();
        }
        return null;
      }).afterQuery((rows) async => [
            ...rows,
            {'id': 2, 'nome': 'extra'}
          ]);
      final rows = await q.get();
      expect(rows, [
        {'id': 1, 'nome': 'Ana'},
        {'id': 2, 'nome': 'extra'}
      ]);
      expect(await q.clone().count(), 10);
      final rows2 = await pg2()
          .afterQuery((rows) => [
                for (final r in rows) {...r, 'x': true}
              ])
          .get();
      expect(rows2.single['x'], isTrue);
    });
  });

  group('cursorPaginate', () {
    test('first page, next cursor, previous cursor', () async {
      conn.mockSelectResult = [
        {'id': 1, 'nome': 'a'},
        {'id': 2, 'nome': 'b'},
        {'id': 3, 'nome': 'c'},
      ];
      final query = pg().orderBy('nome').orderBy('t.id');
      final first = await query.cursorPaginate(perPage: 2);
      expect(conn.lastSelectSql,
          'select * from "t" order by "nome" asc, "t"."id" asc limit 3');
      expect(first.items.length, 2);
      expect(first.previousCursor, isNull);
      expect(first.nextCursor, isNotNull);
      expect(PageCursor.decode(first.nextCursor!).values,
          {'nome': 'b', 't.id': 2});

      conn.mockSelectResult = [
        {'id': 3, 'nome': 'c'},
      ];
      final second = await query.cursorPaginate(
          perPage: 2, cursor: first.nextCursor);
      expect(
          conn.lastSelectSql,
          'select * from "t" where ("nome" > ? or ("nome" = ? and ("t"."id" > ?))) '
          'order by "nome" asc, "t"."id" asc limit 3');
      expect(conn.lastSelectBindings, ['b', 'b', 2]);
      expect(second.nextCursor, isNull);
      expect(second.previousCursor, isNotNull);

      conn.mockSelectResult = [
        {'id': 2, 'nome': 'b'},
        {'id': 1, 'nome': 'a'},
      ];
      final back = await query.cursorPaginate(
          perPage: 2, cursor: second.previousCursor);
      expect(
          conn.lastSelectSql,
          'select * from "t" where ("nome" < ? or ("nome" = ? and ("t"."id" < ?))) '
          'order by "nome" desc, "t"."id" desc limit 3');
      expect(back.items.map((r) => r['id']), [1, 2]);
      expect(back.previousCursor, isNull);
      expect(back.nextCursor, isNotNull);
    });

    test('descending order, DateTime values survive the cursor', () async {
      final when = DateTime.utc(2026, 3, 4, 5, 6, 7, 8, 9);
      final cursor =
          PageCursor({'criado': when, 'id': 7}, pointsToNextItems: true)
              .encode();
      expect(PageCursor.decode(cursor).values['criado'], when);
      conn.mockSelectResult = [];
      await pg().orderByDesc('criado').orderBy('id').cursorPaginate(
          cursor: cursor);
      expect(
          conn.lastSelectSql,
          'select * from "t" where ("criado" < ? or ("criado" = ? and ("id" > ?))) '
          'order by "criado" desc, "id" asc limit 16');
      expect(conn.lastSelectBindings, [when, when, 7]);
    });

    test('errors', () async {
      expect(() => pg().cursorPaginate(), throwsArgumentError);
      expect(() => pg().orderByRaw('random()').cursorPaginate(),
          throwsArgumentError);
      expect(() => pg().orderBy('id').cursorPaginate(cursor: 'lixo'),
          throwsFormatException);
      final other =
          PageCursor({'x': 1}, pointsToNextItems: true).encode();
      expect(() => pg().orderBy('id').cursorPaginate(cursor: other),
          throwsFormatException);
      conn.mockSelectResult = [
        {'nome': 'a'},
        {'nome': 'b'},
      ];
      expect(() => pg().orderBy('id').cursorPaginate(perPage: 1),
          throwsStateError);
    });
  });

  group('paginateWithWindowCount', () {
    test('one query with count(*) over ()', () async {
      conn.mockSelectResult = [
        {'id': 1, 'eloquent_window_total': 42},
        {'id': 2, 'eloquent_window_total': 42},
      ];
      final page = await pg()
          .where('a', 1)
          .orderBy('id')
          .paginateWithWindowCount(perPage: 2, page: 3);
      expect(
          conn.lastSelectSql,
          'select *, count(*) over () as eloquent_window_total from "t" where '
          '"a" = ? order by "id" asc limit 2 offset 4');
      expect(conn.selectCallCount, 1);
      expect(page.total(), 42);
      expect(page.items(), [
        {'id': 1},
        {'id': 2}
      ]);
      final p2 = await pg2()
          .select(['id'])
          .paginateWithWindowCount(page: 1, perPage: 2);
      expect(conn.lastSelectSql,
          'select "id", count(*) over () as eloquent_window_total from "t" limit 2 offset 0');
      expect(p2.total, 42);
    });

    test('an empty page past the first counts; distinct uses paginate',
        () async {
      conn.mockSelectResult = [];
      final page = await pg().paginateWithWindowCount(perPage: 2, page: 5);
      expect(conn.lastSelectSql, contains('count(*) as aggregate'));
      expect(page.total(), 10);
      final empty = await pg().paginateWithWindowCount(perPage: 2, page: 1);
      expect(empty.total(), 0);
      conn.selectCallCount = 0;
      await pg().distinct().paginateWithWindowCount(page: 1);
      expect(conn.lastSelectSql, isNot(contains('over ()')));
    });
  });
}
