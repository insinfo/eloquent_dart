// orm_repository_integration_test.dart
//
// Integration tests (require a live PostgreSQL) for the lightweight
// Repository<T> / EntityMapper<T> data-mapper layer (Phase 8).
//
// Connection: localhost:5432 db=postgres user/pass=dart (dpgsql driver).

@Tags(['integration'])
library;

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

const _config = {
  'driver': 'pgsql',
  'driver_implementation': 'dpgsql',
  'host': '127.0.0.1',
  'port': '5432',
  'database': 'postgres',
  'username': 'dart',
  'password': 'dart',
  'schema': ['public'],
};

// --- Example entity + mapper (no code generation) ---

class User {
  int? id;
  String name;
  int age;
  User({this.id, required this.name, required this.age});
}

final userMapper = EntityMapper<User>(
  table: 'orm_users',
  fromRow: (r) => User(
    id: (r['id'] as num).toInt(),
    name: r['name'] as String,
    age: (r['age'] as num).toInt(),
  ),
  toRow: (u) => {'name': u.name, 'age': u.age},
  getId: (u) => u.id,
);

void main() {
  late Manager manager;
  late Connection db;
  late Repository<User> repo;

  setUp(() async {
    manager = Manager();
    manager.addConnection(Map<String, dynamic>.from(_config));
    manager.setAsGlobal();
    db = await manager.connection();
    repo = Repository<User>(db, userMapper);

    await db.execute('DROP TABLE IF EXISTS orm_users');
    await db.execute('''
      CREATE TABLE orm_users (
        id serial primary key,
        name text not null,
        age int not null
      )
    ''');
  });

  tearDown(() async {
    await db.execute('DROP TABLE IF EXISTS orm_users');
    await manager.getDatabaseManager().purge('default');
  });

  test('save inserts and returns the generated id; find hydrates', () async {
    final id = await repo.save(User(name: 'Ada', age: 30));
    expect(id, isNotNull);

    final found = await repo.find(id);
    expect(found, isNotNull);
    expect(found!.name, equals('Ada'));
    expect(found.age, equals(30));
  });

  test('save updates an existing entity', () async {
    final id = await repo.save(User(name: 'Bob', age: 25)) as int;
    final u = await repo.findOrFail(id);
    u.age = 26;
    await repo.save(u);

    expect((await repo.findOrFail(id)).age, equals(26));
  });

  test('findBy / all / count', () async {
    await repo.insert(User(name: 'A', age: 20));
    await repo.insert(User(name: 'B', age: 20));
    await repo.insert(User(name: 'C', age: 40));

    expect((await repo.all()).length, equals(3));
    expect(await repo.count(), equals(3));
    expect((await repo.findBy('age', 20)).length, equals(2));

    final older = await repo.firstBy('age', 30, '>');
    expect(older!.name, equals('C'));
  });

  test('cursor streams hydrated entities', () async {
    for (var i = 0; i < 5; i++) {
      await repo.insert(User(name: 'u$i', age: i));
    }
    final ages = <int>[];
    await for (final u in repo.query().orderBy('age').cursor().map(
        (r) => userMapper.fromRow(r))) {
      ages.add(u.age);
    }
    expect(ages, equals([0, 1, 2, 3, 4]));
  });

  test('delete removes the row', () async {
    final id = await repo.save(User(name: 'Zoe', age: 22)) as int;
    final affected = await repo.deleteById(id);
    expect(affected, equals(1));
    expect(await repo.find(id), isNull);
  });
}
