// `datetime_bindings`: 'string' (default, Laravel) vs 'native' on the four
// PostgreSQL adapters and MariaDB/MySQL, with a session time zone that is
// not UTC. Requires localhost:5432 / 3306, database `banco_teste`, dart/dart.
@Tags(['integration'])
library;

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

Map<String, dynamic> _config(String driver, String mode) => driver == 'mysql'
    ? {
        'driver': 'mysql',
        'host': 'localhost',
        'port': '3306',
        'database': 'banco_teste',
        'username': 'dart',
        'password': 'dart',
        'timezone': '-03:00',
        'datetime_bindings': mode,
      }
    : {
        'driver': 'pgsql',
        'driver_implementation': driver,
        'host': 'localhost',
        'port': '5432',
        'database': 'banco_teste',
        'username': 'dart',
        'password': 'dart',
        'charset': 'utf8',
        'schema': ['public'],
        'timezone': 'America/Sao_Paulo',
        'datetime_bindings': mode,
      };

const _table = 'eloquent_dt_bindings';

String _two(int n) => n.toString().padLeft(2, '0');

/// Wall-clock fields of [d], with microseconds when [micros].
String _fields(DateTime d, {bool micros = true}) {
  final base = '${d.year}-${_two(d.month)}-${_two(d.day)} '
      '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
  if (!micros) return base;
  return '$base.${(d.millisecond * 1000 + d.microsecond).toString().padLeft(6, '0')}';
}

final _local = DateTime(2024, 3, 10, 12, 34, 56, 789, 123);
final _utc = DateTime.utc(2024, 3, 10, 12, 34, 56, 789, 123);

void main() {
  test('datetime_bindings is validated', () {
    expect(PDOConfig.parseDateTimeBindings(null), DateTimeBindings.string);
    expect(PDOConfig.parseDateTimeBindings('NATIVE'), DateTimeBindings.native);
    expect(() => PDOConfig.parseDateTimeBindings('iso'), throwsArgumentError);
  });

  for (final driver in ['postgres', 'postgres_v3', 'dargres', 'dpgsql']) {
    group(driver, () {
      late Manager manager;

      Future<Connection> open(String mode) async {
        manager = Manager()..addConnection(_config(driver, mode), 'dt_$mode');
        final db = await manager.getConnection('dt_$mode');
        await db.execute('DROP TABLE IF EXISTS $_table');
        await db.execute('CREATE TABLE $_table (k text, ts timestamp(6), '
            'tstz timestamptz(6), d date)');
        return db;
      }

      Future<Map<String, dynamic>> stored(Connection db, String key) async {
        final rows = await db.select(
            "select ts::text ts, to_char(tstz at time zone 'UTC', "
            "'YYYY-MM-DD HH24:MI:SS.US') tstz_utc, d::text d "
            'from $_table where k = ?',
            [key]);
        return rows.single;
      }

      tearDown(() async {
        for (final name in manager.getDatabaseManager().connectionsProp.keys
            .toList()) {
          final db = await manager.getConnection(name);
          await db.execute('DROP TABLE IF EXISTS $_table');
          await manager.getDatabaseManager().purge(name);
        }
      });

      test('native: fields for timestamp, instant for timestamptz, micros',
          () async {
        final db = await open('native');
        for (final entry in {'local': _local, 'utc': _utc}.entries) {
          final v = entry.value;
          await db
              .table(_table)
              .insert({'k': entry.key, 'ts': v, 'tstz': v, 'd': v});
          final row = await stored(db, entry.key);
          expect(row['ts'], _fields(v), reason: entry.key);
          expect(row['tstz_utc'], _fields(v.toUtc()), reason: entry.key);
          expect(row['d'], '2024-03-10');
        }

        // What is read back (timestamptz as UTC) can be written back and
        // compared without shifting.
        final read = (await db.table(_table).where('k', 'local').first())!;
        final tstz = read['tstz'] as DateTime;
        await db.table(_table).where('k', 'local').update({'tstz': tstz});
        expect((await stored(db, 'local'))['tstz_utc'], _fields(_local.toUtc()));
        // In a process running in UTC the local and UTC values are the same
        // instant (CI); elsewhere they differ.
        expect(await db.table(_table).where('tstz', tstz).count(),
            _local.isAtSameMomentAs(_utc) ? 2 : 1);
        expect(await db.table(_table).where('ts', _local).count(), 2,
            reason: 'both rows store the same wall clock fields');
      });

      test('string (default): grammar format, no micros, no zone', () async {
        final db = await open('string');
        await db
            .table(_table)
            .insert({'k': 'utc', 'ts': _utc, 'tstz': _utc, 'd': _utc});
        final row = await stored(db, 'utc');
        expect(row['ts'], _fields(_utc, micros: false));
        // "12:34:56" read in the session zone (-03), not 12:34:56 UTC.
        expect(row['tstz_utc'], '2024-03-10 15:34:56.000000');
      });
    });
  }

  group('mysql', () {
    late Manager manager;

    tearDown(() async {
      for (final name
          in manager.getDatabaseManager().connectionsProp.keys.toList()) {
        final db = await manager.getConnection(name);
        await db.execute('DROP TABLE IF EXISTS $_table');
        await manager.getDatabaseManager().purge(name);
      }
    });

    for (final mode in ['native', 'string']) {
      test(mode, () async {
        manager = Manager()..addConnection(_config('mysql', mode), 'dt_$mode');
        final db = await manager.getConnection('dt_$mode');
        await db.execute('DROP TABLE IF EXISTS $_table');
        await db.execute('CREATE TABLE $_table (k varchar(10), '
            'ts datetime(6), d date)');
        await db.table(_table).insert({'k': 'local', 'ts': _local, 'd': _local});
        final row = (await db.select(
                'select cast(ts as char) ts, cast(d as char) d from $_table'))
            .single;
        expect(row['ts'],
            mode == 'native' ? _fields(_local) : '${_fields(_local, micros: false)}.000000');
        expect(row['d'], '2024-03-10');
        expect(await db.table(_table).where('ts', _local).count(), 1);
      });
    }
  });
}
