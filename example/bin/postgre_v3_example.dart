import 'dart:io';

import 'package:eloquent/eloquent.dart';

void main(List<String> args) async {
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
    'pool': true,
    'poolsize': 50,
  });

  manager.setAsGlobal();

  final db = await manager.connection();
 
  await db.execute('DROP TABLE public.test_table');
  await db.execute(
      '''CREATE TABLE public.test_table ( id int4 NOT NULL, name char(255) );''');

  final res = await db.transaction((ctx) async {
    await ctx.table('test_table').insert({'id': 11, 'name': 'Jane Doe'});
    final res = await ctx.table('test_table').limit(1).get();
    return res;
  });

  print('res $res');

  for (var i = 0; i < 1000000; i++) {
    final stopwatch = new Stopwatch()..start();
    final res = await db.table('test_table').select(['name']).limit(1).get();

    print('executed in ${stopwatch.elapsed.inMilliseconds}ms');
    print('res $res');
    //await Future.delayed(Duration(milliseconds: 1000));
  }

  exit(0);
}
