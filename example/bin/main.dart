import 'dart:io';

import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/query/join_clause.dart';

void main(List<String> args) async {
  var manager = new Manager();
  manager.addConnection({
    'driver': 'pgsql',
    'host': 'localhost',
    'port': '5432',
    'database': 'sistemas',
    'username': 'postgres',
    'password': 's1sadm1n',
    'charset': 'utf8',
    'prefix': '',
    'schema': ['public'],
    //'sslmode' => 'prefer',
  });

  manager.setAsGlobal();

  final db = await manager.connection();

  await db.select('DROP SCHEMA IF EXISTS myschema CASCADE;');
  await db.select('CREATE SCHEMA IF NOT EXISTS myschema;');
  await db.select('SET search_path TO myschema;');

  await db.select('''CREATE TABLE "temp_location" ( 
          id int4,
          city VARCHAR(80),
          street VARCHAR(80)
        );''');

  var query = db.table('temp_location');
  var res = await query
      .insert({'id': 1, 'city': 'Rio de Janeiro', 'street': 'Rua R'});

  //await db.transaction((ctx) async {
  // var query = db.table('table_01');
  // var res = await query.insert({'name': 'Teste', 'test2': 'descrição'});
  //var res = await query.insertGetId({'name': 'Teste', 'test': 'descrição'});
  //var res = await query.where('id','=',12).update({'name': 'Teste up', 'test': 'descrição up'});
  //print(res);
  // query.select();
  // query.join('table_02', 'table_02.idtb1','=','table_01.id');
  // query.join('table_02', (JoinClause q) {
  //   q.on('table_02.idtb1', '=', 'table_01.id');
  // });
  //query.join('table_02', 'table_02.idtb1', 'in', db.raw('(10,11)'));
  //query.join('table_02', 'table_02.idtb1', 'in', '(10,11)');

  // query.select(['idsolicitante', 'email']);
  //query.where('idsolicitante', '>', 100);
  // query.limit(1);
  //query.orderBy('id','desc');
  // query.orWhere('idsolicitante', '=', 3);
  // query.offset(0);
  // query.limit(1);
  // query.orderBy('idsolicitante');
  // query.orWhereIn('idsolicitante', [5, 6]);
  //var res = await query.get();
  print('res: $res');
  //});
  print('fim');
  exit(0);
}
