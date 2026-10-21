// Live regression tests for the 4.0 review fixes, against PostgreSQL
// (localhost:5432) and MySQL/MariaDB (localhost:3306), database `banco_teste`,
// user/password `dart`/`dart`.
// Run: dart test test/regression_group_a_integration_test.dart -j 1
@Tags(['integration'])
library;

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

Map<String, dynamic> _pg(String driver,
        {bool pool = false, Map<String, dynamic> extra = const {}}) =>
    {
      'driver': 'pgsql',
      'driver_implementation': driver,
      'host': 'localhost',
      'port': '5432',
      'database': 'banco_teste',
      'username': 'dart',
      'password': 'dart',
      'charset': 'utf8',
      'schema': ['public'],
      'pool': pool,
      'poolsize': 2,
      ...extra,
    };

Map<String, dynamic> _mysql(
        {bool pool = false, Map<String, dynamic> extra = const {}}) =>
    {
      'driver': 'mysql',
      'host': 'localhost',
      'port': '3306',
      'database': 'banco_teste',
      'username': 'dart',
      'password': 'dart',
      'pool': pool,
      'poolsize': 2,
      ...extra,
    };

Future<Connection> _open(
    Manager manager, String name, Map<String, dynamic> config) async {
  manager.addConnection(config, name);
  return manager.getConnection(name);
}

