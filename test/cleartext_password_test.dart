// The password goes in clear text only to a verified server or by explicit
// choice, on every adapter whose driver lets us choose. postgres_v3 is not here:
// the postgres package has no such option.
//
// A fake server on loopback asks for the password, no database needed. The TLS
// one uses the certificates in test/fixtures/tls.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

const _dir = 'test/fixtures/tls';
const _password = 'secret-password';

List<int> _message(String type, List<int> body) {
  final length = ByteData(4)..setInt32(0, body.length + 4);
  return [type.codeUnitAt(0), ...length.buffer.asUint8List(), ...body];
}

final _askCleartext = _message('R', [0, 0, 0, 3]);
final _refused = _message('E', [
  ...latin1.encode('SFATAL\x00VFATAL\x00C28P01\x00Mrefused by fake server\x00'),
  0,
]);

bool _isSslRequest(List<int> chunk) =>
    chunk.length >= 8 &&
    ByteData.sublistView(Uint8List.fromList(chunk)).getInt32(4) == 80877103;

class _Trap {
  bool received = false;

  void onMessage(List<int> chunk, void Function(List<int>) send) {
    if (utf8.decode(chunk, allowMalformed: true).contains(_password)) {
      received = true;
      send(_refused);
    } else {
      send(_askCleartext);
    }
  }
}

Future<ServerSocket> _server(_Trap trap) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((client) {
    // ignore: cancel_subscriptions
    late StreamSubscription<Uint8List> sub;
    sub = client.listen((chunk) async {
      if (!_isSslRequest(chunk)) {
        trap.onMessage(chunk, client.add);
        return;
      }
      sub.pause();
      client.add([0x53]);
      await client.flush();
      try {
        final secure = await SecureSocket.secureServer(
            client,
            SecurityContext()
              ..useCertificateChain('$_dir/server.pem')
              ..usePrivateKey('$_dir/server-key.pem'));
        secure.listen((data) => trap.onMessage(data, secure.add),
            onError: (_) {});
      } catch (_) {}
    }, onError: (_) {});
  });
  return server;
}

Future<void> _connect(int port, String driver, bool pool,
    Map<String, dynamic> extra) async {
  final manager = Manager()
    ..addConnection({
      'driver': 'pgsql',
      'driver_implementation': driver,
      'host': 'localhost',
      'port': port,
      'database': 'd',
      'username': 'u',
      'password': _password,
      if (pool) 'pool': true,
      if (pool) 'poolsize': 1,
      ...extra,
    }, 'c');
  try {
    final db = await manager.connection('c');
    await db.select('select 1').timeout(const Duration(seconds: 10));
  } catch (_) {
    // The fake server never lets it connect.
  }
  try {
    await manager.getDatabaseManager().purge('c');
  } catch (_) {}
  await Future<void>.delayed(const Duration(milliseconds: 50));
}

void main() {
  const optIn = {
    'postgres': {'allowClearTextPassword': true},
    'dargres': {'allowCleartextPassword': true},
    'dpgsql': {'Allow Cleartext Password': 'true'},
  };

  for (final driver in optIn.keys) {
    for (final pool in [false, true]) {
      group('$driver${pool ? ' pool' : ''}', () {
        late _Trap trap;
        late ServerSocket server;

        setUp(() async {
          trap = _Trap();
          server = await _server(trap);
        });
        tearDown(() => server.close());

        test('not sent without TLS', () async {
          await _connect(server.port, driver, pool, {});
          expect(trap.received, isFalse);
        });

        test('not sent with sslmode require, which does not verify', () async {
          await _connect(server.port, driver, pool, {'sslmode': 'require'});
          expect(trap.received, isFalse);
        });

        test('sent with the driver option', () async {
          await _connect(
              server.port, driver, pool, {'driver_options': optIn[driver]});
          expect(trap.received, isTrue);
        });

        if (driver != 'postgres') {
          test('sent to a verified server', () async {
            await _connect(server.port, driver, pool, {
              'sslmode': 'verify-full',
              'sslrootcert': '$_dir/ca.pem',
            });
            expect(trap.received, isTrue);
          });
        }
      });
    }
  }
}
