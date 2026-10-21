// numeric comes back as the exact server text on the four PostgreSQL
// adapters (a double loses digits and the scale: 150.50 → 150.5).
// Requires localhost:5432, database `banco_teste`, dart/dart.
@Tags(['integration'])
library;

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

void main() {
  for (final driver in ['postgres', 'postgres_v3', 'dargres', 'dpgsql']) {
    test('$driver: numeric is exact text', () async {
      final manager = Manager()
        ..addConnection({
          'driver': 'pgsql',
          'driver_implementation': driver,
          'host': 'localhost',
          'port': '5432',
          'database': 'banco_teste',
          'username': 'dart',
          'password': 'dart',
          'charset': 'utf8',
          'schema': ['public'],
        }, 'numeric');
      final db = await manager.getConnection('numeric');
      addTearDown(() => manager.getDatabaseManager().purge('numeric'));

      final row = (await db.select(
              'select 150.5::numeric(10,2) as price, '
              '12345678901234567890.123456789::numeric as big, '
              '?::numeric as param',
              ['0.10']))
          .single;
      expect(row, {
        'price': '150.50',
        'big': '12345678901234567890.123456789',
        'param': '0.10',
      });
    });
  }
}
