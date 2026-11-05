// The sslrootcert, sslcert, sslkey, sslpassword and security_context config
// keys on every adapter, single connection and pool: a private CA verifies the
// server, the client certificate reaches it, and settings that cannot be
// honored fail before anything is sent.
//
// Fake servers on loopback, no database needed: they speak enough of the
// PostgreSQL and MySQL handshakes to reach TLS, with the certificates in
// test/fixtures/tls (made for these tests only, see generate.sh), and refuse
// the login. The login message reaching them means the client accepted the
// server: it carries the user name.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

const _dir = 'test/fixtures/tls';

abstract class _FakeServer {
  _FakeServer(this._socket, this._context, this._requireClient) {
    _socket.listen(_serve);
  }

  final ServerSocket _socket;
  final SecurityContext _context;
  final bool _requireClient;

  bool loginReceived = false;
  String? clientSubject;

  int get port => _socket.port;

  /// Sent when the client connects, before it sends anything.
  List<int> get greeting => const [];

  bool isTlsRequest(List<int> chunk);

  /// The answer to the TLS request, in plain text.
  List<int> get tlsAccepted => const [];

  /// The answer to the login, under TLS.
  List<int> get loginRefused;

  static SecurityContext context(String certificate, bool requireClient) {
    final context = SecurityContext()
      ..useCertificateChain('$_dir/$certificate.pem')
      ..usePrivateKey('$_dir/$certificate-key.pem');
    if (requireClient) {
      context
        ..setTrustedCertificates('$_dir/ca.pem')
        ..setClientAuthorities('$_dir/ca.pem');
    }
    return context;
  }

  void _serve(Socket client) {
    if (greeting.isNotEmpty) client.add(greeting);
    // ignore: cancel_subscriptions
    late StreamSubscription<Uint8List> sub;
    sub = client.listen((chunk) async {
      if (!isTlsRequest(chunk)) {
        client.destroy();
        return;
      }
      sub.pause();
      if (tlsAccepted.isNotEmpty) client.add(tlsAccepted);
      await client.flush();
      try {
        final secure = await SecureSocket.secureServer(client, _context,
            requireClientCertificate: _requireClient);
        clientSubject = secure.peerCertificate?.subject;
        secure.listen((_) async {
          loginReceived = true;
          secure.add(loginRefused);
          await secure.flush();
          secure.destroy();
        }, onError: (_) {});
      } catch (_) {
        // The handshake failed: the client rejected the certificate, or the
        // server rejected the client.
      }
    }, onError: (_) {});
  }

  Future<void> close() => _socket.close();
}

class _FakePostgres extends _FakeServer {
  _FakePostgres(super.socket, super.context, super.requireClient);

  @override
  bool isTlsRequest(List<int> chunk) {
    if (chunk.length < 8) return false;
    final data = ByteData.sublistView(Uint8List.fromList(chunk));
    return data.getInt32(0) == 8 && data.getInt32(4) == 80877103;
  }

  @override
  List<int> get tlsAccepted => const [83]; // 'S'

  @override
  List<int> get loginRefused {
    final fields = latin1
        .encode('SFATAL\x00VFATAL\x00C28P01\x00Mfake login refused\x00\x00');
    final length = ByteData(4)..setInt32(0, fields.length + 4);
    return [69, ...length.buffer.asUint8List(), ...fields]; // 'E'
  }
}

class _FakeMySql extends _FakeServer {
  _FakeMySql(super.socket, super.context, super.requireClient);

  static const _authData = [1, 2, 3, 4, 5, 6, 7, 8];

  /// A protocol 10 handshake with PROTOCOL_41, SSL, SECURE_CONNECTION and
  /// PLUGIN_AUTH.
  @override
  List<int> get greeting {
    final payload = <int>[
      10,
      ...latin1.encode('8.0.0-fake\x00'),
      1, 0, 0, 0, // thread id
      ..._authData,
      0,
      0x01, 0x8A, // capabilities, low bytes
      45, // utf8mb4_general_ci
      2, 0, // status
      0x08, 0x00, // capabilities, high bytes
      21, // auth data length
      ...List.filled(10, 0),
      ...List.filled(12, 7),
      0,
      ...latin1.encode('mysql_native_password\x00'),
    ];
    return _packet(0, payload);
  }

  static List<int> _packet(int sequence, List<int> payload) => [
        payload.length & 0xff,
        payload.length >> 8 & 0xff,
        payload.length >> 16 & 0xff,
        sequence,
        ...payload,
      ];

  @override
  bool isTlsRequest(List<int> chunk) => chunk.length == 36 && chunk[3] == 1;

