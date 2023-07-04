import 'dart:async';

import 'package:eloquent/eloquent.dart';

void main(List<String> args) async {
  var manager = new Manager();
  manager.addConnection({
    'driver': 'pgsql',
    'host': 'localhost',
    'port': '5433',
    'database': 'sistemas',
    'username': 'sisadmin',
    'password': 's1sadm1n',
    'charset': 'utf8',
    'prefix': '',
    'schema': ['myschema'],
    //'sslmode' => 'prefer',
  });

  manager.setAsGlobal();

  final db = await manager.connection();

  Timer.periodic(Duration(milliseconds: 2000), (timer) async{ 
    var res = await db.table('temp_location').select().get();
    print('Timer.periodic $res');
  });
}
