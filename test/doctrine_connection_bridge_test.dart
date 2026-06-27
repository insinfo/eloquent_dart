import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/doctrine/connection.dart' as doctrine;
import 'package:eloquent/src/doctrine/schema/mysql_schema_manager.dart';
import 'package:eloquent/src/doctrine/schema/postgres_schema_manager.dart';
import 'package:eloquent/src/mysql_connection.dart';
import 'package:test/test.dart';

class FakePdo extends PDOInterface {
  @override
  PDOConfig config;

  FakePdo(this.config) {
    pdoInstance = this;
  }

  @override
  Future<PDOInterface> connect() async => this;

  @override
  Future close() async {}

  @override
  Future<int> execute(String statement, [int? timeoutInSeconds]) async => 0;

  @override
  PDOConfig getConfig() => config;

  @override
  Future<PDOResults> query(String query,
          [dynamic params, int? timeoutInSeconds]) async =>
      PDOResults([], 0);

  @override
  Future<T> runInTransaction<T>(Future<T> operation(PDOExecutionContext ctx),
          [int? timeoutInSeconds]) =>
      operation(this);
}

void main() {
  group('Doctrine connection bridge', () {
    test('creates a Postgres schema manager from connection driver config', () {
      final connection = PostgresConnection(
        FakePdo(PDOConfig(driver: 'pgsql', host: 'localhost', database: 'app')),
        'app',
        '',
        {'driver': 'pgsql', 'server_version': '16.0'},
      );

      final doctrineConnection = connection.getDoctrineConnection();
      final schemaManager = connection.getDoctrineSchemaManager();

      expect(doctrineConnection, isA<doctrine.DoctrineConnection>());
      expect(doctrineConnection.driver, 'pgsql');
      expect(doctrineConnection.database, 'app');
      expect(doctrineConnection.getServerVersion(), '16.0');
      expect(schemaManager, isA<PostgreSQLSchemaManager>());
      expect(identical(schemaManager, connection.getDoctrineSchemaManager()),
          isTrue);
    });

    test('creates a MySQL schema manager from connection driver config', () {
      final connection = MySqlConnection(
        FakePdo(PDOConfig(driver: 'mysql', host: 'localhost', database: 'app')),
        'app',
        '',
        {'driver': 'mysql'},
      );

      expect(connection.getDriverName(), 'mysql');
      expect(connection.getDoctrineSchemaManager(), isA<MySqlSchemaManager>());
    });

    test('throws for unsupported Doctrine schema manager drivers', () {
      final connection = Connection(
        FakePdo(
            PDOConfig(driver: 'sqlite', host: 'localhost', database: 'app')),
        'app',
        '',
        {'driver': 'sqlite'},
      );

      expect(connection.getDriverName(), 'sqlite');
      expect(connection.getDoctrineSchemaManager,
          throwsA(isA<UnsupportedError>()));
    });
  });
}