  @override
  List<int> get loginRefused => _packet(3, [
        0xff,
        0x15, 0x04, // error 1045
        ...latin1.encode('#28000fake login refused'),
      ]);
}

/// The driver variants, with the config keys that select them.
class _Variant {
  const _Variant(this.name, this.start, this.config);

  final String name;
  final _FakeServer Function(ServerSocket, SecurityContext, bool) start;
  final Map<String, dynamic> config;
}

final _variants = [
  for (final pool in [false, true]) ...[
    _Variant('mysql${pool ? ' pool' : ''}', _FakeMySql.new,
        {'driver': 'mysql', if (pool) 'pool': true, if (pool) 'poolsize': 1}),
    for (final driver in ['postgres', 'postgres_v3', 'dargres', 'dpgsql'])
      _Variant('$driver${pool ? ' pool' : ''}', _FakePostgres.new, {
        'driver': 'pgsql',
        'driver_implementation': driver,
        if (pool) 'pool': true,
        if (pool) 'poolsize': 1,
      }),
  ],
];

Future<_FakeServer> _start(_Variant variant,
    {String certificate = 'server', bool requireClient = false}) async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final server = variant.start(
      socket, _FakeServer.context(certificate, requireClient), requireClient);
  addTearDown(server.close);
  return server;
}

/// Connects and runs a query; the fake servers refuse the login, so this
/// always fails. Returns the error.
Future<Object?> _connect(_Variant variant, _FakeServer server,
    Map<String, dynamic> extra) async {
  final manager = Manager()
    ..addConnection({
      ...variant.config,
      'host': 'localhost',
      'port': server.port,
      'database': 'db',
      'username': 'user',
      'password': 'password',
      ...extra,
    }, 'tls');
  Object? error;
  try {
    final db = await manager.connection('tls');
    await db.select('select 1').timeout(const Duration(seconds: 20));
  } catch (e) {
    error = e;
  }
  try {
    await manager.getDatabaseManager().purge('tls');
  } catch (_) {}
  // Lets the fake server see what the client sent before the assertions.
  await Future<void>.delayed(const Duration(milliseconds: 50));
  return error;
}

