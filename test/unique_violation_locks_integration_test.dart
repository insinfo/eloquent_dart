// Live tests for UniqueConstraintViolationException, createOrFirst /
// firstOrCreate, advisoryLock / tryAdvisoryLock and lockTable on every
// driver. Requires localhost:5432 and localhost:3306, database
// `banco_teste`, user/password `dart`/`dart`.
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

const _table = 'eloquent_unique_test';
const _index = 'eloquent_unique_test_nome_uq';

void main() {
  const drivers = <(String, bool)>[
    ('postgres', false),
    ('postgres', true),
    ('postgres_v3', false),
    ('postgres_v3', true),
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
      // A second physical connection, for the concurrency tests.
      late Connection other;
      final name = 'unique_${driver}_${pool ? 'pool' : 'single'}';

      setUp(() async {
        manager = Manager()
          ..addConnection(_config(driver, pool), name)
          ..addConnection(_config(driver, false), '${name}_other');
        db = await manager.getConnection(name);
        other = await manager.getConnection('${name}_other');
        await db.execute('DROP TABLE IF EXISTS $_table');
        if (isPg) {
          await db.execute('CREATE TABLE $_table (id serial PRIMARY KEY, '
              'nome varchar(40) NOT NULL, valor int)');
          // The form of the tipo_norma index: case and spaces do not count.
          await db.execute(
              'CREATE UNIQUE INDEX $_index ON $_table (lower(trim(nome)))');
        } else {
          await db.execute('CREATE TABLE $_table (id int AUTO_INCREMENT '
              'PRIMARY KEY, nome varchar(40) NOT NULL, valor int, '
              'UNIQUE KEY $_index (nome))');
        }
      });

      tearDown(() async {
        await db.execute('DROP TABLE IF EXISTS $_table');
        await manager.getDatabaseManager().purge(name);
        await manager.getDatabaseManager().purge('${name}_other');
      });

      Future<Object?> errorOf(Future<Object?> future) =>
          future.then<Object?>((_) => null, onError: (Object e) => e);

      test('a unique violation is a UniqueConstraintViolationException',
          () async {
        await db.table(_table).insert({'nome': 'Lei', 'valor': 1});
        final error =
            await errorOf(db.table(_table).insert({'nome': 'Lei', 'valor': 2}));
        expect(error, isA<UniqueConstraintViolationException>());
        final e = error as UniqueConstraintViolationException;
        expect(e, isA<QueryException>());
        expect(e.constraint, _index);
        expect(e.sql, contains('insert into'));
        expect(e.previous, isNotNull);
        if (isPg) expect('$e', contains('23505'));
      });

      test('other errors keep the driver exception', () async {
        final error = await errorOf(db.table(_table).insert({'nome': null}));
        expect(error, isNotNull);
        expect(error, isNot(isA<QueryException>()));
      });

      test('a violation inside a transaction comes out of it mapped', () async {
        await db.table(_table).insert({'nome': 'Lei'});
        final error = await errorOf(db.transaction<void>((ctx) async {
          await ctx.table(_table).insert({'nome': 'Decreto'});
          await ctx.table(_table).insert({'nome': 'lei '});
        }));
        expect(error, isA<UniqueConstraintViolationException>());
        if (isPg) {
          expect(
              (error as UniqueConstraintViolationException).constraint, _index);
        }
        expect(await db.table(_table).count(), 1); // rolled back
      });

      test('the transaction goes on after a violation caught in a savepoint',
          () async {
        await db.transaction((ctx) async {
          await ctx.table(_table).insert({'nome': 'Lei'});
          await expectLater(
              ctx.transaction((sp) => sp.table(_table).insert({'nome': 'Lei'})),
              throwsA(isA<UniqueConstraintViolationException>()));
          await ctx.table(_table).insert({'nome': 'Decreto'});
        });
        expect(await db.table(_table).count(), 2);
      });

      test('createOrFirst inserts, then returns the existing row', () async {
        final created =
            await db.table(_table).createOrFirst({'nome': 'Lei'}, {'valor': 1});
        expect(created['nome'], 'Lei');
        expect(created['valor'], 1);
        expect(created['id'], isNotNull);

        final again =
            await db.table(_table).createOrFirst({'nome': 'Lei'}, {'valor': 2});
        expect(again['id'], created['id']);
        expect(again['valor'], 1);
        expect(await db.table(_table).count(), 1);
      });

      test('createOrFirst in a transaction keeps it usable', () async {
        await db.table(_table).insert({'nome': 'Lei', 'valor': 1});
        await db.transaction((ctx) async {
          final row = await ctx.table(_table).createOrFirst({'nome': 'Lei'});
          expect(row['valor'], 1);
          await ctx.table(_table).insert({'nome': 'Portaria'});
        });
        expect(await db.table(_table).count(), 2);
      });

      test('createOrFirst in a transactionScope through db', () async {
        await db.table(_table).insert({'nome': 'Lei', 'valor': 1});
        await db.transactionScope((_) async {
          final row = await db.table(_table).createOrFirst({'nome': 'Lei'});
          expect(row['valor'], 1);
          await db.table(_table).insert({'nome': 'Portaria'});
        });
        expect(await db.table(_table).count(), 2);
      });

      test('createOrFirst rethrows when no row matches the attributes',
          () async {
        if (!isPg) return; // MySQL's collation already ignores the case.
        await db.table(_table).insert({'nome': 'Lei'});
        // The index refuses ' LEI ', but no row has exactly that name.
        await expectLater(db.table(_table).createOrFirst({'nome': ' LEI '}),
            throwsA(isA<UniqueConstraintViolationException>()));
      });

      test('firstOrCreate', () async {
        final created =
            await db.table(_table).firstOrCreate({'nome': 'Lei'}, {'valor': 1});
        final found =
            await db.table(_table).firstOrCreate({'nome': 'Lei'}, {'valor': 2});
        expect(found['id'], created['id']);
        expect(found['valor'], 1);
        expect((await db.table2(_table).firstOrCreate({'nome': 'Lei'}))['id'],
            created['id']);
      });

      test('concurrent createOrFirst insert each row once', () async {
        for (var i = 0; i < 5; i++) {
          final rows = await Future.wait([
            db.table(_table).createOrFirst({'nome': 'n$i'}),
            other.table(_table).createOrFirst({'nome': 'n$i'}),
          ]);
          expect(rows[0]['id'], rows[1]['id']);
        }
        expect(await db.table(_table).count(), 5);
      });

      if (isPg) {
        test('advisoryLock serializes the transactions with the same key',
            () async {
          final events = <String>[];
          final held = Completer<void>();
          final release = Completer<void>();
          final first = db.transaction((ctx) async {
            await ctx.advisoryLock('normas.tipo_norma');
            events.add('first locked');
            held.complete();
            await release.future;
            events.add('first commit');
          });
          await held.future;

          final second = other.transaction((ctx) async {
            expect(await ctx.tryAdvisoryLock('normas.tipo_norma'), isFalse);
            // Other keys are free.
            expect(await ctx.tryAdvisoryLock('normas.outra'), isTrue);
            expect(await ctx.tryAdvisoryLock(42), isTrue);
            await ctx.advisoryLock('normas.tipo_norma');
            events.add('second locked');
          });
          await Future<void>.delayed(const Duration(milliseconds: 300));
          expect(events, ['first locked']);
          release.complete();
          await Future.wait([first, second]);
          expect(events, ['first locked', 'first commit', 'second locked']);

          // Released with the transaction.
          await other.transaction((ctx) async {
            expect(await ctx.tryAdvisoryLock('normas.tipo_norma'), isTrue);
          });
        });

        test('advisoryLock needs a transaction', () async {
          expect(() => db.advisoryLock('k'), throwsStateError);
          expect(() => db.tryAdvisoryLock('k'), throwsStateError);
          await db.transaction((ctx) async {
            expect(() => ctx.advisoryLock(1.5), throwsArgumentError);
          });
        });

        test('advisoryLock through db in a transactionScope', () async {
          await db.transactionScope((_) async {
            await db.advisoryLock('scope');
            await other.transaction((ctx) async {
              expect(await ctx.tryAdvisoryLock('scope'), isFalse);
            });
          });
        });

        test('lockTable blocks a conflicting lock, not plain reads', () async {
          await db.table(_table).insert({'nome': 'Lei'});
          final held = Completer<void>();
          final release = Completer<void>();
          final first = db.transaction((ctx) async {
            await ctx.table(_table).lockTable(TableLockMode.exclusive);
            held.complete();
            await release.future;
          });
          await held.future;
          try {
            // EXCLUSIVE lets ACCESS SHARE (a plain select) through.
            await other.transaction((ctx) async {
              expect(await ctx.table(_table).count(), 1);
            });
            await expectLater(
                other.transaction((ctx) => ctx
                    .table(_table)
                    .lockTable(TableLockMode.share, noWait: true)),
                throwsA(predicate((e) => '$e'.contains('55P03'))));
          } finally {
            release.complete();
            await first;
          }
          await db.transaction((ctx) => ctx
              .table2(_table)
              .lockTable(TableLockMode.accessExclusive, noWait: true));
        });
      } else {
        test('advisoryLock and lockTable are PostgreSQL only', () async {
          await db.transaction((ctx) async {
            expect(
                () => ctx.advisoryLock('k'), throwsA(isA<UnsupportedError>()));
            expect(() => ctx.table(_table).lockTable(TableLockMode.share),
                throwsA(isA<UnsupportedError>()));
          });
        });
      }
    });
  }
}
