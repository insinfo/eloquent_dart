// Integration tests for transaction state, nested transactions (SAVEPOINT),
// transactionIfNeeded and FOR UPDATE SKIP LOCKED, run against every
// PostgreSQL driver adapter and the MySQL one.
//
// Requires PostgreSQL (localhost:5432) and MySQL 8 / MariaDB 10.6+
// (localhost:3306), both with database `banco_teste` and user/password
// `dart`/`dart`. Run: dart test test/transaction_savepoint_integration_test.dart -j 1

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

const _table = 'eloquent_tx_savepoint_test';

Map<String, dynamic> _config(String driver, bool pool) => driver == 'mysql'
    ? {
        'driver': 'mysql',
        'host': 'localhost',
        'port': '3306',
        'database': 'banco_teste',
        'username': 'dart',
        'password': 'dart',
        'pool': pool,
        'poolsize': 2,
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
        'prefix': '',
        'schema': ['public'],
        'pool': pool,
        'poolsize': 2,
      };

void main() {
  const drivers = <(String, bool)>[
    ('postgres', false),
    ('postgres', true),
    ('postgres_v3', false),
    ('dargres', false),
    ('dargres', true),
    ('dpgsql', false),
    // MySQL 8 / MariaDB 10.6+ (SKIP LOCKED); localhost:3306, banco_teste.
    ('mysql', false),
    ('mysql', true),
  ];

  for (final (driver, pool) in drivers) {
    group('$driver${pool ? ' (pool)' : ''}', () {
      late Manager manager;
      late Connection db;
      final name = '${driver}_${pool ? 'pool' : 'single'}';

      setUp(() async {
        manager = Manager()..addConnection(_config(driver, pool), name);
        db = await manager.getConnection(name);
        await db.execute('DROP TABLE IF EXISTS $_table');
        await db.execute(
            'CREATE TABLE $_table (id int PRIMARY KEY, status varchar(20))');
      });

      tearDown(() async {
        await db.execute('DROP TABLE IF EXISTS $_table');
        await manager.getDatabaseManager().purge(name);
      });

      Future<List<int>> ids() async {
        final rows = await db.table(_table).orderBy('id').get();
        return rows.map((row) => row['id'] as int).toList();
      }

      test('state outside and inside transactions (levels 0..3)', () async {
        expect(db.isInTransaction, isFalse);
        expect(db.transactionLevel(), 0);
        expect(db.supportsSavepoints, isFalse);

        await db.transaction((ctx) async {
          expect(ctx.isInTransaction, isTrue);
          expect(ctx.transactionLevel(), 1);
          expect(ctx.supportsSavepoints, isTrue);
          await ctx.transaction((ctx2) async {
            expect(ctx2.isInTransaction, isTrue);
            expect(ctx2.transactionLevel(), 2);
            await ctx2.transaction((ctx3) async {
              expect(ctx3.transactionLevel(), 3);
            });
            expect(ctx2.transactionLevel(), 2);
          });
          expect(ctx.transactionLevel(), 1);
        });
        expect(db.transactionLevel(), 0);
      });

      test('generic return value', () async {
        final result = await db.transaction((ctx) async => 123);
        expect(result, isA<int>());
        expect(result, 123);

        final nested = await db
            .transaction((ctx) => ctx.transaction((ctx2) async => 'interno'));
        expect(nested, 'interno');
      });

      test('a failing savepoint rolls back only its own work', () async {
        await db.transaction((ctx) async {
          await ctx.table(_table).insert({'id': 1});
          await expectLater(
            ctx.transaction((nested) async {
              await nested.table(_table).insert({'id': 2});
              throw StateError('falha no item');
            }),
            throwsStateError,
          );
          await ctx.table(_table).insert({'id': 3});
        });
        expect(await ids(), [1, 3]);
      });

      test('an error in the outer transaction rolls back everything', () async {
        await expectLater(
          db.transaction((ctx) async {
            await ctx.table(_table).insert({'id': 1});
            await ctx.transaction((nested) async {
              await nested.table(_table).insert({'id': 2});
            });
            throw StateError('falha externa');
          }),
          throwsStateError,
        );
        expect(await ids(), isEmpty);
      });

      test('the outer transaction survives an SQL error inside a savepoint',
          () async {
        await db.transaction((ctx) async {
          await ctx.table(_table).insert({'id': 1});
          await expectLater(
            ctx.transaction((nested) async {
              // duplicate key: PostgreSQL aborts up to the savepoint
              await nested.table(_table).insert({'id': 1});
            }),
            throwsA(anything),
          );
          await ctx.table(_table).insert({'id': 2});
        });
        expect(await ids(), [1, 2]);
      },
          skip: driver == 'postgres_v3'
              ? 'postgres 3.x rolls back the whole transaction after any SQL '
                  'error (runTx _transactionException), so ROLLBACK TO '
                  'SAVEPOINT cannot recover it'
              : null);

      test('transactionIfNeeded reuses the current transaction', () async {
        await db.transaction((ctx) async {
          await ctx.transactionIfNeeded((same) async {
            expect(same.transactionLevel(), 1);
            expect(identical(same, ctx), isTrue);
            await same.table(_table).insert({'id': 1});
          });
        });
        expect(await ids(), [1]);

        final level =
            await db.transactionIfNeeded((ctx) async => ctx.transactionLevel());
        expect(level, 1);
      });

      if (pool) {
        test('FOR UPDATE SKIP LOCKED skips a row locked by another transaction',
            () async {
          await db.table(_table).insertMany([
            {'id': 1, 'status': 'pending'},
            {'id': 2, 'status': 'pending'},
          ]);

          await db.transaction((first) async {
            final locked = await first
                .table(_table)
                .where('status', '=', 'pending')
                .orderBy('id')
                .lockForUpdate(skipLocked: true)
                .first();
            expect(locked!['id'], 1);

            // Another physical connection of the pool, row 1 still locked.
            final next = await db.transaction((second) => second
                .table(_table)
                .where('status', '=', 'pending')
                .orderBy('id')
                .skipLocked()
                .first());
            expect(next!['id'], 2);
          });
        });
      }
    });
  }
}