void main() {
  for (final variant in _variants) {
    group(variant.name, () {
      test('sslrootcert verifies a server with a certificate of that CA',
          () async {
        final server = await _start(variant);
        await _connect(variant, server,
            {'sslmode': 'verify-full', 'sslrootcert': '$_dir/ca.pem'});
        expect(server.loginReceived, isTrue);
      });

      test('verify-ca takes sslrootcert too', () async {
        final server = await _start(variant);
        await _connect(variant, server,
            {'sslmode': 'verify-ca', 'sslrootcert': '$_dir/ca.pem'});
        expect(server.loginReceived, isTrue);
      });

      test('without sslrootcert the system roots reject the private CA',
          () async {
        final server = await _start(variant);
        final error =
            await _connect(variant, server, {'sslmode': 'verify-full'});
        expect(error, isNotNull);
        expect(server.loginReceived, isFalse);
      });

      test('another CA rejects the certificate', () async {
        final server = await _start(variant);
        final error = await _connect(variant, server,
            {'sslmode': 'verify-full', 'sslrootcert': '$_dir/other-ca.pem'});
        expect(error, isNotNull);
        expect(server.loginReceived, isFalse);
      });

      test('a certificate for another host is rejected', () async {
        final server =
            await _start(variant, certificate: 'server-other-host');
        final error = await _connect(variant, server,
            {'sslmode': 'verify-full', 'sslrootcert': '$_dir/ca.pem'});
        expect(error, isNotNull);
        expect(server.loginReceived, isFalse);
      });

      test('sslcert and sslkey reach a server that requires them', () async {
        final server = await _start(variant, requireClient: true);
        await _connect(variant, server, {
          'sslmode': 'verify-full',
          'sslrootcert': '$_dir/ca.pem',
          'sslcert': '$_dir/client.pem',
          'sslkey': '$_dir/client-key.pem',
        });
        expect(server.loginReceived, isTrue);
        expect(server.clientSubject, contains('eloquent-client'));
      });

      test('require presents the client certificate without verifying',
          () async {
        final server = await _start(variant, requireClient: true);
        await _connect(variant, server, {
          'sslmode': 'require',
          'sslcert': '$_dir/client.pem',
          'sslkey': '$_dir/client-key-encrypted.pem',
          'sslpassword': 'secret',
        });
        expect(server.loginReceived, isTrue);
        expect(server.clientSubject, contains('eloquent-client'));
      });

      test('security_context verifies with certificates from memory',
          () async {
        final server = await _start(variant);
        await _connect(variant, server, {
          'sslmode': 'verify-full',
          'security_context': SecurityContext()
            ..setTrustedCertificatesBytes(
                File('$_dir/ca.pem').readAsBytesSync()),
        });
        expect(server.loginReceived, isTrue);
      });
    });
  }

  group('settings that cannot be honored throw ArgumentError', () {
    PDOConfig config(Map<String, dynamic> extra) => PDOConfig.fromMap(
        {'driver': 'pgsql', 'host': 'h', 'database': 'd', ...extra});

    final cases = <String, Map<String, dynamic>>{
      'sslrootcert with require': {
        'sslmode': 'require',
        'sslrootcert': '$_dir/ca.pem'
      },
      'sslrootcert with prefer': {
        'sslmode': 'prefer',
        'sslrootcert': '$_dir/ca.pem'
      },
      'sslrootcert without sslmode': {'sslrootcert': '$_dir/ca.pem'},
      'sslcert with disable': {
        'sslmode': 'disable',
        'sslcert': '$_dir/client.pem',
        'sslkey': '$_dir/client-key.pem',
      },
      'sslcert without sslkey': {
        'sslmode': 'require',
        'sslcert': '$_dir/client.pem'
      },
      'sslkey without sslcert': {
        'sslmode': 'require',
        'sslkey': '$_dir/client-key.pem'
      },
    };
    cases.forEach((name, extra) {
      test(name, () => expect(() => config(extra), throwsArgumentError));
    });

    test('security_context with sslrootcert', () {
      expect(
          () => config({
                'sslmode': 'verify-full',
                'sslrootcert': '$_dir/ca.pem',
                'security_context': SecurityContext(),
              }),
          throwsArgumentError);
    });

    test('security_context without sslmode', () {
      expect(() => config({'security_context': SecurityContext()}),
          throwsArgumentError);
    });

    test('security_context of another type', () {
      expect(
          () => config({
                'sslmode': 'require',
                'security_context': '$_dir/ca.pem',
              }),
          throwsArgumentError);
    });

    test('a sslrootcert that does not exist', () {
      final bad = config(
          {'sslmode': 'verify-full', 'sslrootcert': '$_dir/missing.pem'});
      expect(
          bad.buildSecurityContext,
          throwsA(isA<ArgumentError>()
              .having((e) => e.name, 'name', 'sslrootcert')));
    });

    test('a sslrootcert that is not a certificate', () {
      final bad = config(
          {'sslmode': 'verify-full', 'sslrootcert': '$_dir/generate.sh'});
      expect(bad.buildSecurityContext, throwsArgumentError);
    });

    test('an encrypted key with the wrong password', () {
      final bad = config({
        'sslmode': 'require',
        'sslcert': '$_dir/client.pem',
        'sslkey': '$_dir/client-key-encrypted.pem',
        'sslpassword': 'wrong',
      });
      expect(
          bad.buildSecurityContext,
          throwsA(
              isA<ArgumentError>().having((e) => e.name, 'name', 'sslkey')));
    });

    test('the connection fails with the error, and is not retried', () async {
      final manager = Manager()
        ..addConnection({
          'driver': 'pgsql',
          'driver_implementation': 'postgres_v3',
          'host': 'localhost',
          'database': 'd',
          'sslmode': 'verify-full',
          'sslrootcert': '$_dir/missing.pem',
        }, 'tls');
      final watch = Stopwatch()..start();
      await expectLater(manager.connection('tls'), throwsArgumentError);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });

  group('config', () {
    PDOConfig config(Map<String, dynamic> extra) => PDOConfig.fromMap(
        {'driver': 'pgsql', 'host': 'h', 'database': 'd', ...extra});

    test('no certificates: no context, the system roots verify', () {
      expect(config({'sslmode': 'verify-full'}).buildSecurityContext(), isNull);
    });

    test('an empty value is absent (an environment variable not set)', () {
      final empty = config({'sslrootcert': '', 'sslcert': ' ', 'sslkey': ''});
      expect(empty.sslRootCert, isNull);
      expect(empty.sslCert, isNull);
      expect(empty.sslKey, isNull);
    });

    test('toMap() reads back with fromMap()', () {
      final original = config({
        'sslmode': 'verify-full',
        'sslrootcert': '$_dir/ca.pem',
        'sslcert': '$_dir/client.pem',
        'sslkey': '$_dir/client-key.pem',
        'sslpassword': 'secret',
      });
      expect(PDOConfig.fromMap(original.toMap()).toMap(), original.toMap());
    });

    test('toMap() keeps security_context', () {
      final context = SecurityContext();
      final original =
          config({'sslmode': 'require', 'securityContext': context});
      expect(PDOConfig.fromMap(original.toMap()).securityContext, context);
    });
  });
}
