import 'dart:async';

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

/// In-memory notification connection: records statements, lets the test
/// push notifications and simulate a lost connection.
class _FakeServer {
  final connections = <_FakeConnection>[];
  final statements = <String>[];
  int failOpens = 0;
  bool failHeartbeat = false;

  Future<PDONotificationConnection> open() async {
    if (failOpens > 0) {
      failOpens--;
      throw StateError('connection refused');
    }
    final fake = _FakeConnection(this);
    connections.add(fake);
    return fake.pdo;
  }

  _FakeConnection get last => connections.last;
}

class _FakeConnection {
  _FakeConnection(this.server) {
    pdo = PDONotificationConnection(
      notifications: _incoming.stream,
      execute: (sql, timeout) async {
        if (sql == 'SELECT 1' && server.failHeartbeat) {
          throw StateError('socket is dead');
        }
        server.statements.add(sql);
      },
      close: () async {
        closed = true;
      },
      closed: _lost.future,
    );
  }

  final _FakeServer server;
  late final PDONotificationConnection pdo;
  final _incoming = StreamController<DriverNotification>();
  final _lost = Completer<void>();
  bool closed = false;

  void send(String channel, String payload) =>
      _incoming.add(DriverNotification(channel, payload, 42));

  void kill() => _lost.complete();
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  late _FakeServer server;
  late PostgresNotificationListener listener;

  setUp(() {
    server = _FakeServer();
    listener = PostgresNotificationListener(server.open,
        heartbeat: Duration.zero,
        reconnectDelay: const Duration(milliseconds: 5),
        maxReconnectDelay: const Duration(milliseconds: 20));
  });

  tearDown(() => listener.close());

  test('LISTEN on first subscriber, quoted; dispatch by channel', () async {
    final a = <String>[];
    final b = <String>[];
    final subA = listener.channel('Fila').listen((n) => a.add(n.payload));
    final subB = listener.channel('outro"x').listen((n) => b.add(n.payload));
    await listener.ready();

    expect(server.connections, hasLength(1), reason: 'one shared connection');
    expect(server.statements, ['LISTEN "Fila"', 'LISTEN "outro""x"']);

    server.last.send('Fila', '1');
    server.last.send('outro"x', '2');
    server.last.send('fila', 'other case');
    await _settle();
    expect(a, ['1']);
    expect(b, ['2']);
    await subA.cancel();
    await subB.cancel();
  });

  test('a second subscriber reuses the LISTEN; the last cancel UNLISTENs',
      () async {
    final s1 = listener.channel('c').listen((_) {});
    final s2 = listener.channel('c').listen((_) {});
    await listener.ready();
    expect(server.statements, ['LISTEN "c"']);

    await s1.cancel();
    await listener.ready();
    expect(server.statements, ['LISTEN "c"']);

    final keep = listener.channel('d').listen((_) {});
    await s2.cancel();
    await listener.ready();
    expect(server.statements, ['LISTEN "c"', 'LISTEN "d"', 'UNLISTEN "c"']);
    expect(listener.listening, {'d'});

    await keep.cancel();
    await listener.ready();
    expect(listener.isConnected, isFalse);
    expect(server.last.closed, isTrue);
  });

  test('reconnects after the connection is lost and emits onReconnect',
      () async {
    final received = <String>[];
    listener.channel('c').listen((n) => received.add(n.payload));
    await listener.ready();
    final reconnected = listener.onReconnect.first;

    server.failOpens = 2; // two refused attempts before it comes back
    final errors = <Object>[];
    listener.onError.listen(errors.add);
    server.last.kill();

    await reconnected.timeout(const Duration(seconds: 2));
    await listener.ready();
    expect(server.connections, hasLength(2));
    expect(errors, hasLength(2));
    expect(server.statements, ['LISTEN "c"', 'LISTEN "c"']);

    server.last.send('c', 'depois');
    await _settle();
    expect(received, ['depois']);
  });

  test('the heartbeat detects a dead connection', () async {
    final beating = PostgresNotificationListener(server.open,
        heartbeat: const Duration(milliseconds: 10),
        reconnectDelay: const Duration(milliseconds: 5));
    beating.channel('c').listen((_) {});
    await beating.ready();
    final reconnected = beating.onReconnect.first;
    server.failHeartbeat = true;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    server.failHeartbeat = false;
    await reconnected.timeout(const Duration(seconds: 2));
    expect(server.connections.length, greaterThanOrEqualTo(2));
    expect(server.connections.first.closed, isTrue);
    await beating.close();
  });

  test('close() closes the connection and the channel streams', () async {
    final done = Completer<void>();
    listener.channel('c').listen((_) {}, onDone: done.complete);
    await listener.ready();
    await listener.close();
    await done.future.timeout(const Duration(seconds: 1));
    expect(server.last.closed, isTrue);
    expect(() => listener.channel('x'), throwsStateError);
  });

  test('ready() waits through refused connections', () async {
    server.failOpens = 3;
    listener.channel('c').listen((_) {});
    await listener.ready().timeout(const Duration(seconds: 2));
    expect(listener.listening, {'c'});
  });
}
