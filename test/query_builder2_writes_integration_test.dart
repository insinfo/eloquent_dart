// QueryBuilder2: pagination, ON CONFLICT, RETURNING, upsert, union and CTE
// against PostgreSQL (four adapters) and MariaDB/MySQL.
// Requires localhost:5432 / 3306, database `banco_teste`, dart/dart.
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

void main() {
  for (final driver in ['postgres', 'postgres_v3', 'dargres', 'dpgsql', 'mysql']) {
    group(driver, () {
      late Manager manager;
      late Connection db;
      final mysql = driver == 'mysql';

      setUp(() async {
        manager = Manager()..addConnection(_config(driver), 'qb2w_$driver');
        db = await manager.getConnection('qb2w_$driver');
        for (final t in ['qb2w_item', 'qb2w_seq', 'qb2w_setor']) {
          await db.execute('DROP TABLE IF EXISTS $t');
        }
        await db.execute('CREATE TABLE qb2w_item (id int PRIMARY KEY, '
            'grupo varchar(5), n int)');
        await db.execute(
            'CREATE TABLE qb2w_seq (ano int PRIMARY KEY, ultimo int)');
        await db.execute(
            'CREATE TABLE qb2w_setor (id int PRIMARY KEY, pai_id int null)');
        await db.table2('qb2w_item').insertMany([
          for (var i = 1; i <= 23; i++)
            {'id': i, 'grupo': i <= 10 ? 'a' : 'b', 'n': i},
        ]);
      });

      tearDown(() async {
        for (final t in ['qb2w_item', 'qb2w_seq', 'qb2w_setor']) {
          await db.execute('DROP TABLE IF EXISTS $t');
        }
        await manager.getDatabaseManager().purge('qb2w_$driver');
      });

      test('paginate and simplePaginate', () async {
        final page = await db
            .table2('qb2w_item')
            .whereGreaterThan('n', 3)
            .orderBy('id')
            .paginate(page: 2, perPage: 5);
        expect(page.total, 20);
        expect(page.lastPage, 4);
        expect(page.items.map((r) => r['id']).toList(), [9, 10, 11, 12, 13]);
        expect(page.from, 6);

        final grouped = await db
            .table2('qb2w_item')
            .select(['grupo'])
            .groupBy(['grupo'])
            .orderBy('grupo')
            .paginate(page: 1, perPage: 1);
        expect(grouped.total, 2, reason: 'groups, not rows');

        final simple = await db
            .table2('qb2w_item')
            .orderBy('id')
            .simplePaginate(page: 5, perPage: 5);
        expect(simple.items.map((r) => r['id']).toList(), [21, 22, 23]);
        expect(simple.hasMorePages, isFalse);
        expect(() => db.table2('qb2w_item').paginate(page: 0),
            throwsArgumentError);
      });

      test('insert with OnConflict, insertOrIgnore, upsert', () async {
        expect(
            await db.table2('qb2w_item').insert({'id': 1, 'grupo': 'z', 'n': 0},
                onConflict: const OnConflict.doNothing(columns: ['id'])),
            0);
        expect(
            await db
                .table2('qb2w_item')
                .insertOrIgnore([
                  {'id': 2, 'grupo': 'z', 'n': 0},
                  {'id': 30, 'grupo': 'c', 'n': 30},
                ]),
            1);
        await db.table2('qb2w_item').upsert([
          {'id': 3, 'grupo': 'z', 'n': 300},
          {'id': 31, 'grupo': 'c', 'n': 31},
        ], uniqueBy: ['id'], update: ['n']);
        final row3 = (await db.table2('qb2w_item').where('id', 3).first())!;
        expect(row3['n'], 300);
        expect(row3['grupo'], 'a', reason: 'only n is updated');
        expect(await db.table2('qb2w_item').where('id', 31).exists(), isTrue);

        expect(
            () => db.table2('qb2w_item').insertMany([
                  {'id': 40, 'n': 1},
                  {'id': 41, 'grupo': 'x'},
                ]),
            throwsArgumentError);

        // Atomic sequence with an expression update.
        Future<int> next() async {
          if (mysql) {
            await db.table2('qb2w_seq').insert({'ano': 2026, 'ultimo': 1},
                onConflict: OnConflict.doUpdate(
                    columns: ['ano'],
                    set: {'ultimo': db.raw('ultimo + 1')}));
            return (await db.table2('qb2w_seq').where('ano', 2026).value<int>('ultimo'))!;
          }
          final rows = await db.table2('qb2w_seq').insertReturning(
              {'ano': 2026, 'ultimo': 1},
              onConflict: OnConflict.doUpdate(
                  columns: ['ano'],
                  set: {'ultimo': db.raw('qb2w_seq.ultimo + 1')}),
              returning: ['ultimo']);
          return rows.single['ultimo'] as int;
        }

        expect([await next(), await next(), await next()], [1, 2, 3]);
      });

      test('updateReturning and deleteReturning', () async {
        if (mysql) {
          expect(
              () => db.table2('qb2w_item').where('id', 1).updateReturning({'n': 0}),
              throwsUnsupportedError);
          return;
        }
        final updated = await db
            .table2('qb2w_item')
            .where('grupo', 'a')
            .whereLessThanOrEqualTo('id', 3)
            .updateReturning({'n': 0}, returning: ['id', 'n']);
        expect(updated.map((r) => r['id']).toList()..sort(), [1, 2, 3]);
        expect(updated.every((r) => r['n'] == 0), isTrue);

        final deleted = await db
            .table2('qb2w_item')
            .whereGreaterThan('id', 20)
            .deleteReturning(returning: ['id']);
        expect(deleted.map((r) => r['id']).toList()..sort(), [21, 22, 23]);
        expect(await db.table2('qb2w_item').count(), 20);
      });

      test('union and recursive CTE', () async {
        final ids = await db
            .table2('qb2w_item')
            .select(['id'])
            .where('id', 1)
            .unionAll(db.table2('qb2w_item').select(['id']).orderByDescending('id').limit(2))
            .orderBy('id')
            .pluck<int>('id');
        expect(ids, [1, 22, 23]);
        expect(
            await db
                .table2('qb2w_item')
                .select(['grupo'])
                .union(db.table2('qb2w_item').select(['grupo']))
                .count(),
            2);

        await db.table2('qb2w_setor').insertMany([
          {'id': 1, 'pai_id': null},
          {'id': 2, 'pai_id': 1},
          {'id': 3, 'pai_id': 2},
          {'id': 4, 'pai_id': 1},
          {'id': 5, 'pai_id': null},
        ]);
        final tree = await db
            .table2('arvore')
            .withRecursiveExpression(
                'arvore',
                db
                    .table2('qb2w_setor')
                    .select(['id'])
                    .where('id', 1)
                    .unionAll(db
                        .table2('qb2w_setor as s')
                        .select(['s.id'])
                        .join('arvore as a', 'a.id', 's.pai_id')),
                columns: ['id'])
            .orderBy('id')
            .pluck<int>('id');
        expect(tree, [1, 2, 3, 4]);
      });
    });
  }
}
