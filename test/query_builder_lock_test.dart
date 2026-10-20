// Unit tests (no database) for row-locking clauses: FOR UPDATE / FOR SHARE
// with SKIP LOCKED, NOWAIT and OF, on the PostgreSQL and MySQL grammars.

import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/query/grammars/query_mysql_grammar.dart';
import 'package:eloquent/src/query/processors/mysql_processor.dart';
import 'package:eloquent/src/query/processors/postgres_processor.dart';
import 'package:test/test.dart';
import 'helper.dart';

void main() {
  late FakeConnection conn;
  setUp(() => conn = FakeConnection());

  QueryBuilder pg() =>
      QueryBuilder(conn, QueryPostgresGrammar(), PostgresProcessor())
          .from('jobs')
          .where('status', '=', 'pending');

  QueryBuilder my() =>
      QueryBuilder(conn, QueryMySqlGrammar(), MySqlProcessor())
          .from('jobs')
          .where('status', '=', 'pending');

  const base = 'select * from "jobs" where "status" = ?';

  group('PostgreSQL', () {
    test('lockForUpdate / sharedLock keep their output', () {
      expect(pg().lockForUpdate().toSql(), '$base for update');
      expect(pg().sharedLock().toSql(), '$base for share');
    });

    test('lockForUpdate(skipLocked: true)', () {
      expect(pg().lockForUpdate(skipLocked: true).toSql(),
          '$base for update skip locked');
    });

    test('skipLocked() alone implies FOR UPDATE', () {
      expect(pg().skipLocked().toSql(), '$base for update skip locked');
    });

    test('skipLocked() after sharedLock() keeps FOR SHARE', () {
      expect(pg().sharedLock().skipLocked().toSql(),
          '$base for share skip locked');
    });

    test('noWait and OF', () {
      expect(pg().lockForUpdate(noWait: true).toSql(),
          '$base for update nowait');
      expect(pg().lockForUpdate(of: ['jobs'], skipLocked: true).toSql(),
          '$base for update of "jobs" skip locked');
    });

    test('SKIP LOCKED with order and limit (job-queue pattern)', () {
      expect(
          pg().orderBy('id').limit(1).lockForUpdate(skipLocked: true).toSql(),
          '$base order by "id" asc limit 1 for update skip locked');
    });

    test('raw string lock is still used verbatim', () {
      expect(pg().lock('for no key update').toSql(),
          '$base for no key update');
    });

    test('SKIP LOCKED and NOWAIT cannot be combined', () {
      expect(() => pg().skipLocked().noWait(), throwsArgumentError);
      expect(() => pg().lock('for update').skipLocked(), throwsStateError);
      expect(() => pg().lock(1), throwsArgumentError);
    });

    test('first() keeps the lock and the bindings', () async {
      await pg().lockForUpdate(skipLocked: true).first();
      expect(conn.lastSelectSql, '$base limit 1 for update skip locked');
      expect(conn.lastSelectBindings, ['pending']);
    });

    test('clone keeps the lock', () {
      expect(pg().skipLocked().clone().toSql(), '$base for update skip locked');
    });
  });

  group('MySQL', () {
    const myBase = 'select * from `jobs` where `status` = ?';

    test('plain locks keep their output', () {
      expect(my().lockForUpdate().toSql(), '$myBase for update');
      expect(my().sharedLock().toSql(), '$myBase lock in share mode');
    });

    test('modifiers use the MySQL 8 syntax', () {
      expect(my().lockForUpdate(skipLocked: true).toSql(),
          '$myBase for update skip locked');
      expect(my().sharedLock(noWait: true).toSql(), '$myBase for share nowait');
      expect(my().lockForUpdate(of: ['jobs']).toSql(),
          '$myBase for update of `jobs`');
    });
  });
}
