// SQL and bindings of QueryBuilder, its grammars, JoinClause and the
// processors: each placeholder has exactly one binding, and the SQL is valid
// for its dialect.
import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/query/grammars/query_mysql_grammar.dart';
import 'package:eloquent/src/query/json_expression.dart';
import 'package:eloquent/src/query/processors/postgres_processor.dart';
import 'package:test/test.dart';

import 'helper.dart';

/// A connection whose selects fail.
class _FailingConnection extends FakeConnection {
  @override
  Future<List<Map<String, dynamic>>> select(String query,
      [List bindings = const [],
      bool useReadPdo = true,
      int? timeoutInSeconds]) async {
    throw StateError('select failed');
  }
}

/// A connection whose inserts affect [rowsAffected] rows.
class _InsertConnection extends FakeConnection {
  _InsertConnection(this.rowsAffected);
  final int rowsAffected;
  @override
  Future<PDOResults> insert(String query,
      [List bindings = const [], int? timeoutInSeconds]) async {
    await super.insert(query, bindings, timeoutInSeconds);
    return PDOResults([], rowsAffected);
  }
}

/// The number of `?` placeholders in [sql] (none of these tests has a `?`
/// inside a string literal).
int _placeholders(String sql) => '?'.allMatches(sql).length;

void main() {
  late FakeConnection conn;
  QueryBuilder pg([FakeConnection? c]) =>
      QueryBuilder(c ?? conn, QueryPostgresGrammar(), Processor());
  QueryBuilder my([FakeConnection? c]) =>
      QueryBuilder(c ?? conn, QueryMySqlGrammar(), Processor());

  setUp(() => conn = FakeConnection());

  group('insertUsing with a CTE', () {
    for (final entry in {'pgsql': pg, 'mysql': my}.entries) {
      test('${entry.key}: the CTE is compiled with its bindings', () async {
        final qb = entry.value(null).from('cov_qb_dest').withExpression('src',
            (QueryBuilder q) {
          q.from('cov_qb_src').select(['id']).where('id', '>', 5);
        });
        await qb.insertUsing(['id'], (QueryBuilder q) {
          q.from('src').select(['id']).where('id', '<', 9);
        });
        final sql = conn.lastInsertSql!;
        expect(sql, contains('with '));
        expect(conn.lastInsertBindings, [5, 9]);
        expect(_placeholders(sql), 2);
      });
    }

    test('pgsql: with ... insert into ... select', () async {
      final qb = pg().from('dest').withExpression('src', 'select 1 as id');
      await qb.insertUsing(['id'], 'select id from src');
      expect(conn.lastInsertSql,
          'with "src" as (select 1 as id) insert into "dest" ("id") select id from src');
    });
  });

  group('whereFlex', () {
    test('a list value is one binding for its one placeholder', () {
      final qb = pg().from('t').whereFlex('tags', '=', [1, 2]);
      expect(qb.toSql(), 'select * from "t" where "tags" = ?');
      expect(qb.getBindings(), [
        [1, 2]
      ]);
    });
  });

  group('whereBetween', () {
    test('needs exactly two bounds', () {
      expect(() => pg().from('t').whereBetween('n', null), throwsArgumentError);
      expect(() => pg().from('t').whereBetween('n', [1]), throwsArgumentError);
      expect(() => pg().from('t').whereBetween('n', [1, 2, 3]),
          throwsArgumentError);
      expect(
          () => pg().from('t').whereNotBetween('n', []), throwsArgumentError);
    });

    test('two bounds, two bindings', () {
      final qb = pg()
          .from('t')
          .whereBetween('n', [1, 2]).orWhereNotBetween('m', [3, 4]);
      expect(qb.toSql(),
          'select * from "t" where "n" between ? and ? or "m" not between ? and ?');
      expect(qb.getBindings(), [1, 2, 3, 4]);
    });

    test('a raw bound is inlined, not bound', () {
      final qb = pg()
          .from('t')
          .whereBetween('d', [QueryExpression('current_date'), '2030-01-01']);
      expect(
          qb.toSql(), 'select * from "t" where "d" between current_date and ?');
      expect(qb.cleanBindings(qb.getBindings()), ['2030-01-01']);
    });
  });

  group('whereTime', () {
    test('pgsql: "col"::time', () {
      final qb = pg().from('events').whereTime('start_time', '>=', '10:00:00');
      expect(
          qb.toSql(), 'select * from "events" where "start_time"::time >= ?');
      expect(qb.getBindings(), ['10:00:00']);
    });

    test('mysql: time(`col`)', () {
      final qb = my().from('events').whereTime('start_time', '=', '10:00:00');
      expect(qb.toSql(), 'select * from `events` where time(`start_time`) = ?');
    });
  });

  group('whereJsonContains', () {
    test('mysql: json_contains with the path as its third argument', () {
      final qb = my()
          .from('docs')
          .whereJsonContains('tags', ['a'])
          .orWhereJsonContains('meta->roles', 'admin')
          .whereJsonDoesntContain('meta->a->b', 1);
      expect(
          qb.toSql(),
          'select * from `docs` where json_contains(`tags`, ?) '
          'or json_contains(`meta`, ?, \'\$."roles"\') '
          'and not json_contains(`meta`, ?, \'\$."a"."b"\')');
      expect(qb.getBindings(), ['["a"]', '"admin"', '1']);
    });
  });

  group('inRandomOrder', () {
    test('mysql: an integer seed is inlined', () {
      final dynamic qb = my().from('t');
      expect(
          qb.inRandomOrder(42).toSql(), 'select * from `t` order by RAND(42)');
      expect(my().from('t').inRandomOrder().toSql(),
          'select * from `t` order by RAND()');
      expect(my().from('t').inRandomOrder('7').toSql(),
          'select * from `t` order by RAND(7)');
    });

    test('mysql: a seed that is not an integer is rejected', () {
      expect(() => my().from('t').inRandomOrder('1); drop table t; --'),
          throwsArgumentError);
      expect(() => my().from('t').inRandomOrder('1.5'), throwsArgumentError);
    });

    test('pgsql: the seed is ignored', () {
      expect(pg().from('t').inRandomOrder('3').toSql(),
          'select * from "t" order by RANDOM()');
    });
  });

  group('get', () {
    test('a failing select restores the columns', () async {
      final qb = pg(_FailingConnection()).from('t');
      await expectLater(qb.get(['id']), throwsStateError);
      expect(qb.columnsProp, isNull);
      expect(qb.toSql(), 'select * from "t"');
    });
  });

  group('min/max', () {
    test('QueryBuilder2 types them as QueryBuilder does', () async {
      final date = DateTime.utc(2020, 1, 2);
      conn.mockSelectResult = [
        {'aggregate': date}
      ];
      final q2 = QueryBuilder2.using(() => pg(), 't');
      expect(await q2.min('created_at'), date);
      expect(await q2.max('created_at'), date);
      conn.mockSelectResult = [
        {'aggregate': '150.50'}
      ];
      final num? price = await q2.max('price');
      expect(price, 150.5);
    });

    test('a date column gives a DateTime', () async {
      final date = DateTime.utc(2020, 1, 2);
      conn.mockSelectResult = [
        {'aggregate': date}
      ];
      final dynamic qb = pg().from('t');
      expect(await qb.min('created_at'), date);
      expect(await qb.max('created_at'), date);
    });

    test('a text column gives its text', () async {
      conn.mockSelectResult = [
        {'aggregate': 'abc'}
      ];
      final dynamic qb = pg().from('t');
      expect(await qb.min('name'), 'abc');
      expect(await qb.max('name'), 'abc');
    });

    test('numeric callers still get numbers', () async {
      conn.mockSelectResult = [
        {'aggregate': '150.50'}
      ];
      final num? min = await pg().from('t').min('price');
      expect(min, 150.5);
      final num? max = await pg().from('t').max('price');
      expect(max, 150.5);
      conn.mockSelectResult = [
        {'aggregate': 7}
      ];
      final int? id = await pg().from('t').max('id');
      expect(id, 7);
      conn.mockSelectResult = [];
      expect(await pg().from('t').max('id'), isNull);
    });

    test('a numeric type on a date column throws', () async {
      conn.mockSelectResult = [
        {'aggregate': DateTime.utc(2020)}
      ];
      await expectLater(
          pg().from('t').min<num>('d'), throwsA(isA<TypeError>()));
    });
  });

  group('updateOrInsert', () {
    test('true after an insert, as Laravel (insert() succeeded)', () async {
      // exists() reads mockSelectResult: no row.
      final inserted = await pg(_InsertConnection(1))
          .from('t')
          .updateOrInsert({'id': 1}, {'n': 2});
      expect(inserted, isTrue);
      final ignored = await pg(_InsertConnection(0))
          .from('t')
          .updateOrInsert({'id': 1}, {'n': 2});
      expect(ignored, isTrue,
          reason: 'Laravel returns the result of insert(), true on success');
    });
  });

  group('setBindings', () {
    test('replaces the bindings of a type with a list', () {
      final dynamic qb = pg().from('t').whereRaw('a = ? and b = ?', [0, 0]);
      qb.setBindings([1, 2]);
      expect(qb.getBindings(), [1, 2]);
      expect(() => qb.setBindings([1], 'nope'), throwsArgumentError);
    });
  });

  group('joinRaw', () {
    // new_sali writes the ON inside the expression (ProcessoRelacionado):
    // a check that asked for conditions broke it.
    test('an expression with its own ON compiles as written', () {
      final qb = pg().from('r').joinRaw(
          'processo p ON p.id = (CASE WHEN r.a = ? THEN r.b ELSE r.a END)',
          [7]).where('r.ativo', true);
      expect(
          qb.toSql(),
          'select * from "r" inner join processo p ON p.id = '
          '(CASE WHEN r.a = ? THEN r.b ELSE r.a END) where "r"."ativo" = ?');
      expect(qb.getBindings(), [7, true]);
      expect(my().from('a').joinRaw('b', [], SqlJoin.left, (join) {}).toSql(),
          'select * from `a` left join b');
    });

    test('cross join without conditions', () {
      expect(pg().from('a').joinRaw('b', [], SqlJoin.cross).toSql(),
          'select * from "a" cross join b');
      expect(my().from('a').joinRaw('b', [], SqlJoin.cross).toSql(),
          'select * from `a` cross join b');
    });

    test('with on conditions', () {
      final qb = my().from('a').joinRaw('(select ? as x) b', [1], SqlJoin.inner,
          (join) => join.onRaw('b.x = a.id'));
      expect(qb.toSql(),
          'select * from `a` inner join (select ? as x) b on b.x = a.id');
      expect(qb.getBindings(), [1]);
    });

    test('the base grammar does not compile an empty on', () {
      final qb = QueryBuilder(conn, QueryGrammar(), Processor())
          .from('a')
          .join('b', (JoinClause join) {});
      expect(qb.toSql(), 'select * from "a" inner join "b"');
    });
  });

  group('insertMany', () {
    test('a raw value is inlined, the results are returned', () async {
      final result = await pg().from('t').insertMany([
        {'a': 1, 'b': QueryExpression('now()')},
        {'a': 2, 'b': QueryExpression('now()')},
      ]);
      expect(conn.lastInsertSql,
          'INSERT INTO "t" ("a", "b") VALUES (?, now()), (?, now())');
      expect(conn.lastInsertBindings, [1, 2]);
      expect(result, isA<PDOResults>());
    });

    test('a key of a later row is a column too', () async {
      await pg().from('t').insertMany([
        {'a': 1},
        {'a': 2, 'b': 'x'},
      ]);
      expect(conn.lastInsertSql,
          'INSERT INTO "t" ("a", "b") VALUES (?, ?), (?, ?)');
      expect(conn.lastInsertBindings, [1, null, 2, 'x']);
    });
  });

  group('joins with where in', () {
    for (final entry in {'pgsql': pg, 'mysql': my}.entries) {
      test('${entry.key}: one placeholder per value', () {
        final qb = entry.value(null).from('a').join('b', (JoinClause join) {
          join.on('a.id', '=', 'b.a_id').whereIn('b.n', [1, 2, 3]);
          join.orWhereNotIn('b.m', [4]);
        }).where('a.x', '=', 9);
        final sql = qb.toSql();
        expect(sql, contains(' in (?, ?, ?)'));
        expect(sql, contains(' not in (?)'));
        expect(qb.getBindings(), [1, 2, 3, 4, 9]);
        expect(_placeholders(sql), 5);
      });
    }

    test('mysql: onTrue', () {
      final qb = my().from('a').join('b', (JoinClause join) => join.onTrue());
      expect(qb.toSql(), 'select * from `a` inner join `b` on TRUE');
    });

    test('an empty list matches nothing', () {
      final qb = pg().from('a').join('b', (JoinClause join) {
        join.on('a.id', '=', 'b.a_id').whereIn('b.n', []);
      });
      expect(qb.toSql(),
          'select * from "a" inner join "b" on "a"."id" = "b"."a_id" and 0 = 1');
      expect(qb.getBindings(), isEmpty);
    });
  });

  group('mysql update of a JSON selector', () {
    test('inlined numbers and booleans are not bound', () async {
      await my().from('t').where('id', '=', 1).update({
        'meta->n': 5,
        'meta->f': 1.5,
        'meta->b': true,
        'meta->s': 'x',
        'name': 'y',
      });
      final sql = conn.lastUpdateSql!;
      expect(sql, contains('json_set(`meta`, "\$.n", 5)'));
      expect(conn.lastUpdateBindings, ['x', 'y', 1]);
      expect(_placeholders(sql), 3);
    });

    test('null is bound', () async {
      await my().from('t').update({'meta->n': null});
      expect(conn.lastUpdateSql,
          'update `t` set `meta` = json_set(`meta`, "\$.n", ?)');
      expect(conn.lastUpdateBindings, [null]);
    });
  });

  group('JsonExpression', () {
    test('values', () {
      expect(JsonExpression(true).getValue(), 'true');
      expect(JsonExpression(3).getValue(), 3);
      expect(JsonExpression(null).getValue(), '?');
      expect(JsonExpression([1]).getValue(), '?');
      expect(JsonExpression('a').getValue(), '?');
      expect(() => JsonExpression(double.nan), throwsArgumentError);
    });
  });

  group('pgsql update with joins', () {
    test('an onRaw condition goes to the where', () async {
      await pg()
          .from('a')
          .join('b', (JoinClause join) {
            join.onRaw('b.a_id = a.id').onRaw('b.n > ?', SqlBool.and, [3]);
          })
          .where('a.x', '=', 1)
          .update({'y': 2});
      expect(
          conn.lastUpdateSql,
          'update "a" set "y" = ? from "b" where "a"."x" = ? '
          'and b.a_id = a.id and b.n > ?');
      expect(conn.lastUpdateBindings, [2, 1, 3]);
    });

    test('an onRaw condition alone', () async {
      await pg().from('a').join('b', (JoinClause join) {
        join.onRaw('b.a_id = a.id');
      }).update({'y': 2});
      expect(conn.lastUpdateSql,
          'update "a" set "y" = ? from "b" where b.a_id = a.id');
    });
  });

  group('PostgresProcessor.processColumnListing', () {
    test('reads column_name of map rows', () {
      expect(
          PostgresProcessor().processColumnListing([
            {'column_name': 'id'},
            {'column_name': 'name'},
          ]),
          ['id', 'name']);
    });
  });

  group('removeLeadingBoolean', () {
    final g = QueryPostgresGrammar();
    test('only the leading boolean, in any case', () {
      expect(g.removeLeadingBoolean('and a = 1'), 'a = 1');
      expect(g.removeLeadingBoolean('AND a = 1'), 'a = 1');
      expect(g.removeLeadingBoolean('Or a = 1'), 'a = 1');
      expect(g.removeLeadingBoolean('a = 1 or b = 2'), 'a = 1 or b = 2');
      expect(g.removeLeadingBoolean('color = 1'), 'color = 1');
    });

    test('an upper-case boolean of the first where', () {
      final qb = pg().from('t').whereRaw('a = 1 or b = 2', [], 'AND');
      expect(qb.toSql(), 'select * from "t" where a = 1 or b = 2');
    });
  });
}
