import 'dart:async';

import 'package:dpgsql/dpgsql.dart';

import '../../driver/driver_access.dart';
import 'dpgsql_pdo.dart';

/// [DriverAccess] implementation for the `dpgsql` adapter.
///
/// Surfaces dpgsql capabilities that the query-builder abstraction cannot
/// express: bulk `COPY`, `LISTEN`/`NOTIFY`, and direct access to the native
/// [DpgsqlConnection] (for pipelining, batch, large objects, etc.).
class DpgsqlDriverAccess extends DriverAccess {
  /// Owning PDO (pooled/single mode) — used to lease connections per operation.
  final DpgsqlPDO? _pdo;

  /// Fixed connection (transaction mode) — used directly, never closed here.
  final DpgsqlConnection? _fixedConnection;

  DpgsqlDriverAccess.forPdo(DpgsqlPDO pdo)
      : _pdo = pdo,
        _fixedConnection = null;

  DpgsqlDriverAccess.forConnection(DpgsqlConnection connection)
      : _pdo = null,
        _fixedConnection = connection;

  @override
  bool get supportsCopy => true;

  @override
  bool get supportsListenNotify => true;

  /// Run [action] with a driver connection, respecting pooled vs. transaction
  /// ownership semantics.
  Future<T> _run<T>(Future<T> Function(DpgsqlConnection connection) action) {
    final fixed = _fixedConnection;
    if (fixed != null) {
      return action(fixed);
    }
    return _pdo!.useConnection(action);
  }

  @override
  Future<int> copyInRows(
    String table,
    List<String> columns,
    Iterable<List<Object?>> rows, {
    String delimiter = '\t',
    String nullString = r'\N',
  }) {
    final colList = columns.map((c) => '"$c"').join(', ');
    final withClause = "with (format text, delimiter '$delimiter', "
        "null '${nullString.replaceAll("'", "''")}')";
    final sql = 'COPY $table ($colList) FROM STDIN $withClause';

    return _run<int>((connection) async {
      final stream = await connection.beginTextImport(sql);
      var count = 0;
      try {
        for (final row in rows) {
          await stream.writeString(
            DriverAccess.formatCopyTextRow(
              row,
              delimiter: delimiter,
              nullString: nullString,
            ),
          );
          count++;
        }
        await stream.complete();
      } catch (_) {
        try {
          await stream.cancel();
        } catch (_) {}
        rethrow;
      }
      return count;
    });
  }

  @override
  Future<void> copyInRaw(String copyFromSql, Stream<List<int>> data) {
    return _run<void>((connection) async {
      final stream = await connection.beginRawBinaryCopy(copyFromSql);
      try {
        await stream.writeStream(data);
        await stream.complete();
      } catch (_) {
        try {
          await stream.cancel();
        } catch (_) {}
        rethrow;
      }
    });
  }

  @override
  Future<String> copyOutText(String copyToSql) {
    return _run<String>((connection) async {
      final stream = await connection.beginTextExport(copyToSql);
      return stream.readAsString();
    });
  }

  @override
  Future<void> notify(String channel, [String? payload]) {
    return _run<void>((connection) async {
      final command = payload == null
          ? 'NOTIFY "$channel"'
          : "NOTIFY \"$channel\", '${payload.replaceAll("'", "''")}'";
      final cmd = connection.createCommand(command);
      await cmd.executeNonQuery();
    });
  }

  @override
  Stream<DriverNotification> listen(String channel) {
    final pdo = _pdo;
    if (pdo == null) {
      throw UnsupportedError(
        'listen() requires a poolable/single DpgsqlPDO; it is not available '
        'from within a transaction context.',
      );
    }

    late StreamController<DriverNotification> controller;
    DpgsqlConnection? connection;
    StreamSubscription? sub;

    Future<void> start() async {
      connection = await pdo.openDedicatedConnection();
      final cmd = connection!.createCommand('LISTEN "$channel"');
      await cmd.executeNonQuery();
      sub = connection!.notifications.listen((e) {
        if (e.channel == channel) {
          controller.add(DriverNotification(e.channel, e.payload, e.pid));
        }
      });
    }

    Future<void> stop() async {
      await sub?.cancel();
      await connection?.close();
      connection = null;
    }

    controller = StreamController<DriverNotification>(
      onListen: () {
        start().catchError(controller.addError);
      },
      onCancel: stop,
    );

    return controller.stream;
  }

  @override
  Future<T> withRawConnection<T>(
      Future<T> Function(dynamic connection) action) {
    return _run<T>((connection) => action(connection));
  }
}
