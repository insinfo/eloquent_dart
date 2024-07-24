import 'dart:io';

import 'package:eloquent/eloquent.dart';

void main(List<String> args) async {
  final manager = Manager();
  manager.addConnection({
    'driver': 'pgsql',
    'driver_implementation': 'postgres_v3', // postgres | dargres | postgres_v3
    'timezone': 'America/Sao_Paulo',   
    'forceDecodeTimestamptzAsUTC': false,
    'forceDecodeTimestampAsUTC': false,
    'forceDecodeDateAsUTC': false,
    'pool': true,
    'poolsize': 2,
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

  final connection = await manager.connection();

  var results =
      await connection.select("select current_timestamp, current_date ");
  print('results: ${results}');
  var currentTimestamp = results.first['current_timestamp'] as DateTime;
  print('dafault: $currentTimestamp ${currentTimestamp.timeZoneName}');
  print('local: ${currentTimestamp.toLocal()}');

  // await connection.execute("set timezone to 'America/Sao_Paulo'");
  // results = await connection.execute("select current_timestamp");
  // currentTimestamp = results.first.first as DateTime;
  // print(
  //     'America/Sao_Paulo: $currentTimestamp ${currentTimestamp.timeZoneName}');

  // final res = await db.transaction((ctx) async {
  //   await ctx.table('test_table').insert({'id':10,'name':'Jane Doe'});
  //   final res = await ctx.table('test_table').limit(2).get();
  //   return res;
  // });
  // print('res $res');

  exit(0);
}
