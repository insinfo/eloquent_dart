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
    //'sslmode' => 'prefer',
  });

  manager.setAsGlobal();

  final db = await manager.connection();
  // final res = await db.table('test_table').limit(1).get();
  await db.execute('DROP TABLE public.test_table');
  await db.execute('''CREATE TABLE public.test_table ( id int4 NOT NULL, name char(255) );''');

  final res = await db.transaction((ctx) async {
    await ctx.table('test_table').insert({'id': 11, 'name': 'Jane Doe'});
    final res = await ctx.table('test_table').limit(1).get();
    return res;
  });

  print('res $res');

  exit(0);
}
