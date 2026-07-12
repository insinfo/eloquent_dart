// dpgsql_pg_features_integration_test.dart
//
// Integration tests (require a live PostgreSQL) for the Phase 9 helpers:
// JSON containment/length, full-text search, distinct-on and `->` access.
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

void main() {
  late Manager manager;
  late Connection db;

  setUp(() async {
    manager = Manager();
    manager.addConnection(Map<String, dynamic>.from(_config));
    manager.setAsGlobal();
    db = await manager.connection();

    await db.execute('DROP TABLE IF EXISTS perf_pgfeat');
    await db.execute('''
      CREATE TABLE perf_pgfeat (
        id serial primary key,
        user_id int not null,
        tags jsonb,
        meta jsonb,
        body text,
        created_at timestamp not null
      )
    ''');

    Future<void> ins(int uid, String tags, String meta, String body, String at) =>
        db.execute("INSERT INTO perf_pgfeat (user_id, tags, meta, body, created_at) "
            "VALUES ($uid, '$tags'::jsonb, '$meta'::jsonb, '$body', '$at')");

    await ins(1, '["urgent","new"]', '{"name":"ada"}', 'the quick brown fox', '2026-01-01 10:00:00');
    await ins(1, '["urgent"]', '{"name":"ada"}', 'lazy dogs sleeping', '2026-01-02 10:00:00');
    await ins(2, '["new"]', '{"name":"bob"}', 'a clever fox and hound', '2026-01-03 10:00:00');
  });

  tearDown(() async {
    await db.execute('DROP TABLE IF EXISTS perf_pgfeat');
    await manager.getDatabaseManager().purge('default');
  });

  test('whereJsonContains matches jsonb array elements', () async {
    final rows = await db
        .table('perf_pgfeat')
        .whereJsonContains('tags', ['urgent'])
        .orderBy('id')
        .get();
    expect(rows.map((r) => r['id']).toList(), equals([1, 2]));
  });

  test('whereJsonContains scalar in nested path', () async {
    final count = await db
        .table('perf_pgfeat')
        .whereJsonContains('meta', {'name': 'ada'})
        .count();
    expect(count, equals(2));
  });

  test('whereJsonLength filters by array length', () async {
    final rows = await db
        .table('perf_pgfeat')
        .whereJsonLength('tags', '>', 1)
        .get();
    expect(rows.length, equals(1));
    expect(rows.first['id'], equals(1));
  });

  test('whereFullText matches tsquery', () async {
    final rows = await db
        .table('perf_pgfeat')
        .whereFullText('body', 'fox')
        .orderBy('id')
        .get();
    expect(rows.map((r) => r['id']).toList(), equals([1, 3]));
  });

  test('JSON -> access in where', () async {
    final count = await db
        .table('perf_pgfeat')
        .where('meta->name', '=', 'bob')
        .count();
    expect(count, equals(1));
  });

  test('distinctOn returns one row per user_id', () async {
    final rows = await db
        .table('perf_pgfeat')
        .distinctOn(['user_id'])
        .select(['user_id', 'id'])
        .orderBy('user_id')
        .orderBy('created_at', 'desc')
        .get();
    // Latest row per user: user 1 -> id 2, user 2 -> id 3.
    expect(
      rows.map((r) => [r['user_id'], r['id']]).toList(),
      equals([
        [1, 2],
        [2, 3],
      ]),
    );
  });
}
