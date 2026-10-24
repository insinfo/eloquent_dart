// QueryBuilder SQL that must run: whereTime, where in inside a join,
// insertUsing with a CTE, JSON selectors on MySQL, joinRaw, insertMany,
// PostgreSQL update joins with raw conditions, min/max on non-numeric
// columns. PostgreSQL (four adapters) and MariaDB/MySQL.
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

const _tables = ['cov_qb_b', 'cov_qb_a', 'cov_qb_dest', 'cov_qb_doc'];

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

      Future<void> dropTables() async {
        for (final table in _tables) {
          await db.execute('DROP TABLE IF EXISTS $table');
        }
      }

      setUp(() async {
        manager = Manager()..addConnection(_config(driver), 'cov_qb_$driver');
        db = await manager.getConnection('cov_qb_$driver');
        await dropTables();
        await db.execute('CREATE TABLE cov_qb_a (id int PRIMARY KEY, '
            'nome varchar(20), criado timestamp NULL)');
        await db.execute('CREATE TABLE cov_qb_b (id int PRIMARY KEY, '
            'a_id int, n int)');
        await db.execute('CREATE TABLE cov_qb_dest (id int PRIMARY KEY, '
            'nome varchar(20) NULL, criado timestamp NULL)');
        await db.execute(mysql
            ? 'CREATE TABLE cov_qb_doc (id int PRIMARY KEY, meta json)'
            : 'CREATE TABLE cov_qb_doc (id int PRIMARY KEY, meta jsonb)');
        await db.table('cov_qb_a').insertMany([
          {'id': 1, 'nome': 'b', 'criado': DateTime(2026, 1, 2, 9, 30)},
          {'id': 2, 'nome': 'a', 'criado': DateTime(2026, 1, 3, 13, 0)},
          {'id': 3, 'nome': 'c', 'criado': DateTime(2026, 1, 4, 18, 15)},
        ]);
        await db.table('cov_qb_b').insertMany([
          {'id': 10, 'a_id': 1, 'n': 1},
          {'id': 11, 'a_id': 2, 'n': 2},
          {'id': 12, 'a_id': 3, 'n': 3},
        ]);
      });

      tearDown(() async {
        await dropTables();
        await manager.getDatabaseManager().purge('cov_qb_$driver');
      });

      test('whereTime', () async {
        final ids = await db
            .table('cov_qb_a')
            .whereTime('criado', '>=', '12:00:00')
            .orderBy('id')
            .pluck('id');
        expect(ids, [2, 3]);
      });

      test('where in / not in inside a join', () async {
        final ids = await db
            .table('cov_qb_a')
            .join('cov_qb_b', (JoinClause join) {
              join.on('cov_qb_b.a_id', '=', 'cov_qb_a.id').whereIn(
                  'cov_qb_b.n', [1, 2, 3]).whereNotIn('cov_qb_b.n', [3]);
            })
            .where('cov_qb_a.id', '<=', 2)
            .orderBy('cov_qb_a.id')
            .pluck('cov_qb_a.id');
        expect(ids, [1, 2]);

        final none =
            await db.table('cov_qb_a').join('cov_qb_b', (JoinClause join) {
          join
              .on('cov_qb_b.a_id', '=', 'cov_qb_a.id')
              .whereIn('cov_qb_b.n', []);
        }).count();
        expect(none, 0);
      });

      test('insertUsing with a CTE', () async {
        await db.table('cov_qb_dest').withExpression('src', (QueryBuilder q) {
          q.from('cov_qb_a').select(['id', 'nome']).where('id', '>', 1);
        }).insertUsing(['id', 'nome'], (QueryBuilder q) {
          q.from('src').select(['id', 'nome']).where('id', '<', 3);
        });
        expect(await db.table('cov_qb_dest').pluck('id'), [2]);
      });

      test('insertMany: raw values, keys of later rows, result', () async {
        final result = await db.table('cov_qb_dest').insertMany([
          {'id': 1, 'criado': QueryExpression('CURRENT_TIMESTAMP')},
          {
            'id': 2,
            'criado': QueryExpression('CURRENT_TIMESTAMP'),
            'nome': 'x'
          },
        ]);
        expect(result, isA<PDOResults>());
        expect((result as PDOResults).rowsAffected, 2);
        final rows = await db.table('cov_qb_dest').orderBy('id').get();
        expect(rows.map((r) => r['nome']), [null, 'x']);
        expect(rows.every((r) => r['criado'] != null), isTrue);
      });

      test('joinRaw', () async {
        expect(
            await db
                .table('cov_qb_a')
                .joinRaw('cov_qb_b', [], SqlJoin.cross)
                .count(),
            9);
        expect(
            await db
                .table('cov_qb_a')
                .joinRaw('(select a_id as x from cov_qb_b where n = ?) j', [2],
                    SqlJoin.inner, (join) => join.onRaw('j.x = cov_qb_a.id'))
                .pluck('cov_qb_a.nome'),
            ['a']);
        // The ON written in the expression (as new_sali does).
        expect(
            await db.table('cov_qb_a').joinRaw(
                'cov_qb_b b ON b.a_id = cov_qb_a.id AND b.n = ?',
                [2]).pluck('cov_qb_a.nome'),
            ['a']);
      });

      test('update with a raw join condition', () async {
        final affected = await db
            .table('cov_qb_a')
            .join('cov_qb_b', (JoinClause join) {
              join
                  .onRaw('cov_qb_b.a_id = cov_qb_a.id')
                  .onRaw('cov_qb_b.n >= ?', SqlBool.and, [2]);
            })
            .where('cov_qb_a.id', '<', 3)
            .update(mysql ? {'cov_qb_a.nome': 'z'} : {'nome': 'z'});
        expect(affected, 1);
        expect(await db.table('cov_qb_a').where('nome', 'z').pluck('id'), [2]);
      });

      test('min/max on text and date columns', () async {
        expect(await db.table('cov_qb_a').min('nome'), 'a');
        expect(await db.table('cov_qb_a').max('nome'), 'c');
        final min = await db.table('cov_qb_a').min('criado');
        expect(min, anyOf(isA<DateTime>(), isA<String>()));
        expect('$min', contains('2026-01-02'));
        final num? maxId = await db.table('cov_qb_a').max('id');
        expect(maxId, 3);
      });

      test('whereBetween with a raw bound', () async {
        final ids = await db
            .table('cov_qb_a')
            .whereBetween('id', [QueryExpression('1 + 1'), 3])
            .orderBy('id')
            .pluck('id');
        expect(ids, [2, 3]);
      });

      test('updateOrInsert', () async {
        expect(
            await db
                .table('cov_qb_dest')
                .updateOrInsert({'id': 1}, {'nome': 'novo'}),
            isTrue);
        expect(
            await db
                .table('cov_qb_dest')
                .updateOrInsert({'id': 1}, {'nome': 'outro'}),
            isTrue);
        expect(await db.table('cov_qb_dest').pluck('nome'), ['outro']);
      });

      if (mysql) {
        test('update of JSON selectors and whereJsonContains', () async {
          await db.table('cov_qb_doc').insert({
            'id': 1,
            'meta': '{"n": 1, "f": 0.5, "b": false, "s": "a", '
                '"roles": ["admin", "dev"]}',
          });
          final affected = await db.table('cov_qb_doc').where('id', 1).update({
            'meta->n': 5,
            'meta->f': 1.5,
            'meta->b': true,
            'meta->s': 'x',
          });
          expect(affected, 1);
          final row =
              await db.selectOne("select json_extract(meta, '\$.n') as n, "
                  "json_extract(meta, '\$.f') as f, "
                  "json_extract(meta, '\$.b') as b, "
                  "json_unquote(json_extract(meta, '\$.s')) as s "
                  'from cov_qb_doc where id = 1');
          expect('${row!['n']}', '5');
          expect('${row['f']}', '1.5');
          expect('${row['b']}', 'true');
          expect(row['s'], 'x');

          expect(
              await db
                  .table('cov_qb_doc')
                  .whereJsonContains('meta->roles', 'admin')
                  .count(),
              1);
          expect(
              await db
                  .table('cov_qb_doc')
                  .whereJsonDoesntContain('meta->roles', 'ops')
                  .count(),
              1);
          expect(
              await db
                  .table('cov_qb_doc')
                  .whereJsonContains('meta', {'s': 'x'}).count(),
              1);
        });

        test('inRandomOrder with a seed', () async {
          final ids = await db.table('cov_qb_a').inRandomOrder(7).pluck('id');
          expect(ids.toSet(), {1, 2, 3});
        });
      }
    });
  }
}
