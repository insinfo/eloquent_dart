// QueryBuilder2 (`db.table2()`): the Dart 3 API. Values are always bound,
// operators are enums, columns are identifiers and results are typed.
//
//   dart run bin/query_builder2.dart
import 'package:eloquent/eloquent.dart';
import 'package:example_eloquent/config.dart';

Future<void> main() async {
  final manager = postgresManager();
  final db = await manager.connection();
  await _createTables(db);

  await db.table2('ex_users').insertMany([
    {'name': 'Ana', 'age': 34, 'city': 'Niterói', 'role': 'admin'},
    {'name': 'Bruno', 'age': 17, 'city': 'Macaé', 'role': 'operator'},
    {'name': 'Carla', 'age': 52, 'city': 'Rio das Ostras', 'role': 'guest'},
    {'name': 'Davi', 'age': 25, 'city': 'Macaé', 'role': 'operator'},
  ]);

  // Filters: where(column, value) is always `column = ?`
  String? role = 'operator';
  final users = await db
      .table2('ex_users')
      .select(['id', 'name', 'age'])
      .where('age', 18, operator: ComparisonOperator.greaterThanOrEqualTo)
      .whereIn('city', ['Macaé', 'Rio das Ostras'])
      .whereNull('deleted_at')
      .whereGroup((w) => w.where('city', 'Macaé').orWhere('age', 52))
      .whenNotNull(role, (q, r) => q.where('role', r))
      .orderBy('name')
      .get();
  print('users: $users');

  // Typed reads
  final names =
      await db.table2('ex_users').orderBy('name').pluck<String>('name');
  final adults =
      await db.table2('ex_users').whereGreaterThan('age', 17).count();
  final oldest = await db.table2('ex_users').orderByDescending('age').first();
  print('names: $names, adults: $adults, oldest: ${oldest?['name']}');

  // Pagination; toMap() is ready for a JSON response
  final page =
      await db.table2('ex_users').orderBy('id').paginate(page: 1, perPage: 2);
  print('page: ${page.toMap()}');

  // Insert returning the generated values
  final inserted = await db.table2('ex_users').insertReturning(
    {'name': 'Eva', 'age': 41, 'city': 'Niterói', 'role': 'guest'},
    returning: ['id', 'name'],
  );
  print('inserted: $inserted');

  // A per-year sequence without locks: insert or increment, read it back
  for (var i = 0; i < 3; i++) {
    final rows = await db.table2('ex_sequences').insertReturning(
          {'year': 2026, 'last': 1},
          onConflict: OnConflict.doUpdate(
              columns: ['year'],
              set: {'last': db.raw('ex_sequences.last + 1')}),
          returning: ['last'],
        );
    print('next number: ${rows.first['last']}');
  }

  // Upsert, insert-or-ignore and firstOrCreate on a unique key
  await db.table2('ex_stock').upsert([
    {'sku': 'A1', 'qty': 10},
    {'sku': 'B2', 'qty': 5},
  ], uniqueBy: [
    'sku'
  ], update: [
    'qty'
  ]);
  await db.table2('ex_stock').upsert([
    {'sku': 'A1', 'qty': 7},
  ], uniqueBy: [
    'sku'
  ], update: [
    'qty'
  ]);
  await db.table2('ex_stock').insertOrIgnore([
    {'sku': 'B2', 'qty': 99}, // ignored: B2 exists
  ]);
  final c3 =
      await db.table2('ex_stock').firstOrCreate({'sku': 'C3'}, {'qty': 1});
  print('stock: ${await db.table2('ex_stock').orderBy('sku').get()}, '
      'firstOrCreate: $c3');

  // Update and delete returning the changed rows
  final promoted = await db
      .table2('ex_users')
      .where('name', 'Davi')
      .updateReturning({'role': 'admin'}, returning: ['id', 'role']);
  final removed = await db
      .table2('ex_users')
      .whereLessThan('age', 18)
      .deleteReturning(returning: ['name']);
  print('promoted: $promoted, removed: $removed');

  // Recursive CTE: a sector and everything below it
  final tree = await db
      .table2('tree')
      .withRecursiveExpression(
        'tree',
        db.table2('ex_sectors').select(['id']).where('id', 1).unionAll(db
            .table2('ex_sectors as s')
            .select(['s.id']).join('tree as t', 't.id', 's.parent_id')),
        columns: ['id'],
      )
      .orderBy('id')
      .pluck<int>('id');
  print('sector 1 and its descendants: $tree');

  await _dropTables(db);
  await db.disconnect();
}

Future<void> _createTables(Connection db) async {
  await _dropTables(db);
  await db.unprepared('''
    create table ex_users (
      id serial primary key, name varchar(40), age int, city varchar(40),
      role varchar(20), deleted_at timestamp null);
    create table ex_sequences (year int primary key, last int not null);
    create table ex_stock (sku varchar(10) primary key, qty int not null);
    create table ex_sectors (id int primary key, parent_id int null);
    insert into ex_sectors values (1, null), (2, 1), (3, 2), (4, null), (5, 1);
  ''');
}

Future<void> _dropTables(Connection db) => db.unprepared(
    'drop table if exists ex_users, ex_sequences, ex_stock, ex_sectors');
