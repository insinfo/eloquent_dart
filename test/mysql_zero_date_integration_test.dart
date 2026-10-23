// A DATE/DATETIME that DateTime cannot represent (0000-00-00, a zero month
// or day, 2024-02-30 under ALLOW_INVALID_DATES) reads as null by default;
// driver_options `zeroDateBehavior: 'exception'` throws instead. mysql_dart
// 3.0.2 returned an invented date (0000-00-00 -> -0001-11-30).
//
// Connection: localhost:3306 db=banco_teste user/pass=dart.

@Tags(['integration'])
library;

import 'package:eloquent/eloquent.dart';
import 'package:mysql_dart/exception.dart';
import 'package:mysql_dart/mysql_dart.dart' show ZeroDateBehavior;
import 'package:test/test.dart';

Map<String, dynamic> _config({bool pool = false, Object? zeroDateBehavior}) => {
      'driver': 'mysql',
      'host': '127.0.0.1',
      'port': '3306',
      'database': 'banco_teste',
      'username': 'dart',
      'password': 'dart',
      if (pool) 'pool': true,
      if (pool) 'poolsize': 2,
      if (zeroDateBehavior != null)
        'driver_options': {'zeroDateBehavior': zeroDateBehavior},
    };

void main() {
  setUpAll(() async {
    final manager = Manager()..addConnection(_config(), 'setup');
    final db = await manager.connection('setup');
    // Zero and invalid dates are only stored without the strict modes.
    await db.execute("SET SESSION sql_mode = 'ALLOW_INVALID_DATES'");
    await db.execute('DROP TABLE IF EXISTS mysql_zero_date');
    await db.execute('CREATE TABLE mysql_zero_date '
        '(id int PRIMARY KEY, d date NULL, dt datetime NULL)');
    await db.execute("INSERT INTO mysql_zero_date VALUES "
        "(1, '0000-00-00', '0000-00-00 00:00:00'), "
        "(2, '2024-05-00', '2024-00-10 10:00:00'), "
        "(3, '2024-02-30', '2024-03-10 12:34:56')");
    await manager.getDatabaseManager().purge('setup');
  });

  tearDownAll(() async {
    final manager = Manager()..addConnection(_config(), 'teardown');
    final db = await manager.connection('teardown');
    await db.execute('DROP TABLE IF EXISTS mysql_zero_date');
    await manager.getDatabaseManager().purge('teardown');
  });

  for (final pool in [false, true]) {
    group(pool ? 'pool' : 'single connection', () {
      test('dates DateTime cannot represent read as null by default', () async {
        final manager = Manager()..addConnection(_config(pool: pool), 'zd');
        final db = await manager.connection('zd');
        try {
          final rows = await db.table('mysql_zero_date').orderBy('id').get();
          expect(rows.map((r) => [r['d'], r['dt']]), [
            [null, null],
            [null, null],
            [null, DateTime(2024, 3, 10, 12, 34, 56)],
          ]);
          // The same through a transaction's connection.
          final inTx = await db.transaction((ctx) =>
              ctx.table('mysql_zero_date').where('id', '=', 1).first());
          expect(inTx!['d'], isNull);
        } finally {
          await manager.getDatabaseManager().purge('zd');
        }
      });

      test("zeroDateBehavior: 'exception' throws", () async {
        final manager = Manager()
          ..addConnection(
              _config(pool: pool, zeroDateBehavior: 'exception'), 'zd');
        final db = await manager.connection('zd');
        try {
          await expectLater(
              db.table('mysql_zero_date').where('id', '=', 1).first(),
              throwsA(isA<MySQLClientException>().having(
                  (e) => e.message, 'message', contains('0000-00-00'))));
          // Valid dates still read (row 3's `d` is 2024-02-30, so only
          // `dt`), and the connection is still usable.
          final row = await db
              .table('mysql_zero_date')
              .select(['dt'])
              .where('id', '=', 3)
              .first();
          expect(row!['dt'], DateTime(2024, 3, 10, 12, 34, 56));
        } finally {
          await manager.getDatabaseManager().purge('zd');
        }
      });
    });
  }

  test('the option accepts the enum value', () async {
    final manager = Manager()
      ..addConnection(
          _config(zeroDateBehavior: ZeroDateBehavior.convertToNull), 'zd');
    final db = await manager.connection('zd');
    try {
      final row = await db.table('mysql_zero_date').where('id', '=', 1).first();
      expect(row!['d'], isNull);
    } finally {
      await manager.getDatabaseManager().purge('zd');
    }
  });

  test('an unknown zeroDateBehavior is rejected', () async {
    final manager = Manager()
      ..addConnection(_config(zeroDateBehavior: 'round'), 'zd');
    await expectLater(manager.connection('zd'), throwsArgumentError);
  });
}
