// dpgsql_performace_integration_test.dart
//
// Integration tests (require a live PostgreSQL) for the `performace` branch
// features: UPSERT / ON CONFLICT / RETURNING, streaming cursor, and direct
// driver access (COPY).
//
// Connection: localhost:5432 db=postgres user/pass=dart (dpgsql driver).
// Run with:  dart test test/dpgsql_performace_integration_test.dart

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
  'charset': 'utf8',
  'prefix': '',
  'schema': ['public'],
  'pool': true,
  'poolsize': 2,
};

void main() {
  late Manager manager;
  late Connection db;

  setUp(() async {
    manager = Manager();
    manager.addConnection(Map<String, dynamic>.from(_config));
    manager.setAsGlobal();
    db = await manager.connection();
  });

  tearDown(() async {
    await manager.getDatabaseManager().purge('default');
  });

  group('UPSERT / ON CONFLICT / RETURNING', () {
    setUp(() async {
      await db.execute('DROP TABLE IF EXISTS perf_upsert');
      await db.execute('''
        CREATE TABLE perf_upsert (
          email text primary key,
          name  text not null,
          hits  int  not null default 0
        )
      ''');
    });
    tearDown(() => db.execute('DROP TABLE IF EXISTS perf_upsert'));

    test('upsert inserts then updates on conflict', () async {
      await db.table('perf_upsert').upsert(
        [{'email': 'a@x.com', 'name': 'A', 'hits': 1}],
        ['email'],
      );
      await db.table('perf_upsert').upsert(
        [{'email': 'a@x.com', 'name': 'A2', 'hits': 5}],
        ['email'],
        {'name': db.raw('excluded.name'), 'hits': db.raw('perf_upsert.hits + 1')},
      );

      final row = await db.table('perf_upsert')
          .where('email', '=', 'a@x.com').first();
      expect(row!['name'], equals('A2'));
      expect(row['hits'], equals(2)); // 1 -> +1
    });

    test('insertOrIgnore skips the duplicate', () async {
      final a = await db.table('perf_upsert')
          .insertOrIgnore({'email': 'b@x.com', 'name': 'B'});
      final b = await db.table('perf_upsert')
          .insertOrIgnore({'email': 'b@x.com', 'name': 'B-dup'});
      expect(a, equals(1));
      expect(b, equals(0));

      final count = await db.table('perf_upsert')
          .where('email', '=', 'b@x.com').count();
      expect(count, equals(1));
    });
  });

  group('lock-free sequence (the user case)', () {
    setUp(() async {
      await db.execute('DROP TABLE IF EXISTS processos_sequences');
      await db.execute('''
        CREATE TABLE processos_sequences (
          ano     int primary key,
          last_id int not null
        )
      ''');
    });
    tearDown(() => db.execute('DROP TABLE IF EXISTS processos_sequences'));

    Future<int> nextSeq(int ano) async {
      final rows = await db.table('processos_sequences')
          .onConflict(['ano'])
          .doUpdate({'last_id': db.raw('processos_sequences.last_id + 1')})
          .returning(['last_id'])
          .insert({'ano': ano, 'last_id': 1});
      return rows.first['last_id'] as int;
    }

    test('ON CONFLICT DO UPDATE RETURNING increments atomically', () async {
      expect(await nextSeq(2026), equals(1));
      expect(await nextSeq(2026), equals(2));
      expect(await nextSeq(2026), equals(3));
      expect(await nextSeq(2027), equals(1)); // different key
    });
  });

  group('streaming cursor', () {
    setUp(() async {
      await db.execute('DROP TABLE IF EXISTS perf_cursor');
      await db.execute(
          'CREATE TABLE perf_cursor (id int primary key, n int not null)');
      // Insert 1000 rows via generate_series (fast).
      await db.execute(
          'INSERT INTO perf_cursor SELECT g, g * 2 FROM generate_series(1, 1000) g');
    });
    tearDown(() => db.execute('DROP TABLE IF EXISTS perf_cursor'));

    test('cursor() streams every row', () async {
      var count = 0;
      var sum = 0;
      await for (final row in db.table('perf_cursor').orderBy('id').cursor()) {
        count++;
        sum += row['n'] as int;
      }
      expect(count, equals(1000));
      expect(sum, equals(1001000)); // sum of 2..2000 step 2
    });

    test('cursor() honors where + limit', () async {
      final ids = <int>[];
      await for (final row in db
          .table('perf_cursor')
          .where('id', '<=', 5)
          .orderBy('id')
          .cursor()) {
        ids.add(row['id'] as int);
      }
      expect(ids, equals([1, 2, 3, 4, 5]));
    });
  });

  group('direct driver access — COPY', () {
    setUp(() async {
      await db.execute('DROP TABLE IF EXISTS perf_copy');
      await db.execute(
          'CREATE TABLE perf_copy (id int primary key, city text, note text)');
    });
    tearDown(() => db.execute('DROP TABLE IF EXISTS perf_copy'));

    test('copyInRows bulk-loads and handles escaping', () async {
      final drv = db.driver();
      expect(drv, isNotNull);
      expect(drv!.supportsCopy, isTrue);

      final written = await drv.copyInRows(
        'perf_copy',
        ['id', 'city', 'note'],
        [
          [1, 'Rio', 'ok'],
          [2, 'Niteroi', 'tab\there'],
          [3, 'Sao Paulo', null],
        ],
      );
      expect(written, equals(3));

      final rows = await db.table('perf_copy').orderBy('id').get();
      expect(rows.length, equals(3));
      expect(rows[1]['note'], equals('tab\there')); // escaping round-trips
      expect(rows[2]['note'], isNull);
    });

    test('copyOutText exports rows', () async {
      await db.table('perf_copy').insert({'id': 1, 'city': 'Rio', 'note': 'x'});
      final drv = db.driver()!;
      final out = await drv.copyOutText('COPY perf_copy TO STDOUT');
      expect(out.trim(), equals('1\tRio\tx'));
    });
  });
}
