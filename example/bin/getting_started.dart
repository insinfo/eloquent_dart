// Connect, create a table, write and read rows, disconnect.
//
//   dart run bin/getting_started.dart
import 'package:eloquent/eloquent.dart';
import 'package:example_eloquent/config.dart';

Future<void> main() async {
  final manager = Manager();
  // postgresConfig() is a map with driver, host, port, database, username,
  // password, charset and schema; see lib/config.dart and
  // bin/connection_options.dart for every setting.
  manager.addConnection(postgresConfig());
  // Makes this manager reachable through Manager.instance.
  manager.setAsGlobal();

  final db = await manager.connection();

  final schema = db.getSchemaBuilder();
  await schema.dropIfExists('ex_contacts');
  await schema.create('ex_contacts', (Blueprint t) {
    t.increments('id');
    t.string('name', 80);
    t.string('city', 80);
    t.nullable();
    t.boolean('active');
    t.defaultTo(true);
    t.timestamps();
  });

  // insert / insertGetId
  await db.table('ex_contacts').insert({'name': 'Ana', 'city': 'Niterói'});
  await db.table('ex_contacts').insert({'name': 'Bruno', 'city': 'Macaé'});
  final id = await db.table('ex_contacts').insertGetId({
    'name': 'Carla',
    'city': 'Rio das Ostras',
    'created_at': DateTime.now()
  });
  print('inserted id: $id');

  // select
  final rows = await db
      .table('ex_contacts')
      .select(['id', 'name', 'city'])
      .where('active', '=', true)
      .orderBy('name')
      .get();
  print('contacts: $rows');

  final carla = await db.table('ex_contacts').where('id', '=', id).first();
  print('first: $carla');

  // update / delete return the number of affected rows
  final updated = await db
      .table('ex_contacts')
      .where('name', '=', 'Bruno')
      .update({'city': 'Cabo Frio', 'updated_at': DateTime.now()});
  final deleted =
      await db.table('ex_contacts').where('name', '=', 'Ana').delete();
  print('updated: $updated, deleted: $deleted');

  print('count: ${await db.table('ex_contacts').count()}');

  // Raw SQL with bindings
  final raw = await db.select(
      'select name, city from ex_contacts where city = ?', ['Cabo Frio']);
  print('raw select: $raw');

  await schema.drop('ex_contacts');
  await db.disconnect();
}
