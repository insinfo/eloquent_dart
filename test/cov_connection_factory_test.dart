// ConnectionFactory: connections opened before a failure are closed, and a
// read/write configuration is checked before anything is opened. Fake
// connectors and PDOs, no server.
import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/container/container.dart';
import 'package:test/test.dart';

class _FakePdo extends PDOInterface {
  _FakePdo(this.host)
      : config = PDOConfig(driver: 'pgsql', host: host, database: 'x') {
    pdoInstance = this;
  }

  final String host;

  @override
  PDOConfig config;

  bool closed = false;

  @override
  Future<PDOInterface> connect() async => this;

  @override
  Future close() async => closed = true;

  @override
  Future<int> execute(String statement, [int? timeoutInSeconds]) async => 0;

  @override
  Future<PDOResults> query(String query,
          [dynamic params, int? timeoutInSeconds]) async =>
      PDOResults([], 0);

  @override
  Future<T> runInTransaction<T>(Future<T> operation(PDOExecutionContext ctx),
          [int? timeoutInSeconds]) =>
      throw UnimplementedError();
}

/// Opens a [_FakePdo] for the config's host; host `down` fails.
class _FakeConnector implements ConnectorInterface {
  _FakeConnector(this.opened);

  final List<_FakePdo> opened;

  @override
  Future<PDOInterface> connect(Map<String, dynamic> config) async {
    final host = config['host'] as String;
    if (host == 'down') throw StateError('cannot connect to $host');
    final pdo = _FakePdo(host);
    opened.add(pdo);
    return pdo;
  }
}

class _Factory extends ConnectionFactory {
  _Factory() : super(Container());

  final opened = <_FakePdo>[];

  /// Makes [createConnection] fail after the PDO was opened.
  bool failCreate = false;

  @override
  ConnectorInterface createConnector(Map<String, dynamic> config) {
    super.createConnector(config); // validates the driver
    return _FakeConnector(opened);
  }

  @override
  Connection createConnection(String driver, PDOInterface pdoP, String database,
      [String prefix = '', Map<String, dynamic> config = const {}]) {
    if (failCreate) throw StateError('createConnection failed');
    return super.createConnection(driver, pdoP, database, prefix, config);
  }
}

Map<String, dynamic> _config([Map<String, dynamic> extra = const {}]) => {
      'driver': 'pgsql',
      'host': 'primary',
      'database': 'app',
      ...extra,
    };

void main() {
  test('a read/write connection uses one PDO for each side', () async {
    final factory = _Factory();
    final connection = await factory.make(_config({
      'read': {'host': 'replica'},
    }));
    expect((connection.getPdo() as _FakePdo).host, 'primary');
    expect((connection.getReadPdo() as _FakePdo).host, 'replica');
  });

  test('a failed read connection closes the write connection', () async {
    final factory = _Factory();
    await expectLater(
        factory.make(_config({
          'read': {'host': 'down'},
        })),
        throwsA(isA<StateError>()));
    expect(factory.opened.map((p) => p.host), ['primary']);
    expect(factory.opened.single.closed, isTrue,
        reason: 'the write PDO must not stay open');
  });

  test('a failure after connect closes the PDO', () async {
    final factory = _Factory()..failCreate = true;
    await expectLater(factory.make(_config()), throwsA(isA<StateError>()));
    expect(factory.opened.single.closed, isTrue);
  });

  test('read and write must use the same driver', () async {
    final factory = _Factory();
    await expectLater(
        factory.make(_config({
          'read': {'driver': 'mysql', 'host': 'replica'},
        })),
        throwsA(isA<ArgumentError>()));
    expect(factory.opened, isEmpty, reason: 'checked before opening');
  });

  test('an empty list of read hosts throws ArgumentError', () async {
    final factory = _Factory();
    await expectLater(
        factory.make(_config({
          'read': {'host': <String>[]},
        })),
        throwsA(isA<ArgumentError>()));
    expect(factory.opened, isEmpty);
  });
}
