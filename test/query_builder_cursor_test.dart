// query_builder_cursor_test.dart
//
// Unit tests (no database) for the streaming cursor API added in the
// `performace` branch. Uses FakeConnection to assert the compiled SQL /
// bindings and that rows are streamed through unchanged.

import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/query/processors/postgres_processor.dart';
import 'package:test/test.dart';
import 'helper.dart';

void main() {
  group('QueryBuilder.cursor()', () {
    late FakeConnection conn;
    setUp(() => conn = FakeConnection());

    QueryBuilder builder() =>
        QueryBuilder(conn, QueryPostgresGrammar(), PostgresProcessor())
            .from('big');

    test('emits the compiled select SQL and bindings', () async {
      conn.mockSelectResult = [
        {'id': 1},
        {'id': 2},
      ];

      final qb = builder().where('ok', '=', true);
      final rows = await qb.cursor().toList();

      expect(
        conn.lastSelectSql,
        equals('select * from "big" where "ok" = ?'),
      );
      expect(conn.lastSelectBindings, equals([true]));
      expect(rows, equals([
        {'id': 1},
        {'id': 2},
      ]));
    });

    test('streams rows lazily (one at a time)', () async {
      conn.mockSelectResult = List.generate(5, (i) => {'n': i});

      final seen = <int>[];
      await for (final row in builder().cursor()) {
        seen.add(row['n'] as int);
      }
      expect(seen, equals([0, 1, 2, 3, 4]));
    });

    test('lazy() is an alias for cursor()', () async {
      conn.mockSelectResult = [
        {'id': 9},
      ];
      final rows = await builder().lazy().toList();
      expect(rows, equals([
        {'id': 9},
      ]));
    });

    test('restores columns after streaming', () async {
      conn.mockSelectResult = [];
      final qb = builder().select(['a', 'b']);
      await qb.cursor().toList();
      // Selecting again should still reflect the original explicit columns.
      expect(qb.columnsProp, equals(['a', 'b']));
    });
  });

  group('cursor unsupported by adapter', () {
    test('PDOExecutionContext.queryStream default throws UnsupportedError', () {
      final ctx = _NoStreamContext();
      expect(
        () => ctx.queryStream('select 1').toList(),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}

/// Minimal execution context that does not override queryStream, to verify the
/// default UnsupportedError behavior.
class _NoStreamContext extends PDOExecutionContext {
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
