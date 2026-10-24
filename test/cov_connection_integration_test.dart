// A write is run again after a lost connection only when the adapter refused
// it before sending it (the server had already closed the idle session);
// a write lost in flight fails instead of running twice. outsideTransaction()
// refuses a pool of one connection inside a transactionScope.
// Requires localhost:5432 / 3306, database `banco_teste`, dart/dart.
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
        'poolsize': 1,
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
        'poolsize': 1,
      };

void main() {
  for (final driver in [
    'postgres',
    'postgres_v3',
    'dargres',
    'dpgsql',
    'mysql'
  ]) {
    for (final pool in [false, true]) {
      group('$driver${pool ? ' (pool)' : ''}', () {
        final mysql = driver == 'mysql';
        final table = 'cov_cx_writes_${driver}_${pool ? 'pool' : 'single'}';
        late Manager manager;
        late Connection victim;
        late Connection killer;

        Future<dynamic> pid() async => (await victim.select(mysql
                ? 'select connection_id() as pid'
                : 'select pg_backend_pid() as pid'))
            .first['pid'];

        Future<void> kill(dynamic id) async {
          if (mysql) {
            await killer.execute('KILL $id');
          } else {
            await killer.select('select pg_terminate_backend(?::int)', [id]);
          }
        }

        Future<int> count() async =>
            (await killer.select('select count(*) as n from $table')).first['n']
                as int;

        setUp(() async {
          manager = Manager()
            ..addConnection(_config(driver, pool), 'victim')
            ..addConnection(_config(driver, false), 'killer');
          victim = await manager.getConnection('victim');
          killer = await manager.getConnection('killer');
          await killer.execute('drop table if exists $table');
          await killer.execute('create table $table (id int)');
        });

        tearDown(() async {
          await killer.execute('drop table if exists $table');
          await manager
              .getDatabaseManager()
              .purge('victim')
              .timeout(const Duration(seconds: 10));
          await manager.getDatabaseManager().purge('killer');
        });

        test('a write after the server ended the idle session runs once',
            () async {
          await kill(await pid());
          await Future<void>.delayed(const Duration(milliseconds: 300));

          await victim
              .table(table)
              .insert({'id': 1}).timeout(const Duration(seconds: 20));
          expect(await count(), 1);
        });

        test('a write lost in flight is not run again', () async {
          final id = await pid();
          // Handled at once: the error may come while the killer runs.
          final outcome = victim
              .insert(mysql
                  ? 'insert into $table (id) select 1 from (select sleep(2)) s'
                  : 'insert into $table (id) select 1 from pg_sleep(2)')
              .then<Object>((_) => 'ran', onError: (Object e) => e);
          await Future<void>.delayed(const Duration(milliseconds: 400));
          await kill(id);

          expect(
              await outcome.timeout(const Duration(seconds: 20)), isNot('ran'),
              reason: 'the lost insert fails instead of running again');
          expect(await count(), lessThanOrEqualTo(1),
              reason: 'the insert ran at most once');

          // Reconnected: the next statement works.
          final before = await count();
          await victim.table(table).insert({'id': 2});
          expect(await count(), before + 1);
        });

        if (!pool) {
          test('a write after an idle-session timeout runs once', () async {
            await victim.execute(mysql
                ? 'set session wait_timeout = 1'
                : "set idle_session_timeout = '1s'");
            await Future<void>.delayed(const Duration(milliseconds: 2500));

            await victim
                .table(table)
                .insert({'id': 1}).timeout(const Duration(seconds: 20));
            expect(await count(), 1);
          });
        }

        if (pool) {
          test('outsideTransaction() in a scope refuses a pool of one',
              () async {
            await expectLater(
                victim
                    .transactionScope((ctx) => victim.outsideTransaction(
                        () => victim.select('select 1 as one')))
                    .timeout(const Duration(seconds: 5)),
                throwsA(isA<StateError>()));
          });
        }
      });
    }
  }
}
