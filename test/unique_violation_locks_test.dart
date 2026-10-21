// Unit tests (no database) for UniqueConstraintViolationException.fromDriverError
// with the exception shapes of each driver, and for LOCK TABLE compilation.

import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/query/grammars/query_mysql_grammar.dart';
import 'package:eloquent/src/query/processors/mysql_processor.dart';
import 'package:eloquent/src/query/processors/postgres_processor.dart';
import 'package:test/test.dart';
import 'helper.dart';

/// postgres (postgres_fork) and postgres_v3: `code` and `constraintName`.
class _PgError implements Exception {
  _PgError(this.code, [this.constraintName]);
  final String? code;
  final String? constraintName;
  @override
  String toString() => 'Severity.error $code: duplicate key value violates '
      'unique constraint "$constraintName"';
}

/// dpgsql: `sqlState` and `constraintName`.
class _DpgsqlError implements Exception {
  _DpgsqlError(this.sqlState, this.constraintName);
  final String sqlState;
  final String? constraintName;
}

class _Notice {
  _Notice(this.constraint);
  final String? constraint;
}

/// dargres: `errorCode` and the server fields in `serverMessage`.
class _DargresError implements Exception {
  _DargresError(this.errorCode, this.serverMessage);
  final Object? errorCode;
  final _Notice? serverMessage;
}

/// mysql_dart: `errorCode` (int) and the key in the message.
class _MySqlError implements Exception {
  _MySqlError(this.errorCode, this.message);
  final int errorCode;
  final String message;
  @override
  String toString() => 'MySQLServerException [$errorCode]: $message';
}

void main() {
  UniqueConstraintViolationException? map(Object error) =>
      UniqueConstraintViolationException.fromDriverError(
          error, 'insert into t (a) values (?)', [1]);

  group('fromDriverError', () {
    test('postgres / postgres_v3', () {
      final e = map(_PgError('23505', 'tipo_norma_nome_uq'))!;
      expect(e.constraint, 'tipo_norma_nome_uq');
      expect(e.sql, 'insert into t (a) values (?)');
      expect(e.bindings, [1]);
      expect(e.previous, isA<_PgError>());
      // The driver's text stays in toString (code that greps for 23505).
      expect('$e', contains('23505'));
      expect('$e', contains('tipo_norma_nome_uq'));
    });

    test('dpgsql', () {
      expect(map(_DpgsqlError('23505', 'uq'))!.constraint, 'uq');
    });

    test('dargres', () {
      expect(map(_DargresError('23505', _Notice('uq')))!.constraint, 'uq');
      expect(map(_DargresError('23505', null))!.constraint, isNull);
    });

    test('MySQL 1062 with and without the table prefix of MySQL 8', () {
      expect(
          map(_MySqlError(
                  1062, "Duplicate entry 'lei' for key 'tipo_norma.nome_uq'"))!
              .constraint,
          'nome_uq');
      expect(
          map(_MySqlError(1062, "Duplicate entry 'lei' for key 'nome_uq'"))!
              .constraint,
          'nome_uq');
      expect(map(_MySqlError(1586, 'Duplicate entry'))!.constraint, isNull);
    });

    test('other errors are not unique violations', () {
      expect(map(_PgError('23503', 'fk')), isNull); // foreign key
      expect(map(_PgError(null)), isNull);
      expect(map(_DpgsqlError('42P01', null)), isNull);
      expect(map(_DargresError(500, null)), isNull);
      expect(map(_MySqlError(1452, 'foreign key')), isNull);
      expect(map(StateError('23505')), isNull); // only the code field counts
      expect(map(Exception('duplicate key')), isNull);
    });

    test('an already mapped exception is returned as is', () {
      final e = map(_PgError('23505', 'uq'))!;
      expect(identical(map(e), e), isTrue);
    });
  });

  group('lockTable', () {
    late FakeConnection conn;
    setUp(() => conn = FakeConnection());

    QueryBuilder pg(String table) =>
        QueryBuilder(conn, QueryPostgresGrammar(), PostgresProcessor())
            .from(table);

    test('compiles every mode, schema-qualified and NOWAIT', () {
      final grammar = QueryPostgresGrammar();
      expect(
          grammar.compileLockTable(
              pg('normas.tipo_norma'), TableLockMode.exclusive),
          'lock table "normas"."tipo_norma" in exclusive mode');
      expect(
          grammar.compileLockTable(pg('t'), TableLockMode.accessExclusive,
              noWait: true),
          'lock table "t" in access exclusive mode nowait');
      expect(TableLockMode.values.map((m) => m.sql), [
        'access share',
        'row share',
        'row exclusive',
        'share update exclusive',
        'share',
        'share row exclusive',
        'exclusive',
        'access exclusive',
      ]);
    });

    test('rejects an alias', () {
      expect(
          () => QueryPostgresGrammar()
              .compileLockTable(pg('t as x'), TableLockMode.share),
          throwsArgumentError);
    });

    test('needs a transaction', () {
      expect(() => pg('t').lockTable(TableLockMode.share), throwsStateError);
    });

    test('MySQL is not supported', () {
      final query =
          QueryBuilder(conn, QueryMySqlGrammar(), MySqlProcessor()).from('t');
      expect(() => query.lockTable(TableLockMode.share),
          throwsA(isA<UnsupportedError>()));
    });
  });
}
