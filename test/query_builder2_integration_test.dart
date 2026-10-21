// QueryBuilder2 against PostgreSQL (four adapters) and MariaDB/MySQL.
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
      final mysql = driver == 'mysql';

      setUp(() async {
        manager = Manager()..addConnection(_config(driver), 'qb2_$driver');
        db = await manager.getConnection('qb2_$driver');
        await db.execute('DROP TABLE IF EXISTS qb2_item');
        await db.execute('DROP TABLE IF EXISTS qb2_grupo');
        await db.execute(
            'CREATE TABLE qb2_grupo (id int PRIMARY KEY, nome varchar(20))');
        await db.execute(mysql
            ? 'CREATE TABLE qb2_item (id int AUTO_INCREMENT PRIMARY KEY, '
                'grupo_id int, nome varchar(40), n int, obs varchar(20) null)'
            : 'CREATE TABLE qb2_item (id serial PRIMARY KEY, grupo_id int, '
                'nome varchar(40), n int, obs varchar(20) null)');
        await db.table2('qb2_grupo').insertMany([
          {'id': 1, 'nome': 'a'},
          {'id': 2, 'nome': 'b'},
        ]);
        await db.table2('qb2_item').insertMany([
          for (var i = 1; i <= 10; i++)
            {
              'grupo_id': i <= 6 ? 1 : 2,
              'nome': i.isEven ? 'Ana $i' : 'JOÃO $i',
              'n': i,
              'obs': i == 3 ? null : 'x',
            }
        ]);
      });

      tearDown(() async {
        await db.execute('DROP TABLE IF EXISTS qb2_item');
        await db.execute('DROP TABLE IF EXISTS qb2_grupo');
        await manager.getDatabaseManager().purge('qb2_$driver');
      });

      test('reads with typed results', () async {
        final rows = await db
            .table2('qb2_item')
            .select(['id', 'nome'])
            .whereGreaterThanOrEqualTo('n', 3)
            .whereGroup((w) => w.whereLike('nome', 'joão%').orWhere('n', 4))
            .orderBy('n')
            .get();
        expect(rows.map((r) => r['id']).toList(), [3, 4, 5, 7, 9]);

        expect(await db.table2('qb2_item').where('obs', null).count(), 1);
        expect(await db.table2('qb2_item').whereNotEqualTo('obs', null).count(),
            9);
        expect(
            await db.table2('qb2_item').whereBetween('n', 2, 4).pluck<int>('n'),
            unorderedEquals([2, 3, 4]));
        expect(await db.table2('qb2_item').where('n', 5).value<String>('nome'),
            'JOÃO 5');
        expect((await db.table2('qb2_item').where('n', 6).sole())['nome'],
            'Ana 6');
        expect(await db.table2('qb2_item').whereIn('n', <int>[]).exists(),
            isFalse);
        expect(
            await db.table2('qb2_item').whereNotIn('n', <int>[]).count(), 10);
        expect((await db.table2('qb2_item').sum('n'))!.toInt(), 55);

        final joined = await db
            .table2('qb2_item as i')
            .select(['i.n', 'g.nome as grupo'])
            .join('qb2_grupo as g', 'g.id', 'i.grupo_id')
            .where('g.nome', 'b')
            .orderByDescending('i.n')
            .first();
        expect(joined!['n'], 10);
        expect(joined['grupo'], 'b');

        final withItems = await db
            .table2('qb2_grupo')
            .whereExists(db
                .table2('qb2_item')
                .whereColumn('qb2_item.grupo_id', 'qb2_grupo.id')
                .whereGreaterThan('qb2_item.n', 8))
            .pluck<String>('nome');
        expect(withItems, ['b']);
      });

      test('writes, transaction ctx and lazyById', () async {
        final id = await db
            .table2('qb2_item')
            .insertGetId<int>({'grupo_id': 2, 'nome': 'Novo', 'n': 11});
        expect(id, 11);
        expect(await db.table2('qb2_item').where('id', id).update({'obs': 'y'}),
            1);
        expect(
            await db.table2('qb2_item').where('id', id).increment('n', 5), 1);
        expect(await db.table2('qb2_item').where('id', id).value<int>('n'), 16);

        await db.transaction((ctx) async {
          await ctx.table2('qb2_item').where('grupo_id', 2).delete();
        });
        expect(await db.table2('qb2_item').count(), 6);

        final ids = await db
            .table2('qb2_item')
            .lazyById(chunkSize: 4)
            .map((r) => r['id'])
            .toList();
        expect(ids, [1, 2, 3, 4, 5, 6]);
      });

      test('dialect operators through whereSqlOperator', () async {
        if (mysql) {
          expect(
              await db
                  .table2('qb2_item')
                  .whereSqlOperator('nome', 'regexp', '^Ana')
                  .count(),
              5);
          expect(
              await db
                  .table2('qb2_item')
                  .whereSqlOperator('obs', '<=>', null)
                  .count(),
              1);
        } else {
          expect(
              await db
                  .table2('qb2_item')
                  .whereSqlOperator('nome', '~*', '^joão')
                  .count(),
              5);
          expect(
              await db
                  .table2('qb2_item')
                  .whereSqlOperator('obs', 'is not distinct from', null)
                  .count(),
              1);
        }
      });
    });
  }
}
