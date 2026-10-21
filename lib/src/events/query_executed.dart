import '../connection.dart';

/// A statement that ran (or failed) on a connection, as delivered to
/// [Connection.listen] listeners — Laravel's `QueryExecuted` event.
class QueryExecuted {
  QueryExecuted({
    required this.sql,
    required this.bindings,
    required this.time,
    required this.connection,
    this.error,
  });

  /// The SQL with `?` placeholders.
  final String sql;

  /// The bindings, before driver-specific conversion.
  final List<dynamic> bindings;

  /// Wall-clock time until the result (or the error) was available.
  final Duration time;

  /// The connection (or transaction connection) that ran the statement.
  final Connection connection;

  /// The error the statement raised, or `null` when it succeeded.
  final Object? error;

  bool get failed => error != null;

  /// The configured name of the connection, if any.
  String? get connectionName => connection.getName()?.toString();

  /// The SQL with the bindings inlined, for logs and debugging only. Never
  /// execute it: escaping is best-effort.
  String toRawSql() =>
      connection.getQueryGrammar().substituteBindingsIntoRawSql(
          sql, connection.prepareBindings(List<dynamic>.of(bindings)));

  @override
  String toString() =>
      'QueryExecuted(${time.inMicroseconds / 1000} ms${failed ? ', failed' : ''}): $sql';
}
