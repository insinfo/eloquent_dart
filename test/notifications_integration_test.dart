// LISTEN/NOTIFY on the four PostgreSQL adapters (postgres, postgres_v3,
// dargres, dpgsql). Requires localhost:5432, database `banco_teste`,
// user/password `dart`/`dart` (and MariaDB on 3306 for the unsupported case).
@Tags(['integration'])
library;

import 'dart:async';

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

Map<String, dynamic> _pg(String driver,
        {bool pool = false, String? applicationName}) =>
    {
      'driver': 'pgsql',
      'driver_implementation': driver,
      'host': 'localhost',
      'port': '5432',
      'database': 'banco_teste',
      'username': 'dart',
      'password': 'dart',
      'charset': 'utf8',
      'schema': ['public'],
      'pool': pool,
      'poolsize': 2,
      if (applicationName != null) 'application_name': applicationName,
    };

const _wait = Duration(seconds: 5);

void main() {
  for (final driver in ['postgres', 'postgres_v3', 'dargres', 'dpgsql']) {
    group(driver, () {
      late Manager manager;
      late Connection db;
      late Connection other;

      setUp(() async {
        manager = Manager()
          ..addConnection(_pg(driver, pool: true), 'listen_$driver')
          ..addConnection(_pg(driver), 'notify_$driver');
        db = await manager.getConnection('listen_$driver');
        other = await manager.getConnection('notify_$driver');
      });

      tearDown(() async {
        await manager.getDatabaseManager().purge('listen_$driver');
        await manager.getDatabaseManager().purge('notify_$driver');
      });

      test('notify reaches the listener of another connection', () async {
        expect(db.supportsNotifications, isTrue);
        final received = StreamQueue(db.notifications('Canal_$driver'));
        await db.notificationListener.ready();
        expect(db.notificationListener.listening, {'Canal_$driver'});

        const payload = "olá 'mundo' \"aspas\" \\ ç";
        await other.notify('Canal_$driver', payload);
        await other.notify('Canal_$driver');
        await other.notify('canal_$driver', 'outro canal'); // case-sensitive

        final first = await received.next.timeout(_wait);
        expect(first.channel, 'Canal_$driver');
        expect(first.payload, payload);
        expect(first.processId, isNonZero);
        expect((await received.next.timeout(_wait)).payload, '');
        await received.cancel();
      });

      test('NOTIFY in a transaction is delivered on commit only', () async {
        final events = <String>[];
        final sub =
            db.notifications('tx_$driver').listen((n) => events.add(n.payload));
        await db.notificationListener.ready();

        await expectLater(
            other.transaction((ctx) async {
              await ctx.notify('tx_$driver', 'rollback');
              throw StateError('rollback');
            }),
            throwsStateError);

        final committed = Completer<void>();
        await other.transaction((ctx) async {
          await ctx.notify('tx_$driver', 'commit');
          await Future<void>.delayed(const Duration(milliseconds: 200));
          expect(events, isEmpty, reason: 'not delivered before COMMIT');
        });
        while (events.isEmpty && !committed.isCompleted) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(events, ['commit']);
        await sub.cancel();
      });

      test('the last cancel runs UNLISTEN and closes the connection',
          () async {
        final listener = db.notificationListener;
        final a = db.notifications('a_$driver').listen((_) {});
        final b = db.notifications('b_$driver').listen((_) {});
        await listener.ready();
        expect(listener.listening, {'a_$driver', 'b_$driver'});
        expect(listener.isConnected, isTrue);

        await a.cancel();
        await listener.ready();
        expect(listener.listening, {'b_$driver'});

        await b.cancel();
        await listener.ready();
        expect(listener.listening, isEmpty);
        expect(listener.isConnected, isFalse);
      });

      test('reconnects and listens again after the backend is killed',
          () async {
        final appName =
            'eloquent_listen_${driver}_${DateTime.now().microsecondsSinceEpoch}';
        manager.addConnection(
            _pg(driver, applicationName: appName), 'named_$driver');
        final named = await manager.getConnection('named_$driver');
        final listener = PostgresNotificationListener(
          named.getPdo().pdoInstance.openNotificationConnection,
          heartbeat: const Duration(milliseconds: 300),
          reconnectDelay: const Duration(milliseconds: 100),
        );
        final reconnected = listener.onReconnect.first;
        final received = StreamQueue(listener.channel('rc_$driver'));
        await listener.ready();

        // The application name identifies the LISTEN session (and the
        // single connection of `named`, which is terminated too).
        final pids = await other.select(
            'select pid from pg_stat_activity where application_name = ?',
            [appName]);
        expect(pids, isNotEmpty, reason: appName);
        for (final row in pids) {
          await other.select('select pg_terminate_backend(?::int)', [row['pid']]);
        }

        await reconnected.timeout(const Duration(seconds: 10));
        await listener.ready();
        expect(listener.listening, {'rc_$driver'});
        expect(listener.isConnected, isTrue);

        await other.notify('rc_$driver', 'depois');
        expect((await received.next.timeout(_wait)).payload, 'depois');
        await received.cancel();
        await listener.close();
        await manager.getDatabaseManager().purge('named_$driver');
      });
    });
  }

  test('MySQL has no LISTEN/NOTIFY', () async {
    final manager = Manager()
      ..addConnection({
        'driver': 'mysql',
        'host': 'localhost',
        'port': '3306',
        'database': 'banco_teste',
        'username': 'dart',
        'password': 'dart',
      }, 'mysql_notify');
    final db = await manager.getConnection('mysql_notify');
    expect(db.supportsNotifications, isFalse);
    expect(() => db.notify('x'), throwsUnsupportedError);
    expect(() => db.notifications('x'), throwsUnsupportedError);
    await manager.getDatabaseManager().purge('mysql_notify');
  });
}

/// Minimal pull-based reader over a stream (package:async's StreamQueue).
class StreamQueue<T> {
  StreamQueue(Stream<T> stream) {
    _subscription = stream.listen((event) {
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete(event);
      } else {
        _buffer.add(event);
      }
    });
  }

  late final StreamSubscription<T> _subscription;
  final _buffer = <T>[];
  final _waiters = <Completer<T>>[];

  Future<T> get next {
    if (_buffer.isNotEmpty) return Future.value(_buffer.removeAt(0));
    final waiter = Completer<T>();
    _waiters.add(waiter);
    return waiter.future;
  }

  Future<void> cancel() => _subscription.cancel();
}
