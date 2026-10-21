// Live tests for the features ported from Laravel 12, against PostgreSQL
// (postgres, postgres_v3, dargres, dpgsql) and MariaDB/MySQL.
// Requires localhost:5432 and localhost:3306, database `banco_teste`,
// user/password `dart`/`dart`.
@Tags(['integration'])
library;

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

Map<String, dynamic> _config(String driver) => driver == 'mysql'
    ? {
        'driver': 'mysql',
        'host': 'localhost',
        'port': '3306',
        'database': 'banco_teste',
        'username': 'dart',
        'password': 'dart',
      }
    : {
        'driver': 'pgsql',
        'driver_implementation': driver,
        'host': 'localhost',
        'port': '5432',
        'database': 'banco_teste',
        'username': 'dart',
        'password': 'dart',
        'charset': 'utf8',
        'schema': ['public'],
      };

const _table = 'eloquent_l12_port';

void main() {
  for (final driver in [
    'postgres',
    'postgres_v3',
    'dargres',
    'dpgsql',
    'mysql'
  ]) {
    group(driver, () {
      late Manager manager;
      late Connection db;
      final name = 'l12_$driver';

      setUp(() async {
        manager = Manager()..addConnection(_config(driver), name);
        db = await manager.getConnection(name);
        await db.execute('DROP TABLE IF EXISTS $_table');
        await db.execute('CREATE TABLE $_table (id int PRIMARY KEY, '
            'nome varchar(40), grupo varchar(10), n int, m int)');
        await db.table(_table).insertMany([
          for (var i = 1; i <= 25; i++)
            {
              'id': i,
              'nome': i.isEven ? 'Ana $i' : 'JOÃO $i',
              'grupo': i <= 10 ? 'a' : 'b',
              'n': i,
              'm': 0,
            }
        ]);
      });

      tearDown(() async {
        await db.execute('DROP TABLE IF EXISTS $_table');
        await manager.getDatabaseManager().purge(name);
      });

      test('query log, listen, onSlowQuery and pretend', () async {
        final events = <QueryExecuted>[];
        final stop = db.listen(events.add);
        final slow = <String>[];
        final stopSlow = db.onSlowQuery(Duration.zero, (q) => slow.add(q.sql));
        db.enableQueryLog();

        await db.table(_table).where('id', 1).first();
        await db.transaction((ctx) async {
          await ctx.table(_table).where('id', 2).update({'m': 1});
        });
        await expectLater(db.select('select * from tabela_inexistente_l12'),
            throwsA(anything));

        expect(
            events.map((e) => e.sql).toList(), [for (final e in events) e.sql]);
        expect(events.where((e) => e.sql.contains('update')), hasLength(1),
            reason: 'statements run through the transaction ctx are reported');
        expect(events.last.failed, isTrue);
        expect(events.first.time, greaterThan(Duration.zero));
        expect(events.first.toRawSql(), contains("= 1"));
        expect(db.getQueryLog().length, greaterThanOrEqualTo(3));
        expect(slow, isNotEmpty);
        expect(db.totalQueryDuration(), greaterThan(Duration.zero));

        stop();
        stopSlow();
        final before = events.length;
        await db.table(_table).count();
        expect(events.length, before);

        final log = await db.pretend((Connection c) async {
          await c.table(_table).where('id', 3).delete();
          await c.table(_table).insert({'id': 99, 'nome': 'x'});
        });
        expect(log, hasLength(2));
        expect(await db.table(_table).count(), 25, reason: 'nothing ran');
        db.disableQueryLog();
      });

      test('whereLike is case-insensitive by default', () async {
        expect(await db.table(_table).whereLike('nome', 'joão%').count(), 13);
        expect(
            await db
                .table(_table)
                .whereLike('nome', 'joão%', caseSensitive: true)
                .count(),
            0);
        expect(
            await db
                .table(_table)
                .whereAny(['nome', 'grupo'], 'like', 'Ana 2%').count(),
            4); // Ana 2, Ana 20, Ana 22, Ana 24
      });

      test('lazyById, chunkById and eachById read every row once', () async {
        final ids = await db
            .table(_table)
            .where('grupo', 'b')
            .lazyById(4)
            .map((r) => r['id'] as int)
            .toList();
        expect(ids, [for (var i = 11; i <= 25; i++) i]);

        final desc = await db.table(_table).lazyByIdDesc(7).take(3).toList();
        expect(desc.map((r) => r['id']).toList(), [25, 24, 23]);

        var pages = 0;
        await db.table(_table).chunkById(10, (rows) {
          pages++;
          return true;
        });
        expect(pages, 3);

        final names = await db
            .table(_table)
            .orderBy('id')
            .chunkMap((r) => (r['nome'] as String).split(' ').first, 10);
        expect(names.toSet(), {'Ana', 'JOÃO'});
      });

      test('whereIntegerInRaw beyond the bind-parameter limit', () async {
        final ids = [for (var i = 1; i <= 70000; i++) i];
        expect(await db.table(_table).whereIntegerInRaw('id', ids).count(), 25);
        expect(
            await db.table(_table).whereIntegerNotInRaw('id', [1, 2]).count(),
            23);
      });

      test('incrementEach, sole, having variants and subqueries', () async {
        await db.table(_table).where('id', 1).incrementEach({'n': 10, 'm': 2});
        final row = await db.table(_table).where('id', 1).sole(['n', 'm']);
        expect(row['n'], 11);
        expect(row['m'], 2);
        await expectLater(db.table(_table).where('grupo', 'a').sole(),
            throwsA(isA<MultipleRecordsFoundException>()));

        final groups = await db
            .table(_table)
            .select(['grupo'])
            .selectRaw('count(*) as total')
            .groupBy('grupo')
            .havingBetween('grupo', ['a', 'a'])
            .orHaving((QueryBuilder h) => h.havingRaw('count(*) > ?', [14]))
            .orderBy('grupo')
            .get();
        expect(groups.map((g) => g['grupo']).toList(), ['a', 'b']);

        final top = await db
            .table(_table)
            .select(['id'])
            .addSelect({
              'maior': db.table('$_table as x').selectRaw('max(x.n)'),
            })
            .orderByDesc((QueryBuilder q) => q
                .from('$_table as y')
                .selectRaw('max(y.n)')
                .whereColumn('y.id', '$_table.id'))
            .first();
        expect(top!['id'], 25);
        expect((top['maior'] as num).toInt(), 25);

        expect(await db.table(_table).where('id', 2).doesntExist(), isFalse);
      });
    });
  }
}
