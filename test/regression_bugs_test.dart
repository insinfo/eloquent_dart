// regression_bugs_test.dart
//
// Unit regression tests (no database) for bugs fixed on the `performace` branch.
// These are pure SQL-generation checks so they are safe to run in parallel.

import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/query/processors/postgres_processor.dart';
import 'package:test/test.dart';
import 'helper.dart';

/// Minimal PDO context — the schema compilers never touch it, they only need a
/// concrete [Connection] instance to satisfy the parameter type.
class _FakeCtx extends PDOExecutionContext {
  @override
  Future<int> execute(String statement, [int? timeoutInSeconds]) async => 0;

  @override
  Future<PDOResults> query(String query,
          [dynamic params, int? timeoutInSeconds]) async =>
      PDOResults([], 0);

  @override
  PDOConfig getConfig() =>
      PDOConfig(driver: 'pgsql', host: 'localhost', database: 'x');
}

void main() {
  // A real (fake-backed) Connection; the schema DDL compilers ignore it.
  final Connection conn = PostgresConnection(_FakeCtx(), 'test');

  group('schema DDL was previously stubbed to [""] (compile* returned empty)',
      () {
    final grammar = SchemaPostgresGrammar();

    test('compileCreate emits CREATE TABLE with bigserial primary key', () {
      final bp = Blueprint('widgets')
        ..create()
        ..id()
        ..string('name')
        ..integer('qty');
      expect(
        bp.toSql(conn, grammar),
        equals([
          'create table "widgets" ("id" bigserial primary key, '
              '"name" varchar(255), "qty" integer)'
        ]),
      );
    });

    test('compileCreate honors nullable / default modifiers', () {
      final bp = Blueprint('t')
        ..create()
        ..string('a')
        ..integer('b');
      // Force modifiers via the fluent column attributes.
      (bp.getAddedColumns()[0]).attributes['nullable'] = true;
      (bp.getAddedColumns()[1]).attributes['default'] = 0;
      expect(
        bp.toSql(conn, grammar),
        equals([
          'create table "t" ("a" varchar(255) null, "b" integer default 0)'
        ]),
      );
    });

    test('compileAdd emits ALTER TABLE ADD COLUMN', () {
      final bp = Blueprint('widgets')..boolean('active');
      expect(
        bp.toSql(conn, grammar),
        equals(['alter table "widgets" add column "active" boolean']),
      );
    });

    test('compileDrop / compileDropIfExists', () {
      final drop = Blueprint('widgets')..drop();
      expect(drop.toSql(conn, grammar), equals(['drop table "widgets"']));

      final dropIf = Blueprint('widgets')..dropIfExists();
      expect(dropIf.toSql(conn, grammar),
          equals(['drop table if exists "widgets"']));
    });
  });

  group('QueryPostgresGrammar.compileInsert empty values (stray "}" bug)', () {
    test('empty insert -> DEFAULT VALUES without a stray brace', () {
      final grammar = QueryPostgresGrammar();
      final qb = QueryBuilder(FakeConnection(), grammar, PostgresProcessor())
          .from('t');
      expect(
        grammar.compileInsert(qb, {}),
        equals('insert into "t" DEFAULT VALUES'),
      );
    });
  });

  group('SchemaBuilder._getSchemaName accepts a List schema config', () {
    test('List search-path no longer throws "List is not a subtype of String?"',
        () async {
      // Previously `_getSchemaName` assigned the List config directly to a
      // String? and threw. hasTable() exercises that path.
      final c = PostgresConnection(_FakeCtx(), 'test', '', {
        'schema': ['public', 'other'],
      });
      final sb = c.getSchemaBuilder();
      expect(await sb.hasTable('whatever'), isFalse);
    });

    test('comma-separated schema config also works', () async {
      final c = PostgresConnection(_FakeCtx(), 'test', '', {
        'schema': 'public,other',
      });
      final sb = c.getSchemaBuilder();
      expect(await sb.hasTable('whatever'), isFalse);
    });
  });

  group('grammar wrap() fast paths preserve behavior', () {
    final grammar = QueryPostgresGrammar();

    test('wrapValue doubles embedded double quotes', () {
      expect(grammar.wrapValue('a"b'), equals('"a""b"'));
    });

    test('wrap handles simple, dotted and aliased identifiers', () {
      expect(grammar.wrap('id'), equals('"id"'));
      expect(grammar.wrap('u.id'), equals('"u"."id"'));
      expect(grammar.wrap('users as u'), equals('"users" as "u"'));
      expect(grammar.wrap('*'), equals('*'));
    });
  });
}
