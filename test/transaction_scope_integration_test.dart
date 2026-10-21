// Integration tests for Connection.transactionScope (ambient transaction) and
// outsideTransaction, on every PostgreSQL driver adapter and the MySQL one,
// with a single connection and with a pool.
//
// Requires PostgreSQL (localhost:5432) and MySQL 8 / MariaDB 10.6+
// (localhost:3306), database `banco_teste`, user/password `dart`/`dart`.
@Tags(['integration'])
library;

import 'dart:async';

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

const _table = 'eloquent_tx_scope_test';

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

/// A repository that only knows the connection made by the manager, as the
/// SALI repositories do.
class _Repository {
  _Repository(this.db);
  final Connection db;

  Future<void> insert(int id, [String status = 'ok']) =>
      db.table(_table).insert({'id': id, 'status': status});

  Future<int> count() => db.table(_table).count();
}

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
    group('$driver${pool ? ' (pool)' : ''}', () {
      late Manager manager;
      late Connection db;
      late _Repository repository;
      final name = 'scope_${driver}_${pool ? 'pool' : 'single'}';

      setUp(() async {
        manager = Manager()..addConnection(_config(driver, pool), name);
        db = await manager.getConnection(name);
        repository = _Repository(db);
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

      test('db inside the scope is part of the transaction', () async {
        final result = await db.transactionScope((ctx) async {
          await ctx.table(_table).insert({'id': 1});
          await repository.insert(2); // `db`
          // Sees the uncommitted rows: same transaction, no deadlock.
          expect(await repository.count(), 2);
          expect(db.isInTransaction, isTrue);
          expect(db.isInTransactionScope, isTrue);
          expect(db.transactionLevel(), 1);
          return 'feito';
        }).timeout(const Duration(seconds: 20));
        expect(result, 'feito');
        expect(db.isInTransaction, isFalse);
        expect(db.isInTransactionScope, isFalse);
        expect(await ids(), [1, 2]);
      });

      test('an error rolls back the work done through db', () async {
        await expectLater(
            db.transactionScope((ctx) async {
              await repository.insert(1);
              await db.select('select 1 as x');
              await db.table(_table).where('id', 1).update({'status': 'x'});
              throw StateError('falhou');
            }),
            throwsStateError);
        expect(await ids(), isEmpty);
      });

      test('db.transaction inside the scope is a SAVEPOINT', () async {
        await db.transactionScope((ctx) async {
          await repository.insert(1);
          await expectLater(
              db.transaction((inner) async {
                expect(db.transactionLevel(), 2);
                await repository.insert(2);
                throw StateError('item');
              }),
              throwsStateError);
          expect(db.transactionLevel(), 1);
          final joined = await db.transactionIfNeeded((same) async {
            await repository.insert(3);
            return same.transactionLevel();
          });
          expect(joined, 1);
        });
        expect(await ids(), [1, 3]);
      });

      test('a scope opened on ctx covers db too', () async {
        await db.transaction((ctx) async {
          await ctx.table(_table).insert({'id': 1});
          await ctx.transactionScope((inner) async {
            await repository.insert(2);
            expect(await repository.count(), 2);
          });
        });
        expect(await ids(), [1, 2]);
      });

      test('concurrent calls inside the scope share the transaction', () async {
        await db.transactionScope((ctx) async {
          await Future.wait([
            for (var i = 1; i <= 6; i++) repository.insert(i),
          ]);
          expect(await repository.count(), 6);
        });
        expect(await ids(), [1, 2, 3, 4, 5, 6]);
      });

      test('work still running after the scope uses db normally', () async {
        final late = Completer<void>();
        await db.transactionScope((ctx) async {
          await repository.insert(1);
          unawaited(Future.delayed(const Duration(milliseconds: 50), () async {
            await repository.insert(2);
            late.complete();
          }));
        });
        await late.future.timeout(const Duration(seconds: 10));
        expect(await ids(), [1, 2]);
      });

      test('other code on the same db is not affected', () async {
        final inside = Completer<void>();
        final release = Completer<void>();
        final scope = db.transactionScope((ctx) async {
          await repository.insert(1);
          inside.complete();
          await release.future;
        });
        await inside.future;
        expect(db.isInTransaction, isFalse);
        expect(db.isInTransactionScope, isFalse);
        if (pool) {
          // Another connection of the pool: the row is not committed yet.
          expect(await repository.count().timeout(const Duration(seconds: 10)),
              0);
        }
        release.complete();
        await scope;
        expect(await ids(), [1]);
      });

      if (pool) {
        test('outsideTransaction survives the rollback', () async {
          await expectLater(
              db.transactionScope((ctx) async {
                await repository.insert(1);
                await db.outsideTransaction(() => repository.insert(99, 'log'));
                throw StateError('falhou');
              }),
              throwsStateError);
          expect(await ids(), [99]);
        });
      } else {
        test('outsideTransaction without a pool throws instead of waiting',
            () async {
          await db.transactionScope((ctx) async {
            await expectLater(
                db.outsideTransaction(() => repository.insert(99)),
                throwsStateError);
          });
          // Outside a scope it just runs.
          await db.outsideTransaction(() => repository.insert(5));
          expect(await ids(), [5]);
        });
      }
    });
  }
}
