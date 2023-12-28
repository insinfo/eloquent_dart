import 'dart:io';

import 'package:eloquent/eloquent.dart';

void main(List<String> args) async {
  final manager = Manager();
  manager.addConnection({
    'driver': 'pgsql',
    'host': 'localhost',
    'port': '5435',
    'database': 'siamweb',
    'username': 'dart',
    'password': 'dart',
    'charset': 'win1252',
    'prefix': '',
    'schema': ['public'],
    //'sslmode' : 'require',
  });

  manager.setAsGlobal();

  final db = await manager.connection();

  final res = await db.transaction((ctx) async {
    await ctx.table('test_table').insert({'id':10,'name':'Jane Doe'});
    final res = await ctx.table('test_table').limit(2).get();
    return res;
  });

  print('res $res');
  exit(0);
}
