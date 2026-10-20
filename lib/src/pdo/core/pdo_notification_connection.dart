import 'dart:async';

import '../../driver/driver_access.dart' show DriverNotification;

/// A dedicated PostgreSQL connection, outside any pool, that receives
/// `LISTEN` notifications. Created by `PDOInterface.openNotificationConnection`
/// and owned by a `PostgresNotificationListener`.
///
/// Each adapter supplies the native pieces; this class forwards the driver's
/// notifications and completes [done] when the driver reports the connection
/// closed. Drivers that never report it are covered by the listener's
/// heartbeat.
class PDONotificationConnection {
  PDONotificationConnection({
    required Stream<DriverNotification> notifications,
    required Future<void> Function(String sql, Duration timeout) execute,
    required Future<void> Function() close,
    Future<void>? closed,
  })  : _execute = execute,
        _close = close {
    _subscription = notifications.listen(
      _notifications.add,
      onError: (_) {},
      onDone: _markDone,
    );
    closed?.then((_) => _markDone(), onError: (_) => _markDone());
  }

  final Future<void> Function(String sql, Duration timeout) _execute;
  final Future<void> Function() _close;
  final _notifications = StreamController<DriverNotification>.broadcast();
  final _done = Completer<void>();
  late final StreamSubscription<DriverNotification> _subscription;

  /// Every notification received on this connection.
  Stream<DriverNotification> get notifications => _notifications.stream;

  /// Completes when the connection is closed or lost.
  Future<void> get done => _done.future;

  bool get isDone => _done.isCompleted;

  /// Runs a utility statement (`LISTEN`, `UNLISTEN`, `SELECT 1`).
  Future<void> execute(String sql, Duration timeout) {
    if (isDone) {
      return Future.error(StateError('The notification connection is closed.'));
    }
    return _execute(sql, timeout).timeout(timeout);
  }

  Future<void> close() async {
    _markDone();
    await _subscription.cancel();
    await _close();
  }

  void _markDone() {
    if (!_done.isCompleted) _done.complete();
    if (!_notifications.isClosed) _notifications.close();
  }
}
