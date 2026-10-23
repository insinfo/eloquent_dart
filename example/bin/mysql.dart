// MySQL / MariaDB: the same query builder, models and transactions.
//
//   dart run bin/mysql.dart
import 'package:eloquent/eloquent.dart';
import 'package:example_eloquent/config.dart';

Future<void> main() async {
  final manager = Manager();
  manager.addConnection({
    ...mysqlConfig(),
    // 'sslmode': 'require',
    'pool': true,
    'poolsize': 4,
  });
  final db = await manager.connection();

  final schema = db.getSchemaBuilder();
  await schema.dropIfExists('ex_contacts');
  await schema.dropIfExists('ex_clients');
  await schema.create('ex_clients', (Blueprint t) {
    t.increments('id');
    t.string('name', 80);
    t.string('email', 120);
    t.unique('email');
  });
  await schema.create('ex_contacts', (Blueprint t) {
    t.integer('client_id');
    t.string('phone', 20);
  });

  final anaId = await db
      .table('ex_clients')
      .insertGetId({'name': 'Ana', 'email': 'ana@example.com'});
  final joaoId = await db
      .table('ex_clients')
      .insertGetId({'name': 'João', 'email': 'joao@example.com'});
  await db.table('ex_contacts').insert({'client_id': anaId, 'phone': '2777'});
  await db.table('ex_contacts').insert({'client_id': joaoId, 'phone': '9970'});

  final rows = await db
      .table('ex_clients as c')
      .select(['c.id', 'c.name', 'ct.phone'])
      .join('ex_contacts as ct', 'ct.client_id', '=', 'c.id')
      .orderBy('c.id')
      .get();
  print('joined: $rows');

  // INSERT ... ON DUPLICATE KEY UPDATE
  await db.table('ex_clients').upsert(
    [
      {'email': 'ana@example.com', 'name': 'Ana Paula'},
      {'email': 'bia@example.com', 'name': 'Bia'},
    ],
    ['email'],
  );
  await db
      .table('ex_clients')
      .insertOrIgnore({'email': 'bia@example.com', 'name': 'ignored'});
  print('clients: ${await db.table('ex_clients').orderBy('id').pluck('name')}');

  // Transactions and savepoints (MySQL recovers from an SQL error in one)
  await db.transaction((ctx) async {
    await ctx.table('ex_clients').where('id', '=', anaId).update({'name': 'A'});
    try {
      await ctx.transaction((nested) async {
        await nested
            .table('ex_clients')
            .insert({'name': 'dup', 'email': 'bia@example.com'});
      });
    } on UniqueConstraintViolationException catch (e) {
      print('savepoint rolled back: ${e.constraint}');
    }
  });

  // QueryBuilder2 works the same way
  final count = await db.table2('ex_clients').whereLike('name', 'a%').count();
  print('names starting with a: $count');

  // MySQL has no server-side cursor here: stream with lazyById
  await for (final row in db.table('ex_clients').lazyById(100)) {
    print('lazy: ${row['name']}');
  }

  await schema.drop('ex_contacts');
  await schema.drop('ex_clients');
  await db.disconnect();
}
