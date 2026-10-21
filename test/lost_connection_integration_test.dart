// The server ends the session (pg_terminate_backend / KILL): the next
// statement outside a transaction reconnects and runs, on every adapter with
// and without pool, and disconnect() still completes.
// Requires localhost:5432 / 3306, database `banco_teste`, dart/dart.
@Tags(['integration'])
library;

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
      test(
          '$driver${pool ? ' (pool)' : ''} reconnects after the session is '
          'terminated', () async {
        final mysql = driver == 'mysql';
        final manager = Manager()
          ..addConnection(_config(driver, pool), 'victim')
          ..addConnection(_config(driver, false), 'killer');
        final victim = await manager.getConnection('victim');
        final killer = await manager.getConnection('killer');

        Future<dynamic> pid() async => (await victim.select(mysql
                ? 'select connection_id() as pid'
                : 'select pg_backend_pid() as pid'))
            .first['pid'];

        final before = await pid();
        if (mysql) {
          await killer.execute('KILL $before');
        } else {
          await killer.select('select pg_terminate_backend(?::int)', [before]);
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));

        final after = await pid().timeout(const Duration(seconds: 20));
        expect(after, isNot(before), reason: 'a new session runs the query');
        expect(await victim.select('select 1 as one'), [
          {'one': 1}
        ]);

        // Used to hang on mysql_dart after the server closed the socket.
        await manager
            .getDatabaseManager()
            .purge('victim')
            .timeout(const Duration(seconds: 10));
        await manager.getDatabaseManager().purge('killer');
      });

      // Issue #2: the server closes a connection left idle (MySQL/MariaDB
      // wait_timeout, PostgreSQL 14+ idle_session_timeout); the next query
      // must reconnect instead of failing until the application restarts.
      test(
          '$driver${pool ? ' (pool)' : ''} reconnects after the server closes '
          'an idle connection', () async {
        final mysql = driver == 'mysql';
        final manager = Manager()..addConnection(_config(driver, pool), 'idle');
        final db = await manager.getConnection('idle');

        Future<dynamic> pid() async => (await db.select(mysql
                ? 'select connection_id() as pid'
                : 'select pg_backend_pid() as pid'))
            .first['pid'];

        final before = await pid();
        await db.execute(mysql
            ? 'set session wait_timeout = 1'
            : "set idle_session_timeout = '1s'");
        await Future<void>.delayed(const Duration(seconds: 3));

        final after = await pid().timeout(const Duration(seconds: 20));
        expect(after, isNot(before), reason: 'a new session runs the query');
        expect(await db.select('select 1 as one'), [
          {'one': 1}
        ]);

        await manager
            .getDatabaseManager()
            .purge('idle')
            .timeout(const Duration(seconds: 10));
      });
    }
  }
}
