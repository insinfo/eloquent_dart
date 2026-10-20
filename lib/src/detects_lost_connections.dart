import 'dart:io';

mixin DetectsLostConnections {
  /// PostgreSQL admin/crash shutdown and "cannot connect now". Safe to match
  /// in a message; the connection_exception class (08xxx) is only read from
  /// the exception's code, since 08001 can also be data (a CEP, for example).
  static final _lostSqlStateInMessage = RegExp(r'\b57P0[123]\b');

  /// MySQL/MariaDB errors of a lost connection: 2002 can't connect, 2006
  /// gone away, 2013 lost during query, 1053 shutdown in progress, 1927
  /// connection killed (MariaDB), 4031 disconnected for inactivity.
  static const _lostMySqlCodes = {2002, 2006, 2013, 1053, 1927, 4031};

  /// `MySQLServerException [2006]: ...`
  static final _mySqlCodeInMessage = RegExp(r'\[(\d{4})\]');

  /// Messages (lower case) seen from the adapters when the server closed the
  /// connection, plus the PostgreSQL/MySQL entries of Laravel's list.
  static const _lostMessages = [
    // postgres (postgres_fork), postgres_v3
    'connection is not open',
    'connection is closed',
    // mysql_dart
    'connection closed',
    // dpgsql: the socket ended in the middle of a read
    'eof antes de ler',
    // dargres / pools
    "can't create a connection",
    // Laravel (PostgreSQL and MySQL)
    'server has gone away',
    'no connection to the server',
    'lost connection',
    'server closed the connection unexpectedly',
    'ssl connection has been closed unexpectedly',
    'error writing data to the connection',
    'connection reset by peer',
    'broken pipe',
    'connection refused',
    'connection timed out',
    'could not connect to server',
    'could not translate host name',
    'temporary failure in name resolution',
    'terminating connection due to administrator command',
    'the database system is shutting down',
    'the database system is starting up',
    'connection was killed',
  ];

  ///
  /// Whether [e] means the connection to the server was lost, so the
  /// statement may be retried on a new connection (outside transactions).
  ///
  bool causedByLostConnection(dynamic e) {
    // Network level: the socket was closed, reset or could not be opened.
    if (e is SocketException || e is TlsException) return true;

    final code = _errorCode(e);
    if (code is String &&
        (code.startsWith('08') || _lostSqlStateInMessage.hasMatch(code))) {
      return true;
    }
    if (code is int && _lostMySqlCodes.contains(code)) return true;

    final message = '$e';
    if (_lostSqlStateInMessage.hasMatch(message)) return true;
    final mySqlCode = _mySqlCodeInMessage.firstMatch(message);
    if (mySqlCode != null &&
        _lostMySqlCodes.contains(int.parse(mySqlCode.group(1)!))) {
      return true;
    }
    final lower = message.toLowerCase();
    for (final text in _lostMessages) {
      if (lower.contains(text)) return true;
    }
    return false;
  }

  /// The SQLSTATE (`sqlState`/`code` on the PostgreSQL drivers) or the MySQL
  /// `errorCode` of [e], when it has one.
  static dynamic _errorCode(dynamic e) {
    for (final read in <dynamic Function(dynamic)>[
      (x) => x.sqlState,
      (x) => x.code,
      (x) => x.errorCode,
    ]) {
      try {
        final value = read(e);
        if (value is String || value is int) return value;
      } catch (_) {
        // The exception has no such field.
      }
    }
    return null;
  }
}
