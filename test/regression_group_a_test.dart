// Regression tests (no database) for the query-builder and grammar fixes of
// the 4.0 review: where/null semantics, whereIn([]), count with groupBy,
// exists/value/union/updateOrInsert/clone, PostgreSQL DELETE ... USING and
// UPDATE/DELETE with limit, CTEs in UPDATE/DELETE and on MySQL, binding order,
// timeouts and recursionLimit.

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

  group('where with null and the two-argument form', () {
    test('where(col, value) uses "="', () {
      final q = pg().where('name', 'John');
      expect(q.toSql(), 'select * from "t" where "name" = ?');
      expect(q.getBindings(), ['John']);
    });

    test('orWhere(col, value) uses "="', () {
      final q = pg().where('a', '=', 1).orWhere('name', 'John');
      expect(q.toSql(), 'select * from "t" where "a" = ? or "name" = ?');
      expect(q.getBindings(), [1, 'John']);
    });

    test('a value that looks like an operator is still a value', () {
      final q = pg().where('op', '>');
      expect(q.toSql(), 'select * from "t" where "op" = ?');
      expect(q.getBindings(), ['>']);
    });

    test('= null, <> null and != null', () {
      expect(pg().where('a', '=', null).toSql(),
          'select * from "t" where "a" is null');
      expect(
          pg().where('a', null).toSql(), 'select * from "t" where "a" is null');
      expect(pg().where('a', '<>', null).toSql(),
          'select * from "t" where "a" is not null');
      expect(pg().where('a', '!=', null).toSql(),
          'select * from "t" where "a" is not null');
    });

    test('other operators with null throw', () {
      for (final op in ['>', '<', '>=', 'like']) {
        expect(() => pg().where('a', op, null), throwsArgumentError,
            reason: op);
      }
    });

    test('nested closures and maps still work', () {
      final q = pg()
          .where((QueryBuilder q) => q.where('a', '=', 1).orWhere('b', 2))
          .where({'c': 3});
      expect(q.toSql(),
          'select * from "t" where ("a" = ? or "b" = ?) and ("c" = ?)');
      expect(q.getBindings(), [1, 2, 3]);
    });
  });

  group('whereIn', () {
    test('an empty list never produces "in ()"', () {
      expect(pg().whereIn('id', []).toSql(), 'select * from "t" where 0 = 1');
      expect(
          pg().whereNotIn('id', []).toSql(), 'select * from "t" where 1 = 1');
    });

    test('a Set is bound like a list', () {
      final q = pg().whereIn('id', {1, 2});
      expect(q.toSql(), 'select * from "t" where "id" in (?, ?)');
      expect(q.getBindings(), [1, 2]);
    });
  });

  group('count', () {
    test('groupBy counts the groups through a subquery', () async {
      final total = await pg().groupBy('status').count();
      expect(conn.lastSelectSql,
          'select count(*) as aggregate from (select 1 from "t" group by "status") as "aggregate_table"');
      expect(total, 10); // FakeConnection answers every count with 10
    });

    test('distinct over the selected columns counts distinct rows', () async {
      await pg().distinct().select(['a', 'b']).where('x', '=', 1).count();
      expect(conn.lastSelectSql,
          'select count(*) as aggregate from (select distinct "a", "b" from "t" where "x" = ?) as "aggregate_table"');
      expect(conn.lastSelectBindings, [1]);
    });

    test('CountMode.laravel keeps Laravel semantics', () async {
      await pg().groupBy('status').count('*', CountMode.laravel);
      expect(conn.lastSelectSql,
          'select count(*) as aggregate from "t" group by "status"');

      await pg().distinct().select(['a']).count('*', CountMode.laravel);
      expect(conn.lastSelectSql, 'select count(*) as aggregate from "t"');

      // Laravel itself counts having/union queries through a subquery.
      await pg()
          .groupBy('status')
          .having('status', '<>', 'x')
          .count('*', CountMode.laravel);
      expect(conn.lastSelectSql,
          'select count(*) as aggregate from (select 1 from "t" group by "status" having "status" <> ?) as "aggregate_table"');
    });

    test('groupByRaw binds in SQL order and counts through a subquery',
        () async {
      final q = pg()
          .selectRaw('x % ? as r, count(*) as total', [3])
          .where('a', '=', 1)
          .groupByRaw('x % ?', [3])
          .having('total', '>', 0);
      expect(q.toSql(),
          'select x % ? as r, count(*) as total from "t" where "a" = ? group by x % ? having "total" > ?');
      expect(q.getBindings(), [3, 1, 3, 0]);

      await pg().where('a', '=', 1).groupByRaw('x % ?', [3]).count();
      expect(conn.lastSelectSql,
          'select count(*) as aggregate from (select 1 from "t" where "a" = ? group by x % ?) as "aggregate_table"');
      expect(conn.lastSelectBindings, [1, 3]);
    });

    test('groupBy accepts raw expressions and rejects other values', () {
      expect(pg().groupBy(QueryExpression('date(created_at)')).toSql(),
          'select * from "t" group by date(created_at)');
      expect(pg().groupBy(['a', QueryExpression('b + 1')]).toSql(),
          'select * from "t" group by "a", b + 1');
      expect(() => pg().groupBy(1), throwsArgumentError);
    });

    test('distinct count of one column keeps count(distinct col)', () async {
      await pg().distinct().count('id');
      expect(conn.lastSelectSql,
          'select count(distinct "id") as aggregate from "t"');
    });

    test('pagination count drops order/limit and keeps the builder intact',
        () async {
      final q = pg().groupBy('status').orderBy('status').limit(5);
      await q.getCountForPagination();
      expect(conn.lastSelectSql,
          'select count(*) as aggregate from (select 1 from "t" group by "status") as "aggregate_table"');
      expect(q.toSql(),
          'select * from "t" group by "status" order by "status" asc limit 5');
    });

    test('paginate does not leave limit/offset on the builder', () async {
      conn.mockSelectResult = [
        {'id': 1}
      ];
      final q = pg().where('a', '=', 1);
      await q.paginate(perPage: 10, page: 2);
      expect(conn.lastSelectSql,
          'select * from "t" where "a" = ? limit 10 offset 10');
      expect(q.toSql(), 'select * from "t" where "a" = ?');
    });
  });

  group('builder methods', () {
    test('exists() reads from the read connection', () async {
      await pg().exists();
      expect(conn.lastSelectUseReadPdo, isTrue);
      await pg().useWritePdo().exists();
      expect(conn.lastSelectUseReadPdo, isFalse);
    });

    test('value(col) returns the value, not the row', () async {
      conn.mockSelectResult = [
        {'name': 'Ana'}
      ];
      expect(await pg().value('t.name'), 'Ana');
      conn.mockSelectResult = [];
      expect(await pg().value('name'), isNull);
    });

    test('whereColumn with arrays compares columns', () {
      final q = pg().whereColumn([
        ['first_name', '=', 'last_name'],
        ['updated_at', '>', 'created_at'],
      ]);
      expect(q.toSql(),
          'select * from "t" where ("first_name" = "last_name" and "updated_at" > "created_at")');
      expect(q.getBindings(), isEmpty);
      expect(pg().whereColumn({'a': 'b'}).toSql(),
          'select * from "t" where ("a" = "b")');
    });

    test('exists() understands MySQL 1/0', () async {
      conn.mockSelectResult = [
        {'exists': 1}
      ];
      expect(await my().exists(), isTrue);
      conn.mockSelectResult = [
        {'exists': 0}
      ];
      expect(await my().exists(), isFalse);
    });

    test('union accepts a Function(QueryBuilder)', () {
      final q = pg('a')
          .where('x', '=', 1)
          .union((QueryBuilder u) => u.from('b').where('y', '=', 2));
      expect(q.toSql(),
          'select * from "a" where "x" = ? union select * from "b" where "y" = ?');
      expect(q.getBindings(), [1, 2]);
    });

    test('updateOrInsert applies the attributes once', () async {
      conn.mockSelectResult = [
        {'exists': true}
      ];
      final ok = await pg().updateOrInsert({'email': 'a@b'}, {'name': 'X'});
      expect(ok, isTrue);
      expect(conn.lastUpdateSql,
          'update "t" set "name" = ? where ctid in (select ctid from "t" where ("email" = ?) limit 1)');
      expect(conn.lastUpdateBindings, ['X', 'a@b']);
    });

    test('clone copies onConflict, returning, aggregate and useWritePdo', () {
      final q = pg()
        ..onConflict(['id']).doNothing()
        ..returning(['id'])
        ..useWritePdo()
        ..aggregateProp = {
          'function': 'count',
          'columns': ['*']
        };
      final c = q.clone();
      expect(c.onConflictProp, same(q.onConflictProp));
      expect(c.returningProp, ['id']);
      expect(identical(c.returningProp, q.returningProp), isFalse);
      expect(c.useWritePdoProp, isTrue);
      expect(c.aggregateProp, q.aggregateProp);
    });
  });

  group('PostgreSQL UPDATE/DELETE', () {
    test('delete with a join uses USING and binds in SQL order', () async {
      await pg('a')
          .join('b', (JoinClause j) {
            j.on('b.a_id', '=', 'a.id').where('b.flag', '=', true);
          })
          .where('a.x', '=', 1)
          .delete();
      expect(conn.lastDeleteSql,
          'delete from "a" using "b" where "a"."x" = ? and "b"."a_id" = "a"."id" and "b"."flag" = ?');
      expect(conn.lastDeleteBindings, [1, true]);
    });

    test('delete/update with a left join throw instead of acting as inner', () {
      expect(() => pg('a').leftJoin('b', 'b.a_id', '=', 'a.id').delete(),
          throwsUnsupportedError);
      expect(
          () => pg('a').leftJoin('b', 'b.a_id', '=', 'a.id').update({'x': 1}),
          throwsUnsupportedError);
    });

    test('delete with limit restricts by ctid', () async {
      await pg().where('a', '=', 1).orderBy('id').limit(2).delete();
      expect(conn.lastDeleteSql,
          'delete from "t" where ctid in (select ctid from "t" where "a" = ? order by "id" asc limit 2)');
      expect(conn.lastDeleteBindings, [1]);
    });

    test('update with a CTE keeps the WITH and orders the bindings', () async {
      await pg('jobs')
          .withExpression(
              'cte', pg('jobs').select(['id']).where('status', '=', 'pending'))
          .join('cte', 'cte.id', '=', 'jobs.id')
          .where('jobs.tries', '<', 3)
          .update({'status': 'running'});
      expect(conn.lastUpdateSql,
          'with "cte" as (select "id" from "jobs" where "status" = ?) update "jobs" set "status" = ? from "cte" where "jobs"."tries" < ? and "cte"."id" = "jobs"."id"');
      expect(conn.lastUpdateBindings, ['pending', 'running', 3]);
    });

    test('delete with a CTE keeps the WITH', () async {
      await pg('t')
          .withExpression('old', pg('t').select(['id']).where('a', '=', 1))
          .whereIn('id', (QueryBuilder q) => q.from('old').select(['id']))
          .delete();
      expect(conn.lastDeleteSql,
          'with "old" as (select "id" from "t" where "a" = ?) delete from "t" where "id" in (select "id" from "old")');
      expect(conn.lastDeleteBindings, [1]);
    });

    test('recursionLimit fails loudly', () {
      expect(() => pg().recursionLimit(10).toSql(), throwsUnsupportedError);
    });
  });

  group('MySQL', () {
    test('select emits the CTE', () {
      final q = my('tree')
          .withExpression('tree', my('nodes').where('parent', '=', 1));
      expect(q.toSql(),
          'with `tree` as (select * from `nodes` where `parent` = ?) select * from `tree`');
      expect(q.getBindings(), [1]);
    });

    test('update with a join orders join, SET and where bindings', () async {
      await my('a')
          .join('b', (JoinClause j) {
            j.on('b.a_id', '=', 'a.id').where('b.flag', '=', 1);
          })
          .where('a.x', '=', 2)
          .update({'y': 3});
      expect(conn.lastUpdateSql,
          'update `a` inner join `b` on `b`.`a_id` = `a`.`id` and `b`.`flag` = ? set `y` = ? where `a`.`x` = ?');
      expect(conn.lastUpdateBindings, [1, 3, 2]);
    });

    test('recursionLimit fails loudly', () {
      expect(() => my().recursionLimit(10).toSql(), throwsUnsupportedError);
    });
  });

  group('timeouts reach the connection', () {
    test('get, insert, update and delete', () async {
      await pg().get(['*'], 7);
      expect(conn.lastSelectTimeout, 7);
      await pg().insert({'a': 1}, const Duration(milliseconds: 1500));
      expect(conn.lastInsertTimeout, 2);
      await pg().update({'a': 1}, const Duration(seconds: 3));
      expect(conn.lastUpdateTimeout, 3);
      await pg().delete(null, const Duration(seconds: 4));
      expect(conn.lastDeleteTimeout, 4);
    });
  });
}
