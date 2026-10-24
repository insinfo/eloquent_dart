// The MySQL session the connector opens from the connection config: SQL
// modes (strict), character set and collation, port default and TLS
// (sslmode), read back from the server.
//
// Connection: localhost:3306 db=banco_teste user/pass=dart (MariaDB 10.11,
// with SSL on and a certificate signed by a private CA: verify-ca and
// verify-full must refuse it).

@Tags(['integration'])
library;

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

Map<String, dynamic> _config(
        {bool pool = false, Map<String, dynamic> extra = const {}}) =>
    {
      'driver': 'mysql',
      'host': '127.0.0.1',
      'port': '3306',
      'database': 'banco_teste',
      'username': 'dart',
      'password': 'dart',
      if (pool) 'pool': true,
      if (pool) 'poolsize': 2,
      ...extra,
    };

/// Runs [body] on a new connection opened with [config], then closes it.
Future<T> _withDb<T>(
    Map<String, dynamic> config, Future<T> Function(Connection db) body) async {
  final manager = Manager()..addConnection(config, 'cov_cn');
  try {
    final db = await manager.connection('cov_cn');
    return await body(db);
  } finally {
    try {
      await manager.getDatabaseManager().purge('cov_cn');
    } catch (_) {}
  }
}

Future<String?> _value(Connection db, String sql) async =>
    (await db.selectOne(sql))?['v']?.toString();

Future<String> _sslCipher(Connection db) async =>
    '${(await db.selectOne("show session status like 'Ssl_cipher'"))?['Value']}';

void main() {
  for (final pool in [false, true]) {
    group(pool ? 'pool' : 'single', () {
      Map<String, dynamic> config(Map<String, dynamic> extra) =>
          _config(pool: pool, extra: extra);

      test('strict: false sets only NO_ENGINE_SUBSTITUTION', () async {
        await _withDb(config({'strict': false}), (db) async {
          expect(await _value(db, 'select @@session.sql_mode as v'),
              'NO_ENGINE_SUBSTITUTION');
        });
      });

      test('strict: true sets the strict modes MySQL 8 accepts', () async {
        await _withDb(config({'strict': true}), (db) async {
          final modes =
              (await _value(db, 'select @@session.sql_mode as v'))!.split(',');
          expect(modes, containsAll(['STRICT_TRANS_TABLES', 'NO_ZERO_DATE']));
          expect(modes, isNot(contains('NO_AUTO_CREATE_USER')));
        });
      });

      test('charset with a null collation', () async {
        await _withDb(config({'charset': 'utf8mb4', 'collation': null}),
            (db) async {
          expect(await _value(db, 'select @@character_set_client as v'),
              'utf8mb4');
        });
      });

      test('charset and collation as in Laravel', () async {
        await _withDb(
            config({'charset': 'utf8mb4', 'collation': 'utf8mb4_unicode_ci'}),
            (db) async {
          expect(await _value(db, 'select @@collation_connection as v'),
              'utf8mb4_unicode_ci');
        });
      });

      test('without port connects to 3306', () async {
        await _withDb({...config({})}..remove('port'), (db) async {
          expect(await _value(db, 'select 1 as v'), '1');
        });
      });

      test('sslmode absent or disable: plain connection', () async {
        for (final mode in [null, 'disable', 'DISABLED']) {
          await _withDb(config({if (mode != null) 'sslmode': mode}),
              (db) async {
            expect(await _sslCipher(db), isEmpty, reason: '$mode');
          });
        }
      });

      // The CI's MariaDB 10.11 has no TLS; 11.x and the local server do.
      test('sslmode require, REQUIRED, prefer: TLS when the server has it',
          () async {
        final serverTls = await _withDb(
            config({}),
            (db) async =>
                (await _value(db, 'select @@have_ssl as v')) == 'YES');
        for (final mode in ['require', 'REQUIRED']) {
          final connect = _withDb(config({'sslmode': mode}), _sslCipher);
          if (serverTls) {
            expect(await connect, isNotEmpty, reason: mode);
          } else {
            await expectLater(connect, throwsA(anything),
                reason: '$mode never connects in plain text');
          }
        }
        await _withDb(config({'sslmode': 'prefer'}), (db) async {
          expect(await _sslCipher(db), serverTls ? isNotEmpty : isEmpty,
              reason: 'prefer');
        });
      });

      test('sslmode verify-ca and verify-full refuse the certificate',
          () async {
        for (final mode in ['verify-ca', 'verify-full']) {
          await expectLater(
              _withDb(config({'sslmode': mode}), _sslCipher), throwsA(anything),
              reason: mode);
        }
      });

      test('an unknown sslmode throws ArgumentError', () async {
        await expectLater(_withDb(config({'sslmode': 'requir'}), _sslCipher),
            throwsA(isA<ArgumentError>()));
      });
    });
  }
}
