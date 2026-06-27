import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

void main() {
  late Manager manager;
  late Connection db;

  setUp(() async {
    manager = Manager();
    manager.addConnection({
      'driver': 'pgsql',
      'driver_implementation': 'dpgsql',
      'host': '127.0.0.1',
      'port': '5432',
      'database': 'dart_test',
      'username': 'dart',
      'password': 'dart',
      'charset': 'utf8',
      'prefix': '',
      'schema': ['public'],
      'pool': true,
      'poolsize': 2,
      'timezone': 'America/Sao_Paulo',
      'application_name': 'eloquent-dpgsql-test',
      'statementTimeout': '10s',
      'lockTimeout': '3s',
      'idleInTransactionSessionTimeout': '30s',
    });
    manager.setAsGlobal();
    db = await manager.connection();
    await db.execute('DROP TABLE IF EXISTS dpgsql_querybuilder_test');
    await db.execute('''
      CREATE TABLE dpgsql_querybuilder_test (
        id int primary key,
        name text not null,
        active bool not null,
        created_at timestamp not null,
        expires_at timestamp with time zone
      )
    ''');
  });

  tearDown(() async {
    try {
      await db.execute('DROP TABLE IF EXISTS dpgsql_querybuilder_test');
    } finally {
      await manager.getDatabaseManager().purge('default');
    }
  });

  test('query builder select, bindings, maps and transaction', () async {
    await db.table('dpgsql_querybuilder_test').insertMany([
      {
        'id': 1,
        'name': 'Ana',
        'active': true,
        'created_at': DateTime(2024, 1, 2, 3, 4, 5),
        'expires_at': DateTime.utc(2024, 1, 2, 6, 4, 5).toIso8601String(),
      },
      {
        'id': 2,
        'name': 'Bruno',
        'active': false,
        'created_at': DateTime(2024, 1, 3, 3, 4, 5),
        'expires_at': DateTime.utc(2024, 1, 3, 6, 4, 5).toIso8601String(),
      },
    ]);

    final first = await db
        .table('dpgsql_querybuilder_test')
        .select(['id', 'name', 'active'])
        .where('id', '=', 1)
        .first();

    expect(first, {'id': 1, 'name': 'Ana', 'active': true});

    final insertedId = await db.transaction((ctx) async {
      return ctx.table('dpgsql_querybuilder_test').insertGetId({
        'id': 3,
        'name': 'Carla',
        'active': true,
        'created_at': DateTime(2024, 1, 4, 3, 4, 5),
        'expires_at': DateTime.utc(2024, 1, 4, 6, 4, 5).toIso8601String(),
      });
    });

    expect(insertedId, 3);

    final rows = await db
        .table('dpgsql_querybuilder_test')
        .select(['id', 'name', 'created_at'])
        .where('active', '=', true)
        .orderBy('id', 'asc')
        .get();

    expect(rows.length, 2);
    expect(rows[0]['id'], 1);
    expect(rows[0]['name'], 'Ana');
    expect(rows[0]['created_at'], isA<DateTime>());
    expect(rows[0]['created_at'].hour, 3);
    expect(rows[0]['created_at'].minute, 4);
    expect(rows[1]['id'], 3);
    expect(rows[1]['name'], 'Carla');
    expect(rows[1]['created_at'], isA<DateTime>());
    expect(rows[1]['created_at'].hour, 3);
    expect(rows[1]['created_at'].minute, 4);

    final expiresAt = await db
        .table('dpgsql_querybuilder_test')
        .where('expires_at', '<', DateTime.utc(2024, 1, 5).toIso8601String())
        .count();
    expect(expiresAt, 3);
  });
}
