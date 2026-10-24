// The PostgreSQL session each adapter opens from the connection config:
// search_path (schema), application_name, TimeZone and TLS (sslmode), read
// back from the server.
//
// Connection: localhost:5432 db=banco_teste user/pass=dart. The server has
// SSL on, with a self-signed certificate (CN=192.168.66.123): verify-ca and
// verify-full must refuse it.

@Tags(['integration'])
library;

import 'dart:math';

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

const _drivers = ['postgres', 'postgres_v3', 'dargres', 'dpgsql'];

Map<String, dynamic> _config(String driver,
        {bool pool = false, Map<String, dynamic> extra = const {}}) =>
    {
      'driver': 'pgsql',
      'driver_implementation': driver,
      'host': 'localhost',
      'port': '5432',
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

Future<String?> _ssl(Connection db) => _value(
    db, 'select ssl::text as v from pg_stat_ssl where pid = pg_backend_pid()');

void main() {
  setUpAll(() async {
    await _withDb(_config('postgres'), (db) async {
      for (final schema in ['cov_cn_q"s', 'cov_cn_a,b']) {
        final quoted = '"${schema.replaceAll('"', '""')}"';
        await db.execute('CREATE SCHEMA IF NOT EXISTS $quoted');
      }
    });
  });

  tearDownAll(() async {
    await _withDb(_config('postgres'), (db) async {
      await db.execute('DROP SCHEMA IF EXISTS "cov_cn_q""s", "cov_cn_a,b"');
    });
  });

  for (final driver in _drivers) {
    for (final pool in [false, true]) {
      group('$driver ${pool ? 'pool' : 'single'}', () {
        Map<String, dynamic> config(Map<String, dynamic> extra) =>
            _config(driver, pool: pool, extra: extra);

        test('schema names with a double quote and a comma', () async {
          for (final schema in [
            r'cov_cn_q"s, "cov_cn_a,b"',
            ['cov_cn_q"s', 'cov_cn_a,b'],
          ]) {
            await _withDb(config({'schema': schema}), (db) async {
              expect(
                  await _value(
                      db,
                      "select array_to_string(current_schemas(false), '|') "
                      'as v'),
                  'cov_cn_q"s|cov_cn_a,b',
                  reason: '$schema');
            });
          }
        });

        test('an empty schema leaves the default search_path', () async {
          for (final schema in [null, [], '']) {
            await _withDb(config({'schema': schema}), (db) async {
              expect(
                  await _value(
                      db, "select current_setting('search_path') as v"),
                  r'"$user", public',
                  reason: '$schema');
            });
          }
        });

        test('application_name and timezone with special characters', () async {
          await _withDb(
              config({
                'application_name': "app d'oeste",
                'timezone': 'America/Sao_Paulo',
              }), (db) async {
            expect(
                await _value(
                    db, "select current_setting('application_name') as v"),
                "app d'oeste");
            expect(await _value(db, "select current_setting('TimeZone') as v"),
                'America/Sao_Paulo');
          });
        });

        test('sslmode absent or disable: plain connection', () async {
          for (final mode in [null, 'disable']) {
            await _withDb(config({if (mode != null) 'sslmode': mode}),
                (db) async {
              expect(await _ssl(db), 'false', reason: '$mode');
            });
          }
        });

        test('sslmode require never connects in plain text', () async {
          for (final mode in ['require', 'REQUIRE']) {
            final ssl = await _withDb(config({'sslmode': mode}), _ssl)
                .catchError((Object e) => 'failed: $e');
            expect(ssl, 'true', reason: mode);
          }
        });

        test('sslmode prefer and allow: TLS when the server accepts it',
            () async {
          for (final mode in ['prefer', 'allow']) {
            await _withDb(config({'sslmode': mode}), (db) async {
              expect(await _ssl(db), 'true', reason: mode);
            });
          }
        });

        test(
            'sslmode verify-ca and verify-full refuse the self-signed '
            'certificate', () async {
          for (final mode in ['verify-ca', 'verify-full']) {
            await expectLater(
                _withDb(config({'sslmode': mode}), _ssl), throwsA(anything),
                reason: mode);
          }
        });

        test('an unknown sslmode throws ArgumentError', () async {
          await expectLater(_withDb(config({'sslmode': 'requir'}), _ssl),
              throwsA(isA<ArgumentError>()));
        });

        test('the LISTEN connection uses the same TLS mode', () async {
          final name = 'cov_cn_listen_${Random().nextInt(1 << 30)}';
          final pdo = await PostgresConnector().connect(
              config({'sslmode': 'require', 'application_name': name}));
          try {
            final listen = await pdo.openNotificationConnection();
            try {
              final rows =
                  await pdo.query('select s.ssl::text as v from pg_stat_ssl s '
                      'join pg_stat_activity a on a.pid = s.pid '
                      "where a.application_name = '$name' "
                      'and a.pid <> pg_backend_pid()');
              expect(rows.map((r) => r['v']), ['true']);
            } finally {
              await listen.close();
            }
          } finally {
            await pdo.close();
          }
        });
      });
    }
  }

  group('driver_options', () {
    test('postgres useSSL: true still enables TLS', () async {
      await _withDb(
          _config('postgres', extra: {
            'driver_options': {'useSSL': true}
          }), (db) async {
        expect(await _ssl(db), 'true');
      });
    });

    // dpgsql 1.1.2: verify-ca/verify-full always verify the certificate;
    // Trust Server Certificate only applies to require (TLS without
    // verifying it).
    test('dpgsql Trust Server Certificate does not weaken verify-full',
        () async {
      await expectLater(
          _withDb(
              _config('dpgsql', extra: {
                'sslmode': 'verify-full',
                'driver_options': {'Trust Server Certificate': 'true'},
              }),
              _ssl),
          throwsA(anything));
      await _withDb(
          _config('dpgsql', extra: {
            'sslmode': 'require',
            'driver_options': {'Trust Server Certificate': 'true'},
          }), (db) async {
        expect(await _ssl(db), 'true');
      });
    });
  });
}
