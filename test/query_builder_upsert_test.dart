// query_builder_upsert_test.dart
//
// Unit tests (no database) for UPSERT / ON CONFLICT / RETURNING compilation
// added in the `performace` branch.

import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/query/grammars/query_mysql_grammar.dart';
import 'package:eloquent/src/query/processors/mysql_processor.dart';
import 'package:eloquent/src/query/processors/postgres_processor.dart';
import 'package:test/test.dart';
import 'helper.dart';

void main() {
  group('PostgreSQL upsert / on conflict / returning', () {
    late FakeConnection conn;

    setUp(() => conn = FakeConnection());

    test('upsert with explicit update map', () async {
      final qb =
          QueryBuilder(conn, QueryPostgresGrammar(), PostgresProcessor())
              .from('users');
      await qb.upsert(
        [
          {'email': 'a@x.com', 'name': 'A'},
        ],
        ['email'],
        {'name': 'A2'},
      );

      expect(
        conn.lastAffectingSql,
        equals(
          'insert into "users" ("email", "name") values (?, ?) '
          'on conflict ("email") do update set "name" = ?',
        ),
      );
      expect(conn.lastAffectingBindings, equals(['a@x.com', 'A', 'A2']));
    });

    test('upsert without update map updates non-unique columns from excluded',
        () async {
      final qb =
          QueryBuilder(conn, QueryPostgresGrammar(), PostgresProcessor())
              .from('users');
      await qb.upsert(
        [
          {'email': 'a@x.com', 'name': 'A', 'age': 30},
        ],
        ['email'],
      );

      expect(
        conn.lastAffectingSql,
        equals(
          'insert into "users" ("email", "name", "age") values (?, ?, ?) '
          'on conflict ("email") do update set '
          '"name" = excluded."name", "age" = excluded."age"',
        ),
      );
      expect(conn.lastAffectingBindings, equals(['a@x.com', 'A', 30]));
    });

    test('upsert with multiple rows', () async {
      final qb =
          QueryBuilder(conn, QueryPostgresGrammar(), PostgresProcessor())
              .from('users');
      await qb.upsert(
        [
          {'email': 'a@x.com', 'name': 'A'},
          {'email': 'b@x.com', 'name': 'B'},
        ],
        ['email'],
        {'name': 'X'},
      );

      expect(
        conn.lastAffectingSql,
        equals(
          'insert into "users" ("email", "name") values (?, ?), (?, ?) '
          'on conflict ("email") do update set "name" = ?',
        ),
      );
      expect(
        conn.lastAffectingBindings,
        equals(['a@x.com', 'A', 'b@x.com', 'B', 'X']),
      );
    });

    test('insertOrIgnore -> on conflict do nothing', () async {
      final qb =
          QueryBuilder(conn, QueryPostgresGrammar(), PostgresProcessor())
              .from('users');
      await qb.insertOrIgnore({'email': 'a@x.com', 'name': 'A'});

      expect(
        conn.lastAffectingSql,
        equals(
          'insert into "users" ("email", "name") values (?, ?) '
          'on conflict do nothing',
        ),
      );
      expect(conn.lastAffectingBindings, equals(['a@x.com', 'A']));
    });

    test('low-level onConflict + doUpdate(raw) + returning (the user case)',
        () async {
      final qb =
          QueryBuilder(conn, QueryPostgresGrammar(), PostgresProcessor())
              .from('processos_sequences');

      await qb
          .onConflict(['ano'])
          .doUpdate({
            'last_id': qb.raw('processos_sequences.last_id + 1'),
          })
          .returning(['last_id'])
          .insert({'ano': 2026, 'last_id': 1});

      expect(
        conn.lastInsertSql,
        equals(
          'insert into "processos_sequences" ("ano", "last_id") values (?, ?) '
          'on conflict ("ano") do update set '
          '"last_id" = processos_sequences.last_id + 1 '
          'returning "last_id"',
        ),
      );
      // Raw expression contributes no binding; only the inserted values remain.
      expect(conn.lastInsertBindings, equals([2026, 1]));
    });

    test('onConflict on named constraint + doNothing', () async {
      final qb =
          QueryBuilder(conn, QueryPostgresGrammar(), PostgresProcessor())
              .from('t');
      await qb
          .onConflict([], 'my_unique')
          .doNothing()
          .insert({'a': 1, 'b': 2});

      expect(
        conn.lastInsertSql,
        equals(
          'insert into "t" ("a", "b") values (?, ?) '
          'on conflict on constraint "my_unique" do nothing',
        ),
      );
      expect(conn.lastInsertBindings, equals([1, 2]));
    });

    test('returning with default (*)', () async {
      final qb =
          QueryBuilder(conn, QueryPostgresGrammar(), PostgresProcessor())
              .from('t');
      await qb.returning().insert({'a': 1});

      expect(conn.lastInsertSql, equals('insert into "t" ("a") values (?) returning *'));
    });
  });

  group('MySQL upsert / insertOrIgnore', () {
    late FakeConnection conn;
    setUp(() => conn = FakeConnection());

    test('upsert -> on duplicate key update (explicit)', () async {
      final qb = QueryBuilder(conn, QueryMySqlGrammar(), MySqlProcessor())
          .from('users');
      await qb.upsert(
        [
          {'email': 'a@x.com', 'name': 'A'},
        ],
        ['email'],
        {'name': 'A2'},
      );

      expect(
        conn.lastAffectingSql,
        equals(
          'insert into `users` (`email`, `name`) values (?, ?) '
          'on duplicate key update `name` = ?',
        ),
      );
      expect(conn.lastAffectingBindings, equals(['a@x.com', 'A', 'A2']));
    });

    test('upsert without update map uses values(col)', () async {
      final qb = QueryBuilder(conn, QueryMySqlGrammar(), MySqlProcessor())
          .from('users');
      await qb.upsert(
        [
          {'email': 'a@x.com', 'name': 'A'},
        ],
        ['email'],
      );

      expect(
        conn.lastAffectingSql,
        equals(
          'insert into `users` (`email`, `name`) values (?, ?) '
          'on duplicate key update `name` = values(`name`)',
        ),
      );
    });

    test('insertOrIgnore -> insert ignore', () async {
      final qb = QueryBuilder(conn, QueryMySqlGrammar(), MySqlProcessor())
          .from('users');
      await qb.insertOrIgnore({'email': 'a@x.com'});

      expect(
        conn.lastAffectingSql,
        equals('insert ignore into `users` (`email`) values (?)'),
      );
    });

    test('returning is rejected on MySQL', () {
      final grammar = QueryMySqlGrammar();
      expect(
        () => grammar.compileReturning(['id']),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
