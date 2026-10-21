// Live tests for copyInto (COPY or multi-row INSERT), insertUnnest, nextValue
// and cursor() on every driver (an SQL cursor, DECLARE ... FETCH, on the
// PostgreSQL drivers without an incremental reader). Requires
// localhost:5432 and localhost:3306, database `banco_teste`, user/password
// `dart`/`dart`.
@Tags(['integration'])
library;

import 'dart:async';

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

Map<String, dynamic> _config(String driver, bool pool) => driver == 'mysql'
    ? {
        'driver': 'mysql',
        'host': 'localhost',
        'port': '3306',
        'database': 'banco_teste',
        'username': 'dart',
        'password': 'dart',
        'pool': pool,
        'poolsize': 3,
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
        'pool': pool,
        'poolsize': 3,
      };

const _table = 'eloquent_bulk_test';

void main() {
  const drivers = <(String, bool)>[
    ('postgres', false),
    ('postgres', true),
    ('postgres_v3', false),
    ('dargres', false),
    ('dargres', true),
    ('dpgsql', false),
    ('dpgsql', true),
    ('mysql', false),
    ('mysql', true),
  ];

  for (final (driver, pool) in drivers) {
    final isPg = driver != 'mysql';
    group('$driver${pool ? ' (pool)' : ''}', () {
      late Manager manager;
      late Connection db;
      final name = 'bulk_${driver}_${pool ? 'pool' : 'single'}';

      setUp(() async {
        manager = Manager()..addConnection(_config(driver, pool), name);
        db = await manager.getConnection(name);
        await db.execute('DROP TABLE IF EXISTS $_table');
        await db.execute('CREATE TABLE $_table (id int PRIMARY KEY, '
            'grupo int, nome varchar(40), ativo boolean, criado timestamp, '
            'valor numeric(10, 2))');
      });

      tearDown(() async {
        await db.execute('DROP TABLE IF EXISTS $_table');
        await manager.getDatabaseManager().purge(name);
      });

      List<Map<String, Object?>> rows(int count, [int from = 1]) => [
            for (var i = from; i < from + count; i++)
              {
                'id': i,
                'grupo': i % 3,
                'nome': i == 2 ? 'tab\there "aspas" \\ e\nlinha' : 'n$i',
                'ativo': i.isEven,
                'criado': DateTime(2026, 2, 3, 4, 5, 6, 789),
                'valor': i == 3 ? null : i * 1.5,
              }
          ];

      test('copyInto', () async {
        expect(await db.table(_table).copyInto(rows(2500)), 2500);
        expect(await db.table(_table).count(), 2500);
        final second = await db.table(_table).where('id', 2).first();
        expect(second!['nome'], 'tab\there "aspas" \\ e\nlinha');
        expect(second['ativo'], anyOf(true, 1));
        final third = await db.table(_table).where('id', 3).first();
        expect(third!['valor'], isNull);
        final criado = (await db
            .table(_table)
            .where('id', 1)
            .first())!['criado'] as DateTime;
        expect([criado.year, criado.month, criado.day, criado.hour],
            [2026, 2, 3, 4]);
        expect(await db.table2(_table).copyInto(rows(3, 5000)), 3);
        expect(await db.table(_table).copyInto([]), 0);
        // Inside a transaction (COPY on the transaction's connection).
        await expectLater(db.transaction((ctx) async {
          await ctx.table(_table).copyInto(rows(10, 6000));
          expect(await ctx.table(_table).where('id', '>=', 6000).count(), 10);
          throw StateError('rollback');
        }), throwsStateError);
        expect(await db.table(_table).where('id', '>=', 6000).count(), 0);
      });

      test('insertUnnest', () async {
        final types = {
          'id': 'int',
          'grupo': 'int',
          'nome': 'text',
          'ativo': 'boolean',
          'criado': 'timestamp',
          'valor': 'numeric',
        };
        expect(await db.table(_table).insertUnnest(rows(1200), types: types),
            1200);
        expect(await db.table(_table).count(), 1200);
        final second = await db.table(_table).where('id', 2).first();
        expect(second!['nome'], 'tab\there "aspas" \\ e\nlinha');
        expect(
            (await db.table(_table).where('id', 3).first())!['valor'], isNull);
        expect(
            await db.table2(_table).insertUnnest(rows(2, 9000), types: types),
            2);
        expect(
            () => db
                .table(_table)
                .insertUnnest(rows(1), types: {'id': 'int); drop table x; --'}),
            throwsArgumentError);
      });

      test('nextValue', () async {
        await db.table(_table).insertMany(rows(5));
        if (!isPg) {
          await expectLater(
              db.transaction((ctx) => ctx.table(_table).nextValue('id')),
              throwsUnsupportedError);
          expect(await db.table(_table).nextValue('id', lock: false), 6);
          return;
        }
        await expectLater(db.table(_table).nextValue('id'), throwsStateError);
        expect(await db.table(_table).nextValue('id', lock: false), 6);
        expect(
            await db
                .table(_table)
                .where('grupo', 7)
                .nextValue('id', lock: false, start: 100),
            100);

        // Concurrent transactions get consecutive numbers per scope.
        Future<int> reserve() => db.transaction((ctx) async {
              final next = await ctx.table(_table).nextValue('id');
              await Future<void>.delayed(const Duration(milliseconds: 20));
              await ctx.table(_table).insert({'id': next, 'grupo': 9});
              return next;
            });
        final reserved = pool
            ? await Future.wait([for (var i = 0; i < 4; i++) reserve()])
            : [for (var i = 0; i < 4; i++) await reserve()];
        expect(reserved.toSet(), {6, 7, 8, 9});

        // QueryBuilder2, inside a transactionScope (db is in the transaction).
        final next = await db.transactionScope(
            (ctx) => db.table2(_table).where('grupo', 9).nextValue('id'));
        expect(next, 10);
      });

      test('cursor streams every row', () async {
        await db.table(_table).copyInto(rows(2345));
        if (!isPg) {
          expect(
              () => db.table(_table).cursor().toList(), throwsUnsupportedError);
          return;
        }
        var count = 0;
        var sum = 0;
        await for (final row in db
            .table(_table)
            .where('grupo', '>=', 0)
            .orderBy('id')
            .cursor(500)) {
          count++;
          sum += row['id'] as int;
        }
        expect(count, 2345);
        expect(sum, 2345 * 2346 ~/ 2);

        // Stopping early closes the cursor and its transaction.
        final firsts = await db
            .table(_table)
            .orderBy('id')
            .cursor(100)
            .take(3)
            .map((r) => r['id'])
            .toList();
        expect(firsts, [1, 2, 3]);
        expect(await db.table(_table).count(), 2345);

        // Inside a transaction it uses the transaction's connection.
        final inTx = await db.transaction((ctx) async {
          await ctx.table(_table).where('id', 1).delete();
          return ctx
              .table(_table)
              .where('id', '<', 5)
              .orderBy('id')
              .cursor()
              .map((r) => r['id'])
              .toList();
        });
        expect(inTx, [2, 3, 4]);

        // QueryBuilder2 and an error in the query.
        expect(
            await db
                .table2(_table)
                .where('id', 2)
                .cursor()
                .map((r) => r['id'])
                .toList(),
            [2]);
        await expectLater(
            db.table(_table).where('nao_existe', 1).cursor().toList(),
            throwsA(anything));
        expect(await db.table(_table).where('id', 2).exists(), isTrue);
      });
    });
  }
}
