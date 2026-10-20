import 'dart:async';
import 'dart:math' as math;

import '../driver/driver_access.dart' show DriverNotification;
import '../pdo/core/operation_lock.dart';
import '../pdo/core/pdo_notification_connection.dart';

/// PostgreSQL `LISTEN` over one dedicated connection shared by every channel.
///
/// ```dart
/// final sub = db.notifications('tramita_pendente').listen((n) {
///   processarFila(); // n.payload has the NOTIFY payload
/// });
/// await db.notificationListener.ready(); // LISTEN is active
/// db.notificationListener.onReconnect.listen((_) => processarFila());
/// ```
///
/// - `LISTEN` runs when a channel gets its first subscriber and `UNLISTEN`
///   when its last subscriber cancels; with no channel left the connection is
///   closed.
/// - When the connection is lost (detected by the driver or by the
///   [heartbeat]), it reconnects with exponential backoff, runs `LISTEN`
///   again and emits [onReconnect]. Notifications sent while it was
///   disconnected are lost: treat [onReconnect] as "re-read the state".
/// - Failures never reach the channel streams; they are reported as data on
///   [onError].
class PostgresNotificationListener {
  PostgresNotificationListener(
    this._open, {
    this.heartbeat = const Duration(seconds: 30),
    this.reconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 30),
    this.commandTimeout = const Duration(seconds: 10),
  });

  final Future<PDONotificationConnection> Function() _open;

  /// Interval of the `SELECT 1` that detects a dead connection (a dropped
  /// network does not always close the socket). `Duration.zero` disables it.
  final Duration heartbeat;

  /// First delay before reconnecting; doubles up to [maxReconnectDelay].
  final Duration reconnectDelay;
  final Duration maxReconnectDelay;

  /// Timeout of `LISTEN`, `UNLISTEN` and the heartbeat.
  final Duration commandTimeout;

  final _controllers = <String, StreamController<DriverNotification>>{};
  final _listened = <String>{};
  final _onReconnect = StreamController<void>.broadcast();
  final _onError = StreamController<Object>.broadcast();
  final _readyWaiters = <Completer<void>>[];
  final _lock = OperationLock();

  PDONotificationConnection? _connection;
  StreamSubscription<DriverNotification>? _subscription;
  Timer? _heartbeatTimer;
  Completer<void>? _sleep;
  bool _running = false;
  bool _dirty = false;
  bool _closed = false;
  bool _lostConnection = false;

  /// Notifications on [channel] (case-sensitive, as in `pg_notify`).
  Stream<DriverNotification> channel(String channel) {
    if (_closed) {
      throw StateError('The notification listener is closed.');
    }
    final controller = _controllers.putIfAbsent(
        channel,
        () => StreamController<DriverNotification>.broadcast(
              onListen: _schedule,
              onCancel: _schedule,
            ));
    return controller.stream;
  }

  /// Emits after a lost connection was restored and `LISTEN` ran again.
  Stream<void> get onReconnect => _onReconnect.stream;

  /// Connection and `LISTEN` failures (the listener keeps retrying).
  Stream<Object> get onError => _onError.stream;

  /// Whether the dedicated connection is open.
  bool get isConnected => _connection != null;

  /// Channels with an active `LISTEN`.
  Set<String> get listening => Set.unmodifiable(_listened);

  /// Completes when every subscribed channel has an active `LISTEN` (it
  /// waits through reconnection attempts; add a `.timeout` if needed).
  Future<void> ready() {
    if (_isSynced()) return Future.value();
    final waiter = Completer<void>();
    _readyWaiters.add(waiter);
    return waiter.future;
  }

  /// Closes the connection and every channel stream.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final sleep = _sleep;
    if (sleep != null && !sleep.isCompleted) sleep.complete();
    _heartbeatTimer?.cancel();
    final connection = _connection;
    _connection = null;
    _listened.clear();
    await _subscription?.cancel();
    if (connection != null) {
      try {
        await connection.close();
      } catch (_) {}
    }
    for (final controller in _controllers.values) {
      await controller.close();
    }
    _controllers.clear();
    _completeReady();
    await _onReconnect.close();
    await _onError.close();
  }

  Set<String> get _wanted => {
        for (final entry in _controllers.entries)
          if (entry.value.hasListener) entry.key
      };

  bool _isSynced() {
    if (_closed) return true;
    if (_running || _dirty) return false;
    final wanted = _wanted;
    return wanted.length == _listened.length && _listened.containsAll(wanted);
  }

  void _completeReady() {
    if (!_isSynced()) return;
    final waiters = List.of(_readyWaiters);
    _readyWaiters.clear();
    for (final waiter in waiters) {
      waiter.complete();
    }
  }

  /// Serializes reconciliation: a change during a run triggers another run.
  void _schedule() {
    if (_closed) return;
    if (_running) {
      _dirty = true;
      return;
    }
    _running = true;
    () async {
      try {
        do {
          _dirty = false;
          await _reconcile();
        } while (_dirty && !_closed);
      } finally {
        _running = false;
        _completeReady();
      }
    }();
  }

  Future<void> _reconcile() async {
    final wanted = _wanted;
    if (wanted.isEmpty) {
      await _drop();
      return;
    }
    final connection = _connection ?? await _connect();
    if (connection == null) return;
    try {
      await _lock.run(() async {
        for (final channel in wanted.difference(_listened)) {
          await connection.execute('LISTEN ${_quote(channel)}', commandTimeout);
          _listened.add(channel);
        }
        for (final channel in _listened.difference(wanted)) {
          await connection.execute(
              'UNLISTEN ${_quote(channel)}', commandTimeout);
          _listened.remove(channel);
        }
      });
    } catch (error) {
      _report(error);
      await _lost(connection);
      if (!_closed) await _wait(reconnectDelay);
      return;
    }
    if (_lostConnection) {
      _lostConnection = false;
      _onReconnect.add(null);
    }
  }

  Future<PDONotificationConnection?> _connect() async {
    var attempt = 0;
    while (!_closed) {
      try {
        final connection = await _open();
        if (_closed) {
          await connection.close();
          return null;
        }
        _connection = connection;
        _listened.clear();
        _subscription = connection.notifications.listen(_dispatch);
        connection.done.then((_) => _lost(connection));
        _startHeartbeat(connection);
        return connection;
      } catch (error) {
        _report(error);
        final factor = math.pow(2, math.min(attempt++, 16)).toInt();
        final delay = reconnectDelay * factor;
        await _wait(delay > maxReconnectDelay ? maxReconnectDelay : delay);
      }
    }
    return null;
  }

  Future<void> _wait(Duration delay) {
    final sleep = _sleep = Completer<void>();
    final timer = Timer(delay, () {
      if (!sleep.isCompleted) sleep.complete();
    });
    return sleep.future.whenComplete(timer.cancel);
  }

  void _startHeartbeat(PDONotificationConnection connection) {
    _heartbeatTimer?.cancel();
    if (heartbeat <= Duration.zero) return;
    var beating = false;
    _heartbeatTimer = Timer.periodic(heartbeat, (_) async {
      if (beating || !identical(_connection, connection)) return;
      beating = true;
      try {
        await _lock.run(() => connection.execute('SELECT 1', commandTimeout));
      } catch (error) {
        _report(error);
        await _lost(connection);
      } finally {
        beating = false;
      }
    });
  }

  /// Forgets [connection] and schedules a reconnection.
  Future<void> _lost(PDONotificationConnection connection) async {
    if (!identical(_connection, connection)) return;
    _connection = null;
    _listened.clear();
    _heartbeatTimer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    try {
      await connection.close();
    } catch (_) {}
    if (_closed) return;
    _lostConnection = true;
    _schedule();
  }

  /// Closes the connection when no channel is wanted.
  Future<void> _drop() async {
    final connection = _connection;
    if (connection == null) return;
    _connection = null;
    _listened.clear();
    _heartbeatTimer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    try {
      await connection.close();
    } catch (_) {}
  }

  void _dispatch(DriverNotification notification) {
    final controller = _controllers[notification.channel];
    if (controller != null && controller.hasListener) {
      controller.add(notification);
    }
  }

  void _report(Object error) {
    if (!_onError.isClosed) _onError.add(error);
  }

  static String _quote(String channel) =>
      '"${channel.replaceAll('"', '""')}"';
}
