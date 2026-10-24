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
    // PostgreSQL 14+ idle_session_timeout (issue #2).
    expect(lost(_SqlStateError('57P05', 'idle-session timeout')), isTrue);
    expect(
        lost(Exception('PostgresqlException: FATAL 57P05 terminando a '
            'conexão devido ao tempo limite de sessão ociosa')),
        isTrue); // dargres
    expect(
        lost(Exception('FATAL: terminating connection due to idle-session '
            'timeout')),
        isTrue);
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
    expect(lost(_MySqlError(1292, "Incorrect datetime value: '2013-02-30'")),
        isFalse);
    expect(
        lost(_SqlStateError('42601', 'syntax error at or near "57"')), isFalse);
    expect(lost(StateError('Bad state: no element')), isFalse);
    expect(lost(TimeoutExceptionLike()), isFalse);
  });

  test('a TLS handshake or certificate failure is not a lost connection', () {
    // A configuration error (sslmode verify-full against a self-signed
    // certificate, no TLS on the server): retrying only delays the error.
    expect(lost(HandshakeException('CERTIFICATE_VERIFY_FAILED')), isFalse);
    expect(lost(CertificateException('bad certificate')), isFalse);
    expect(
        lost(_DriverError('MySQLClientException: HandshakeException: '
            'Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED: '
            'self signed certificate)')),
        isFalse);
    // A TLS error in an open session is still a lost connection.
    expect(lost(TlsException('bad record mac')), isTrue);
    expect(lost(SocketException('Connection reset by peer')), isTrue);
  });
}

class _DriverError implements Exception {
  _DriverError(this.message);
  final String message;
  @override
  String toString() => message;
}

class TimeoutExceptionLike implements Exception {
  @override
  String toString() => 'TimeoutException after 0:00:30.000000';
}
