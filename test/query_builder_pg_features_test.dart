// query_builder_pg_features_test.dart
//
// Unit tests (no database) for the Phase 9 PostgreSQL query-builder helpers:
// JSON containment/length, full-text search, distinct-on, and JSON column
// access via the `->` selector.

import 'dart:convert';

import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/query/processors/postgres_processor.dart';
import 'package:test/test.dart';
import 'helper.dart';

void main() {
  late FakeConnection conn;
  setUp(() => conn = FakeConnection());

  QueryBuilder qb() =>
      QueryBuilder(conn, QueryPostgresGrammar(), PostgresProcessor())
          .from('docs');

  test('whereJsonContains -> jsonb @> ? with JSON-encoded binding', () async {
    await qb().whereJsonContains('tags', ['urgent', 'new']).get();
    expect(
      conn.lastSelectSql,
      equals('select * from "docs" where ("tags")::jsonb @> ?'),
    );
    expect(conn.lastSelectBindings, equals([json.encode(['urgent', 'new'])]));
  });

  test('whereJsonDoesntContain -> not ... @>', () async {
    await qb().whereJsonDoesntContain('tags', 'old').get();
    expect(
      conn.lastSelectSql,
      equals('select * from "docs" where not ("tags")::jsonb @> ?'),
    );
    expect(conn.lastSelectBindings, equals([json.encode('old')]));
  });

  test('whereJsonContains on a nested path uses ->', () async {
    await qb().whereJsonContains('meta->roles', 'admin').get();
    expect(
      conn.lastSelectSql,
      equals('select * from "docs" where ("meta"->\'roles\')::jsonb @> ?'),
    );
  });

  test('whereJsonLength -> jsonb_array_length(...) op ?', () async {
    await qb().whereJsonLength('tags', '>', 2).get();
    expect(
      conn.lastSelectSql,
      equals(
          'select * from "docs" where jsonb_array_length(("tags")::jsonb) > ?'),
    );
    expect(conn.lastSelectBindings, equals([2]));
  });

  test('whereFullText (default plain english)', () async {
    await qb().whereFullText('body', 'quick fox').get();
    expect(
      conn.lastSelectSql,
      equals('select * from "docs" where '
          '(to_tsvector(\'english\', "body")) @@ plainto_tsquery(\'english\', ?)'),
    );
    expect(conn.lastSelectBindings, equals(['quick fox']));
  });

  test('whereFullText multi-column + websearch mode + language', () async {
    await qb().whereFullText(
      ['title', 'body'],
      'cats OR dogs',
      {'language': 'simple', 'mode': 'websearch'},
    ).get();
    expect(
      conn.lastSelectSql,
      equals('select * from "docs" where '
          '(to_tsvector(\'simple\', "title") || to_tsvector(\'simple\', "body")) '
          '@@ websearch_to_tsquery(\'simple\', ?)'),
    );
  });

  test('distinctOn -> select distinct on (...)', () async {
    await qb()
        .distinctOn(['user_id'])
        .select(['user_id', 'created_at'])
        .orderBy('user_id')
        .orderBy('created_at', 'desc')
        .get();
    expect(
      conn.lastSelectSql,
      equals('select distinct on ("user_id") "user_id", "created_at" '
          'from "docs" order by "user_id" asc, "created_at" desc'),
    );
  });

  test('JSON column access via -> selector in where', () async {
    await qb().where('meta->name', '=', 'ada').get();
    expect(
      conn.lastSelectSql,
      equals('select * from "docs" where "meta"->>\'name\' = ?'),
    );
    expect(conn.lastSelectBindings, equals(['ada']));
  });

  test('unsupported grammar throws for JSON/full-text', () {
    final g = QueryGrammar();
    final b = QueryBuilder(conn, g, Processor()).from('t');
    expect(() => g.whereJsonContains(b, {'column': 'x', 'value': 1}),
        throwsA(isA<UnsupportedError>()));
    expect(() => g.whereFullText(b, {'columns': ['x'], 'value': 'y'}),
        throwsA(isA<UnsupportedError>()));
  });
}
