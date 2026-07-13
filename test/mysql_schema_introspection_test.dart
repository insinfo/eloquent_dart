// mysql_schema_introspection_test.dart
//
// Integration tests (require a live MySQL/MariaDB) for MySQL schema
// introspection — in particular ENUM value parsing with escaped quotes.
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
    await db.execute('DROP TABLE IF EXISTS enum_introspect');
  });

  tearDown(() async {
    await db.execute('DROP TABLE IF EXISTS enum_introspect');
    await manager.getDatabaseManager().purge('default');
  });

  test('ENUM values are parsed (multi-value + doubled-quote escape)', () async {
    // 'a''b' is the SQL doubled-quote escape for the value  a'b
    await db.execute(
        "CREATE TABLE enum_introspect (id int, status enum('a''b','plain','on hold'))");

    final sm = db.getDoctrineSchemaManager();
    final cols = await sm.listTableColumns('enum_introspect');
    final status = cols.values.firstWhere((c) => c.getName() == 'status');

    expect(status.type, equals('enum'));
    expect(status.allowedValues, equals(["a'b", 'plain', 'on hold']));
  });
}
