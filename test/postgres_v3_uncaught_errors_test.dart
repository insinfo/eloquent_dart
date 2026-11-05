// postgres 3.5.7 has errors no caller can catch, which end a process by default:
// a write to a socket the server reset, among others. The adapter opens its
// sockets in a zone that drops them, and the call itself still fails.
//
// A wrapper around the real socket makes the error deterministic on any OS.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

class _ResetSocket extends Stream<Uint8List> implements Socket {
  _ResetSocket(this.inner, this.failOnWrite);

  final Socket inner;
  final int failOnWrite;
  int writes = 0;
  final _done = Completer<dynamic>();

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      inner.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  void add(List<int> data) {
    writes++;
    if (writes == failOnWrite && !_done.isCompleted) {
      _done.completeError(const SocketException('Connection reset by peer'));
      inner.destroy();
    }
    if (writes < failOnWrite) inner.add(data);
  }

  @override
  Future get done => _done.future;

  @override
  Future flush() async {
    if (writes < failOnWrite) await inner.flush();
  }

  @override
  Future close() async {
    if (!_done.isCompleted) _done.complete(this);
    return inner.close();
  }

  @override
  void destroy() {
    if (!_done.isCompleted) _done.complete(this);
    inner.destroy();
  }

  @override
  bool setOption(SocketOption option, bool enabled) =>
      inner.setOption(option, enabled);

  @override
  InternetAddress get address => inner.address;

  @override
  InternetAddress get remoteAddress => inner.remoteAddress;

  @override
  int get port => inner.port;

  @override
  int get remotePort => inner.remotePort;

  @override
  void write(Object? object) => add(utf8.encode('$object'));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

List<int> _message(String type, List<int> body) {
  final length = ByteData(4)..setInt32(0, body.length + 4);
  return [type.codeUnitAt(0), ...length.buffer.asUint8List(), ...body];
}

final _loginOk = [
  ..._message('R', [0, 0, 0, 0]),
  ..._message('Z', [0x49]),
];

void main() {
  late ServerSocket server;

  setUp(() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((client) {
      var first = true;
      client.listen((_) {
        if (first) client.add(_loginOk);
        first = false;
      }, onError: (_) {});
    });
  });

  tearDown(() => server.close());

  for (final pool in [false, true]) {
    for (final (name, failOnWrite) in [('the startup', 1), ('a command', 2)]) {
      test(
          'postgres_v3${pool ? ' pool' : ''}: a reset while sending $name is '
          'not an uncaught error', () async {
        final uncaught = <Object>[];
        Object? callError;
        final finished = Completer<void>();
        runZonedGuarded(() {
          IOOverrides.runZoned(() async {
            final manager = Manager()
              ..addConnection({
                'driver': 'pgsql',
                'driver_implementation': 'postgres_v3',
                'host': '127.0.0.1',
                'port': server.port,
                'database': 'd',
                'username': 'u',
                'password': 'p',
                'sslmode': 'disable',
                'allowreconnect': false,
                'driver_options': {'connectTimeout': 2, 'queryTimeout': 2},
                if (pool) 'pool': true,
                if (pool) 'poolsize': 1,
              }, 'c');
            try {
              final db = await manager.connection('c');
              await db.selectOne('select 1').timeout(const Duration(seconds: 15));
            } catch (e) {
              callError = e;
            }
            try {
              await manager.getDatabaseManager().purge('c');
            } catch (_) {}
            await Future<void>.delayed(const Duration(milliseconds: 50));
            finished.complete();
          }, socketConnect: (host, int port,
              {sourceAddress, int sourcePort = 0, Duration? timeout}) async {
            // The root zone has no overrides.
            final real = await Zone.root.run(() => Socket.connect(host, port,
                sourceAddress: sourceAddress, timeout: timeout));
            return _ResetSocket(real, failOnWrite);
          });
        }, (e, s) => uncaught.add(e));
        await finished.future.timeout(const Duration(seconds: 40));
        expect(uncaught, isEmpty);
        expect(callError, isNotNull, reason: 'the call itself must fail');
      });
    }
  }
}
