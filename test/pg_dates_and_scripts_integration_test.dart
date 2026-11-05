// What every PostgreSQL adapter does with dates DateTime cannot represent, and
// with scripts of several statements that return rows. The postgres package
// turned the first into a wrong date or an error no caller can catch, and the
// second into the same kind of error: such an error ends the process by default.
//
// Connection: localhost:5432 db=banco_teste user/pass=dart.

@Tags(['integration'])
library;

import 'dart:async';

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

const _drivers = ['postgres', 'postgres_v3', 'dargres', 'dpgsql'];

/// Runs [body] on a new connection, and fails on any uncaught error.
Future<void> _withDb(String driver, bool pool, Map<String, dynamic> extra,
    Future<void> Function(Connection db) body) async {
  final uncaught = <Object>[];
  final finished = Completer<void>();
  runZonedGuarded(() async {
    final manager = Manager()
      ..addConnection({
        'driver': 'pgsql',
        'driver_implementation': driver,
        'host': 'localhost',
        'port': '5432',
        'database': 'banco_teste',
        'username': 'dart',
        'password': 'dart',
        if (pool) 'pool': true,
        if (pool) 'poolsize': 1,
        ...extra,
      }, 'c');
    try {
      await body(await manager.connection('c'));
      // Errors that escape arrive right after the call.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      finished.complete();
    } catch (e, s) {
      finished.completeError(e, s);
    } finally {
      try {
        await manager.getDatabaseManager().purge('c');
      } catch (_) {}
    }
  }, (e, s) => uncaught.add(e));
  await finished.future;
  expect(uncaught, isEmpty, reason: 'uncaught errors');
}

Future<Object?> _value(Connection db, String expression) async =>
    (await db.selectOne('select $expression as v'))?['v'];

void main() {
  for (final driver in _drivers) {
    for (final pool in [false, true]) {
      group('$driver${pool ? ' pool' : ''}', () {
        test('infinity is null', () async {
          await _withDb(driver, pool, {}, (db) async {
            for (final value in [
              "'infinity'::date",
              "'-infinity'::date",
              "'infinity'::timestamp",
              "'-infinity'::timestamp",
              "'infinity'::timestamptz",
              "'-infinity'::timestamptz",
            ]) {
              expect(await _value(db, value), isNull, reason: value);
            }
            // The connection goes on.
            expect(await _value(db, '1'), 1);
          });
        });

        test('dates DateTime can represent keep their value', () async {
          await _withDb(driver, pool, {}, (db) async {
            expect(await _value(db, "'2024-03-01'::date"),
                DateTime.utc(2024, 3, 1));
            expect(await _value(db, "'1969-12-31'::date"),
                DateTime.utc(1969, 12, 31));
            expect(await _value(db, "'2024-03-01 12:34:56.123456'::timestamp"),
                DateTime.utc(2024, 3, 1, 12, 34, 56, 123, 456));
            expect(await _value(db, "'2024-03-01 12:00:00+00'::timestamptz"),
                DateTime.utc(2024, 3, 1, 12));
            expect(await _value(db, "'0044-03-15 BC'::date"),
                DateTime.utc(-43, 3, 15));
            expect(await _value(db, "null::date"), isNull);
          });
        });

        test('a script with two selects runs, and the connection goes on',
            () async {
          await _withDb(driver, pool, {}, (db) async {
            await db.execute('select 1 as a; select 2 as b');
            await db.execute("select 1 as a; select 'x'::text as b, 2 as c");
            expect(await _value(db, '1'), 1);
          });
        });

        test('a script inside a transaction', () async {
          await _withDb(driver, pool, {}, (db) async {
            await db.transaction((ctx) async {
              await ctx.execute('select 1 as a; select 2 as b');
              expect((await ctx.selectOne('select 3 as v'))?['v'], 3);
            });
          });
        });

        test('execute counts the rows of a command', () async {
          await _withDb(driver, pool, {}, (db) async {
            await db.execute(
                'create temporary table p_scripts (id int); '
                'insert into p_scripts values (1)');
          });
        });
      });
    }
  }

  // The driver's own types: infinity must not end the process there either.
  test('postgres_v3 with pg_types driver', () async {
    await _withDb('postgres_v3', false, {'pg_types': 'driver'}, (db) async {
      expect(await _value(db, "'infinity'::timestamp"), isNull);
      expect(await _value(db, "'infinity'::date"), isNull);
      expect(await _value(db, "'2024-03-01'::date"), DateTime.utc(2024, 3, 1));
    });
  });

  test('postgres_v3 arrays of dates', () async {
    await _withDb('postgres_v3', false, {}, (db) async {
      expect(await _value(db, "array['infinity'::date, null, '2024-03-01'::date]"),
          [null, null, DateTime.utc(2024, 3, 1)]);
      expect(
          await _value(db, "array['infinity'::timestamp, '2024-03-01 12:00'::timestamp]"),
          [null, DateTime.utc(2024, 3, 1, 12)]);
      expect(await _value(db, "array['2024-03-01 12:00+00'::timestamptz]"),
          [DateTime.utc(2024, 3, 1, 12)]);
      expect(await _value(db, "'{}'::date[]"), isEmpty);
      expect(
          await _value(db,
              "array[array['2024-03-01'::date], array['2024-03-02'::date]]"),
          [
            [DateTime.utc(2024, 3, 1)],
            [DateTime.utc(2024, 3, 2)]
          ]);
    });
  });
}