void main() {
  late Manager manager;
  final opened = <String>[];

  setUp(() {
    manager = Manager();
    opened.clear();
  });

  tearDown(() async {
    for (final name in opened) {
      await manager.getDatabaseManager().purge(name);
    }
  });

  Future<Connection> open(String name, Map<String, dynamic> config) {
    opened.add(name);
    return _open(manager, name, config);
  }

  for (final driver in ['postgres', 'postgres_v3', 'dargres', 'dpgsql']) {
    group('PostgreSQL ($driver)', () {
      late Connection db;

      setUp(() async {
        db = await open('pg_$driver', _pg(driver));
        await db.execute('DROP TABLE IF EXISTS ga_b');
        await db.execute('DROP TABLE IF EXISTS ga_a');
        await db.execute(
            'CREATE TABLE ga_a (id int PRIMARY KEY, status varchar(10), x int)');
        await db.execute('CREATE TABLE ga_b (id int PRIMARY KEY, a_id int, '
            'flag boolean)');
        await db.table('ga_a').insertMany([
          {'id': 1, 'status': 'new', 'x': 1},
          {'id': 2, 'status': 'new', 'x': 1},
          {'id': 3, 'status': 'done', 'x': 1},
          {'id': 4, 'status': 'done', 'x': 2},
        ]);
        await db.table('ga_b').insertMany([
          {'id': 10, 'a_id': 1, 'flag': true},
          {'id': 11, 'a_id': 2, 'flag': false},
        ]);
      });

      tearDown(() async {
        await db.execute('DROP TABLE IF EXISTS ga_b');
        await db.execute('DROP TABLE IF EXISTS ga_a');
      });

      Future<List<int>> ids() async =>
          (await db.table('ga_a').orderBy('id').get())
              .map((r) => r['id'] as int)
              .toList();

      test('count and pagination with groupBy and distinct', () async {
        expect(await db.table('ga_a').groupBy('status').count(), 2);
        // x = 1 has 3 rows, x = 2 has 1: two groups.
        expect(await db.table('ga_a').groupBy('x').count(), 2);
        // Laravel semantics: the first group's count (ordered to be stable).
        expect(
            await db
                .table('ga_a')
                .groupBy('x')
                .orderBy('x')
                .count('*', CountMode.laravel),
            3);
        expect(await db.table('ga_a').distinct().select(['status']).count(), 2);
        final page = await db
            .table('ga_a')
            .select(['status'])
            .groupBy('status')
            .paginate(perPage: 1, page: 1);
        expect(page.total(), 2);
      });

      test('groupByRaw with bindings', () async {
        // x: 1, 1, 1, 2 -> x % 2: 1, 1, 1, 0 -> groups {0: 1 row, 1: 3 rows}
        final rows = await db
            .table('ga_a')
            .selectRaw('count(*) as total')
            .groupByRaw('x % ?', [2])
            .orderByRaw('count(*)')
            .get();
        expect(rows.map((r) => (r['total'] as num).toInt()).toList(), [1, 3]);
        expect(await db.table('ga_a').groupByRaw('x % ?', [2]).count(), 2);
      });

      test('delete with a join deletes only the joined rows', () async {
        final deleted = await db
            .table('ga_a')
            .join('ga_b', (JoinClause j) {
              j.on('ga_b.a_id', '=', 'ga_a.id').where('ga_b.flag', '=', true);
            })
            .where('ga_a.x', '=', 1)
            .delete();
        expect(deleted, 1);
        expect(await ids(), [2, 3, 4]);
      });

      test('update and delete honour limit', () async {
        final updated = await db
            .table('ga_a')
            .where('status', '=', 'new')
            .orderBy('id')
            .limit(1)
            .update({'status': 'taken'});
        expect(updated, 1);
        expect(await db.table('ga_a').where('status', '=', 'taken').value('id'),
            1);

        final deleted =
            await db.table('ga_a').orderBy('id', 'desc').limit(2).delete();
        expect(deleted, 2);
        expect(await ids(), [1, 2]);
      });

      test('update with a CTE (job-queue pattern)', () async {
        final cte = db
            .table('ga_a')
            .select(['id'])
            .where('status', '=', 'new')
            .orderBy('id')
            .limit(1)
            .lockForUpdate(skipLocked: true);
        final updated = await db
            .table('ga_a')
            .withExpression('nxt', cte)
            .join('nxt', 'nxt.id', '=', 'ga_a.id')
            .update({'status': 'running'});
        expect(updated, 1);
        expect(
            await db.table('ga_a').where('status', '=', 'running').value('id'),
            1);
      });

      test('two-argument where and value()', () async {
        expect(await db.table('ga_a').where('status', 'done').count(), 2);
        expect(await db.table('ga_a').where('id', 4).value('status'), 'done');
      });

      test('builder timeout cancels a slow select', () async {
        await expectLater(
            db.table('ga_a').selectRaw('pg_sleep(3)').limit(1).get(['*'], 1),
            throwsA(anything));
        // The connection is still usable after the cancelled command.
        expect(await db.table('ga_a').count(), 4);
      });
    });
  }

  group('single connection (no pool) serves concurrent callers', () {
    final configs = <String, Map<String, dynamic>>{
      for (final d in ['postgres', 'postgres_v3', 'dargres', 'dpgsql'])
        d: _pg(d),
      'mysql': _mysql(),
    };
    configs.forEach((name, config) {
      test(name, () async {
        final db = await open('conc_$name', config);
        final results = await Future.wait([
          for (var i = 0; i < 5; i++) db.select('select $i as v'),
          db.transaction((ctx) async => (await ctx.select('select 10 as v'))),
          db.transaction((ctx) async => (await ctx.select('select 11 as v'))),
        ]);
        expect(results.map((r) => '${r.single['v']}').toList(),
            ['0', '1', '2', '3', '4', '10', '11']);
      });
    });
  });

  group('PostgreSQL session timeouts', () {
    for (final driver in ['postgres', 'postgres_v3', 'dargres', 'dpgsql']) {
      test('$driver applies statement_timeout (snake_case key too)', () async {
        final db = await open(
            'pgto_$driver',
            _pg(driver, extra: {
              'statement_timeout': '1500ms',
              'lockTimeout': '700ms'
            }));
        expect((await db.select('SHOW statement_timeout')).first.values.first,
            '1500ms');
        expect(
            (await db.select('SHOW lock_timeout')).first.values.first, '700ms');
      });
    }
  });

  test('postgres_fork maps duplicate column names the same in a transaction',
      () async {
    final db = await open('pg_dup', _pg('postgres'));
    const sql = 'select 1 as id, 2 as id';
    final outside = (await db.select(sql)).first;
    final inside =
        await db.transaction((ctx) async => (await ctx.select(sql)).first);
    expect(inside, outside);
  });

  test('prepareBindings does not modify the caller list', () async {
    final db = await open('pg_bind', _pg('postgres'));
    final when = DateTime(2026, 10, 19, 12, 30);
    final bindings = <dynamic>[when];
    await db.select('select ?::timestamp as t', bindings);
    expect(bindings.single, same(when));
  });

  group('MySQL/MariaDB', () {
    late Connection db;

    setUp(() async {
      db = await open('my', _mysql());
      await db.execute('DROP TABLE IF EXISTS ga_m');
      await db.execute(
          'CREATE TABLE ga_m (id int PRIMARY KEY, parent int, status varchar(10))');
      await db.table('ga_m').insertMany([
        {'id': 1, 'parent': 0, 'status': 'new'},
        {'id': 2, 'parent': 1, 'status': 'new'},
        {'id': 3, 'parent': 1, 'status': 'done'},
      ]);
    });

    tearDown(() async {
      await db.execute('DROP TABLE IF EXISTS ga_m');
    });

    test('select with a CTE', () async {
      final rows = await db
          .table('kids')
          .withExpression('kids', db.table('ga_m').where('parent', '=', 1))
          .orderBy('id')
          .get();
      expect(rows.map((r) => r['id']).toList(), [2, 3]);
    });

    test('exists and updateOrInsert', () async {
      expect(await db.table('ga_m').where('id', 1).exists(), isTrue);
      expect(await db.table('ga_m').where('id', 99).exists(), isFalse);
      // An existing row is updated, not inserted again.
      expect(
          await db.table('ga_m').updateOrInsert({'id': 1}, {'status': 'upd'}),
          isTrue);
      expect(await db.table('ga_m').count(), 3);
      expect(await db.table('ga_m').where('id', 1).value('status'), 'upd');
    });

    test('count with groupBy', () async {
      expect(await db.table('ga_m').groupBy('status').count(), 2);
      expect(await db.table('ga_m').groupByRaw('parent + ?', [1]).count(), 2);
    });

    test('pool applies the session to every connection', () async {
      final pool = await open(
          'my_pool',
          _mysql(pool: true, extra: {
            'timezone': '-03:00',
            'lockTimeout': '7s',
          }));
      final results = await Future.wait(List.generate(
          4,
          (_) => pool.transaction(
              (ctx) => ctx.select('select @@session.time_zone as tz, '
                  '@@session.lock_wait_timeout as lw, connection_id() as id, '
                  'sleep(0.2) as s'))));
      final rows = results.map((r) => r.first).toList();
      expect(rows.map((r) => r['id']).toSet(), hasLength(2));
      expect(rows.map((r) => '${r['tz']}').toSet(), {'-03:00'});
      expect(rows.map((r) => '${r['lw']}').toSet(), {'7'});
    });
  });
}
