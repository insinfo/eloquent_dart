/// A notification received over a PostgreSQL `LISTEN` channel.
class DriverNotification {
  /// The channel the notification was sent on.
  final String channel;

  /// The optional payload string (empty when none was sent).
  final String payload;

  /// The backend process id of the notifying session.
  final int processId;

  const DriverNotification(this.channel, this.payload, this.processId);

  @override
  String toString() =>
      'DriverNotification(channel: $channel, payload: $payload, pid: $processId)';
}

/// Low-level, driver-specific capabilities that sit *beside* the query builder
/// — a typed escape hatch for features the SQL/query-builder abstraction cannot
/// express: bulk `COPY`, pipelining/batch, `LISTEN`/`NOTIFY`, large objects,
/// and direct access to the native driver connection.
///
/// Obtain one via `db.driver()` / `queryBuilder.driver()`, which returns `null`
/// when the active driver adapter does not support these features. Only the
/// `dpgsql` adapter implements it today.
abstract class DriverAccess {
  /// Whether bulk `COPY` (import/export) is supported.
  bool get supportsCopy;

  /// Whether `LISTEN`/`NOTIFY` is supported.
  bool get supportsListenNotify;

  /// Bulk-load [rows] into [table] using PostgreSQL `COPY ... FROM STDIN`
  /// (text format). Far faster than row-by-row inserts for large volumes.
  ///
  /// Each row is a list of values positionally matching [columns]. `null`
  /// becomes the COPY null token. Returns the number of rows written.
  Future<int> copyInRows(
    String table,
    List<String> columns,
    Iterable<List<Object?>> rows, {
    String delimiter,
    String nullString,
  });

  /// Run a raw `COPY ... FROM STDIN` command, feeding it the given byte [data]
  /// stream verbatim (caller controls the wire format).
  Future<void> copyInRaw(String copyFromSql, Stream<List<int>> data);

  /// Run a `COPY ... TO STDOUT` command and return the full output as text.
  Future<String> copyOutText(String copyToSql);

  /// Send a `NOTIFY` on [channel] with an optional [payload].
  Future<void> notify(String channel, [String? payload]);

  /// `LISTEN` on [channel] and stream notifications until the subscription is
  /// cancelled. Requires a dedicated (non-pooled) connection to stay open.
  Stream<DriverNotification> listen(String channel);

  /// Run [action] with the native driver connection object (e.g. a
  /// `DpgsqlConnection`), enabling pipelining, batch, large objects, etc.
  /// The connection is valid only for the duration of [action].
  Future<T> withRawConnection<T>(Future<T> Function(dynamic connection) action);

  /// Format a single COPY text-format line for [values].
  ///
  /// Exposed as a static helper so the escaping rules can be unit-tested
  /// without a database. Follows PostgreSQL COPY TEXT semantics: backslash,
  /// the delimiter, newline, and carriage-return are backslash-escaped; `null`
  /// values become [nullString].
  static String formatCopyTextRow(
    List<Object?> values, {
    String delimiter = '\t',
    String nullString = r'\N',
  }) {
    final buffer = StringBuffer();
    for (var i = 0; i < values.length; i++) {
      if (i > 0) buffer.write(delimiter);
      final value = values[i];
      if (value == null) {
        buffer.write(nullString);
      } else {
        buffer.write(_escapeCopyText(value.toString(), delimiter));
      }
    }
    buffer.write('\n');
    return buffer.toString();
  }

  static String _escapeCopyText(String s, String delimiter) {
    final buffer = StringBuffer();
    for (final rune in s.runes) {
      switch (rune) {
        case 0x5C: // backslash
          buffer.write(r'\\');
          break;
        case 0x0A: // newline
          buffer.write(r'\n');
          break;
        case 0x0D: // carriage return
          buffer.write(r'\r');
          break;
        case 0x09: // tab
          buffer.write(r'\t');
          break;
        default:
          if (delimiter.length == 1 && rune == delimiter.codeUnitAt(0)) {
            // Escape the delimiter if it is not already one of the above.
            buffer.write('\\');
            buffer.writeCharCode(rune);
          } else {
            buffer.writeCharCode(rune);
          }
      }
    }
    return buffer.toString();
  }
}
