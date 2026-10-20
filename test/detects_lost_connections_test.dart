import 'dart:io';

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

class _Detector with DetectsLostConnections {}

/// Shapes of the driver exceptions: dpgsql (`sqlState`), postgres/dargres
/// (`code`) and mysql_dart (`errorCode`).
class _SqlStateError implements Exception {
  _SqlStateError(this.sqlState, this.message);
  final String sqlState;
  final String message;
  @override
  String toString() => 'PostgresException: $sqlState: $message';
}

class _CodeError implements Exception {
  _CodeError(this.code);
  final String code;
  @override
  String toString() => 'PostgreSQLException: $code';
}

class _MySqlError implements Exception {
  _MySqlError(this.errorCode, this.message);
  final int errorCode;
  final String message;
  @override
  String toString() => 'MySQLServerException [$errorCode]: $message';
}

void main() {
  final detector = _Detector();
  bool lost(Object e) => detector.causedByLostConnection(e);

  test('messages measured from the adapters after pg_terminate_backend/KILL',
      () {
    expect(
        lost(Exception('PostgreSQLSeverity.error : Attempting to execute '
            'query, but connection is not open.')),
        isTrue); // postgres, postgres_v3
    expect(
        lost(Exception('PostgresqlException: FATAL 57P01 terminando a '
            'conexão devido a um comando do administrador')),
        isTrue); // dargres
    expect(lost(StateError('EOF antes de ler 5 bytes')), isTrue); // dpgsql
    expect(
        lost(Exception('MySQLClientException: Can not execute query: '
            'connection closed')),
        isTrue); // mysql_dart
    expect(lost(const SocketException('Write failed')), isTrue);
  });

  test('structured codes', () {
    expect(lost(_SqlStateError('08006', 'connection failure')), isTrue);
    expect(lost(_SqlStateError('57P01', 'admin shutdown')), isTrue);
    expect(lost(_CodeError('08003')), isTrue);
    expect(lost(_MySqlError(2006, 'MySQL server has gone away')), isTrue);
    expect(lost(_MySqlError(1927, 'Connection was killed')), isTrue);
    expect(lost(Exception('MySQLServerException [2013]: Lost connection')),
        isTrue);
  });

  test('ordinary errors are not retried', () {
    expect(lost(_SqlStateError('23505', 'duplicate key')), isFalse);
    // Data that looks like a code: a CEP and a year.
    expect(
        lost(_SqlStateError('23505',
            'duplicate key value violates unique constraint: (cep)=(08001-000)')),
        isFalse);
    expect(
        lost(_MySqlError(1292, "Incorrect datetime value: '2013-02-30'")),
        isFalse);
    expect(lost(_SqlStateError('42601', 'syntax error at or near "57"')),
        isFalse);
    expect(lost(StateError('Bad state: no element')), isFalse);
    expect(lost(TimeoutExceptionLike()), isFalse);
  });
}

class TimeoutExceptionLike implements Exception {
  @override
  String toString() => 'TimeoutException after 0:00:30.000000';
}
