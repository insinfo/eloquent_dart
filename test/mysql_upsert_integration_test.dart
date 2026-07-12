// mysql_upsert_integration_test.dart
//
// Integration tests (require a live MySQL/MariaDB) validating the Phase 1
// UPSERT / insertOrIgnore paths on the MySQL grammar
// (ON DUPLICATE KEY UPDATE / INSERT IGNORE).
//
// Connection: localhost:3306 db=banco_teste user/pass=dart.

@Tags(['integration'])
library;

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

void main() {
  late Manager manager;
  late Connection db;

  setUp(() async {
    manager = Manager();
    manager.addConnection({
      'driver': 'mysql',
      'host': '127.0.0.1',
      'port': '3306',
      'database': 'banco_teste',
      'username': 'dart',
      'password': 'dart',
    });
    manager.setAsGlobal();
    db = await manager.connection();

    await db.execute('DROP TABLE IF EXISTS mysql_upsert');
    await db.execute('''
      CREATE TABLE mysql_upsert (
        email varchar(191) NOT NULL,
        name  varchar(191) NOT NULL,
        hits  int NOT NULL DEFAULT 0,
        PRIMARY KEY (email)
      )
    ''');
  });

  tearDown(() async {
    await db.execute('DROP TABLE IF EXISTS mysql_upsert');
    await manager.getDatabaseManager().purge('default');
  });

  test('upsert inserts then updates on duplicate key', () async {
    await db.table('mysql_upsert').upsert(
      [{'email': 'a@x.com', 'name': 'A', 'hits': 1}],
      ['email'],
    );
    await db.table('mysql_upsert').upsert(
      [{'email': 'a@x.com', 'name': 'A2', 'hits': 9}],
      ['email'],
      {'name': 'A2', 'hits': db.raw('mysql_upsert.hits + 1')},
    );

    final row =
        await db.table('mysql_upsert').where('email', '=', 'a@x.com').first();
    expect(row!['name'], equals('A2'));
    expect(row['hits'], equals(2)); // 1 -> +1
  });

  test('upsert multiple rows', () async {
    await db.table('mysql_upsert').upsert(
      [
        {'email': 'a@x.com', 'name': 'A', 'hits': 1},
        {'email': 'b@x.com', 'name': 'B', 'hits': 1},
      ],
      ['email'],
      {'name': db.raw('values(name)')},
    );
    final count = await db.table('mysql_upsert').count();
    expect(count, equals(2));
  });

  test('insertOrIgnore skips the duplicate', () async {
    final a = await db
        .table('mysql_upsert')
        .insertOrIgnore({'email': 'c@x.com', 'name': 'C', 'hits': 0});
    final b = await db
        .table('mysql_upsert')
        .insertOrIgnore({'email': 'c@x.com', 'name': 'C-dup', 'hits': 0});
    expect(a, equals(1));
    expect(b, equals(0));

    final count =
        await db.table('mysql_upsert').where('email', '=', 'c@x.com').count();
    expect(count, equals(1));
  });
}
