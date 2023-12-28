import 'dart:io';

import 'package:eloquent/eloquent.dart';

void main(List<String> args) async {
  for (var i = 0; i < 1000000; i++) {
    final stopwatch = new Stopwatch()..start();
    final db = await getConn();
    final res = await db.table('test_table').select(['name']).limit(1).get();
     db.disconnect();
    print('executed in ${stopwatch.elapsed.inMilliseconds}ms');
    print('res $res');
    //await Future.delayed(Duration(milliseconds: 1000));
  }

  exit(0);
}

Future<Connection> getConn() async {
  final manager = Manager();
  manager.addConnection({
    'driver': 'pgsql',
    'driver_implementation': 'postgres_v3',
    'host': 'localhost',
    'port': '5435',
    'database': 'siamweb',
    'username': 'dart',
    'password': 'dart',
    'charset': 'win1252',
    'prefix': '',
    'schema': ['public'],
    //'sslmode' : 'require',
    // 'pool': true,
    // 'poolsize': 50,
  });
  manager.setAsGlobal();
  final db = await manager.connection();
  return db;
}
