// Connection settings, the four PostgreSQL drivers, pools, named
// connections and closing connections.
//
//   dart run bin/connection_options.dart
import 'package:eloquent/eloquent.dart';
import 'package:example_eloquent/config.dart';

/// Every setting of a PostgreSQL connection, with its default.
Map<String, dynamic> allSettings() => {
      'driver': 'pgsql',
      // postgres | postgres_v3 | dargres | dpgsql
      'driver_implementation': 'postgres_v3',
      'host': 'localhost',
      'port': '5432',
      'database': 'banco_teste',
      'username': 'dart',
      'password': 'dart',
      'charset': 'utf8',
      // table prefix added by the query builder
      'prefix': '',
      // search_path; a list or 'public,other'
      'schema': ['public'],
      // require | disable
      // 'sslmode': 'require',
      // a pool of up to `poolsize` connections
      'pool': false,
      'poolsize': 8,
      // session time zone (default UTC)
      'timezone': 'America/Sao_Paulo',
      // how timestamptz / timestamp / date are decoded: true = UTC,
      // false = in the session time zone (timestamptz) or local (the others)
      'forceDecodeTimestamptzAsUTC': true,
      'forceDecodeTimestampAsUTC': true,
      'forceDecodeDateAsUTC': true,
      // 'uniform': the same Dart types on the four drivers (numeric as
      // String, arrays as List, json decoded); 'driver': each driver's types
      'pg_types': 'uniform',
      // 'string': DateTime bindings sent as 'yyyy-MM-dd HH:mm:ss';
      // 'native': sent as DateTime (keeps microseconds and the UTC instant)
      'datetime_bindings': 'string',
      // settings passed to the driver as they are; an unknown key throws
      // 'driver_options': {'statementCacheCapacity': 256},
    };

Future<void> main() async {
  // The same query on every PostgreSQL driver returns the same Dart types
  for (final driver in ['postgres', 'postgres_v3', 'dargres', 'dpgsql']) {
    final manager = Manager()
      ..addConnection({...allSettings(), ...postgresConfig(driver: driver)});
    final db = await manager.connection();
    final row = await db
        .selectOne("select 150.50::numeric as price, array[1, 2] as ids, "
            "'{\"a\": 1}'::jsonb as data, now() as at");
    print('$driver: ${row!.map((k, v) => MapEntry(k, v.runtimeType))}');
    await db.disconnect();
  }

  // Several named connections in one manager (PostgreSQL and MySQL here)
  final manager = Manager();
  manager.addConnection(postgresConfig()); // 'default'
  manager.addConnection(
      {...postgresConfig(driver: 'dpgsql'), 'pool': true, 'poolsize': 4},
      'reports');
  manager.addConnection(mysqlConfig(), 'legacy');
  // Manager.instance points to it from anywhere in the application
  manager.setAsGlobal();

  final primary = await manager.connection(); // the default
  final reports = await Manager.instance!.connection('reports');
  final legacy = await manager.connection('legacy');
  final database = await primary.selectOne('select current_database() as d');
  print('default: ${database!['d']}');
  print('legacy: ${await legacy.selectOne('select version() as v')}');

  // Queries running at the same time take different pooled connections
  final pids = await Future.wait([
    for (var i = 0; i < 4; i++)
      reports.selectOne('select pg_backend_pid() as pid, pg_sleep(0.1)'),
  ]);
  print('reports pool backends: ${pids.map((r) => r!['pid']).toSet()}');

  // purge() closes a connection and forgets it; the next connection(name)
  // opens a new one
  await manager.getDatabaseManager().purge('legacy');
  for (final name in ['default', 'reports']) {
    await manager.getDatabaseManager().purge(name);
  }
}
