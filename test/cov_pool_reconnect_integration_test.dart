// 'pool_reconnect' with 'pool': true: 'keep' (the default) leaves a lost
// connection to the pool, which discards it, so the statements other
// requests run on the pool are not affected; 'replace' closes the pool and
// makes a new one. Requires localhost:5432 / 3306, database `banco_teste`,
// dart/dart.
@Tags(['integration'])
library;

import 'dart:async';

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

Map<String, dynamic> _config(String driver,
        {bool pool = true, String? poolReconnect}) =>
    {
      if (driver == 'mysql') ...{
        'driver': 'mysql',
        'port': '3306',
      } else ...{
        'driver': 'pgsql',
        'driver_implementation': driver,
        'port': '5432',
        'charset': 'utf8',
        'schema': ['public'],
      },
      'host': 'localhost',
      'database': 'banco_teste',
      'username': 'dart',
      'password': 'dart',
      'pool': pool,
      'poolsize': 2,
      if (poolReconnect != null) 'pool_reconnect': poolReconnect,
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
      final mysql = driver == 'mysql';
      late Manager manager;
      late Connection killer;

      String sleep(String marker) => mysql
          ? "select sleep(1.5) as s, '$marker' as m"
          : "select pg_sleep(1.5) as s, '$marker' as m";

      /// Ends the server session running the statement marked [marker].
      Future<void> killRunning(String marker) async {
        for (var i = 0; i < 50; i++) {
          final rows = await killer.select(mysql
              ? 'select id from information_schema.processlist '
                  "where info like '%$marker%' and info not like '%processlist%'"
              : 'select pid as id from pg_stat_activity '
                  "where query like '%$marker%' and pid <> pg_backend_pid()");
          if (rows.isNotEmpty) {
            final id = rows.first['id'];
            if (mysql) {
              await killer.execute('KILL $id');
            } else {
              await killer.select('select pg_terminate_backend(?::int)', [id]);
            }
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        fail('no session runs $marker');
      }

      Future<dynamic> sessionId(Connection db) async => (await db.select(mysql
              ? 'select connection_id() as id'
              : 'select pg_backend_pid() as id'))
          .first['id'];

      setUp(() async {
        manager = Manager()
          ..addConnection(_config(driver, pool: false), 'killer');
        killer = await manager.getConnection('killer');
      });

      tearDown(() async {
        for (final name in ['keep', 'replace', 'killer']) {
          await manager
              .getDatabaseManager()
              .purge(name)
              .timeout(const Duration(seconds: 10));
        }
      });

      test('keep: a lost connection does not fail the others', () async {
        manager.addConnection(_config(driver), 'keep');
        final db = await manager.getConnection('keep');
        final pool = db.pdo.pdoInstance;
        final marker =
            'cov_pr_${driver}_${DateTime.now().microsecondsSinceEpoch}';

        // Expected before the kill: the statement fails while killRunning
        // still runs, and an error nobody listens to yet is uncaught.
        final victim =
            expectLater(db.select(sleep('${marker}_a')), throwsA(anything));
        final other = db.select(sleep('${marker}_b'));
        await killRunning('${marker}_a');

        await victim;
        expect((await other).single['m'], '${marker}_b',
            reason: 'the other statement on the pool finished');
        expect(identical(db.pdo.pdoInstance, pool), isTrue,
            reason: 'the pool was kept');
        expect(await db.selectOne('select 1 as one'), {'one': 1});
      });

      test(
          'keep: an idle connection ended by the server is replaced by the '
          'pool', () async {
        manager.addConnection(_config(driver, poolReconnect: 'keep'), 'keep');
        final db = await manager.getConnection('keep');
        final pool = db.pdo.pdoInstance;
        final id = await sessionId(db);
        if (mysql) {
          await killer.execute('KILL $id');
        } else {
          await killer.select('select pg_terminate_backend(?::int)', [id]);
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));

        for (var i = 0; i < 4; i++) {
          expect(
              await db
                  .selectOne('select $i as n')
                  .timeout(const Duration(seconds: 20)),
              {'n': i});
        }
        expect(identical(db.pdo.pdoInstance, pool), isTrue);
      });

      test('replace: a lost connection replaces the pool', () async {
        manager.addConnection(
            _config(driver, poolReconnect: 'replace'), 'replace');
        final db = await manager.getConnection('replace');
        final pool = db.pdo.pdoInstance;
        final marker =
            'cov_pr_${driver}_${DateTime.now().microsecondsSinceEpoch}';

        final victim =
            expectLater(db.select(sleep('${marker}_a')), throwsA(anything));
        await killRunning('${marker}_a');
        await victim;
        expect(identical(db.pdo.pdoInstance, pool), isFalse,
            reason: 'a new pool');
        expect(await db.selectOne('select 1 as one'), {'one': 1});
      });

      test('an unknown pool_reconnect throws ArgumentError', () async {
        manager.addConnection(_config(driver, poolReconnect: 'swap'), 'keep');
        await expectLater(
            manager.getConnection('keep'), throwsA(isA<ArgumentError>()));
      });
    });
  }
}
