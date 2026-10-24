import 'dart:math';

import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/container/container.dart';
import 'package:eloquent/src/mysql_connection.dart';

import 'mysql_connector.dart';

class ConnectionFactory {
  /// The IoC container.
  Container container;

  /// Creates a connection factory that uses [container].
  ConnectionFactory(this.container);

  /// Opens a connection with the configuration [configP], named [name].
  ///
  /// The `driver` key picks the connector (`mysql` or `pgsql`) and `prefix`
  /// defaults to `''` (see [parseConfig]). With a `read` key the result is a
  /// read/write connection (see [createReadWriteConnection]).
  Future<Connection> make(Map<String, dynamic> configP,
      [String name = 'default']) {
    var config = parseConfig(configP, name);

    if (config['read'] != null) {
      return createReadWriteConnection(config);
    }

    return createSingleConnection(config);
  }

  /// Opens a connection with the settings in [config]. The driver
  /// connection is closed when the [Connection] cannot be created.
  Future<Connection> createSingleConnection(Map<String, dynamic> config) async {
    var conC = createConnector(config);

    var pdo = await conC.connect(config);

    try {
      return createConnection(
          config['driver'], pdo, config['database'], config['prefix'], config);
    } catch (_) {
      try {
        await pdo.close();
      } catch (_) {
        // The original error is the one to report.
      }
      rethrow;
    }
  }

  /// Opens a read/write connection.
  ///
  /// The connection is opened with the `write` settings of [config] and gets
  /// a second driver connection, opened with the `read` settings, for reads.
  /// Both settings are checked before anything is opened: they must use the
  /// same driver (the reads run SQL compiled by the write side's grammar).
  /// When the read connection cannot be opened, the write one is closed.
  Future<Connection> createReadWriteConnection(
      Map<String, dynamic> config) async {
    final writeConfig = getWriteConfig(config);
    final readConfig = getReadConfig(config);
    if (writeConfig['driver'] != readConfig['driver']) {
      throw ArgumentError(
          'The read and write connections must use the same driver '
          '(write: ${writeConfig['driver']}, read: ${readConfig['driver']}).');
    }
    final connection = await createSingleConnection(writeConfig);
    try {
      connection
          .setReadPdo(await createConnector(readConfig).connect(readConfig));
      return connection;
    } catch (_) {
      await connection.disconnect();
      rethrow;
    }
  }

  /// Opens the driver connection used for reads, with the `read` settings of
  /// [config] (see [getReadConfig]).
  Future<PDOInterface> createReadPdo(Map<String, dynamic> config) async {
    var readConfig = getReadConfig(config);

    return createConnector(readConfig).connect(readConfig);
  }

  /// Returns a copy of [config] with its `read` settings merged in (see
  /// [mergeReadWriteConfig]).
  ///
  /// When `read['host']` is a list, one of its hosts is picked at random; an
  /// empty list throws [ArgumentError].
  Map<String, dynamic> getReadConfig(Map<String, dynamic> config) {
    // A copy (see getReadWriteConfig): picking the host must not change the
    // caller's `read` map.
    var readConfig = getReadWriteConfig(config, 'read');

    final hosts = readConfig['host'];
    if (hosts is List && hosts.isEmpty) {
      throw ArgumentError.value(hosts, "read['host']", 'No host to read from.');
    }
    if (hosts is List) {
      readConfig['host'] =
          hosts.length > 1 ? hosts[_random.nextInt(hosts.length)] : hosts[0];
    }

    return mergeReadWriteConfig(config, readConfig);
  }

  static final _random = Random();

  /// Returns a copy of [config] with its `write` settings merged in (see
  /// [mergeReadWriteConfig]).
  Map<String, dynamic> getWriteConfig(Map<String, dynamic> config) {
    var writeConfig = getReadWriteConfig(config, 'write');
    return mergeReadWriteConfig(config, writeConfig);
  }

  /// Returns the `read` or `write` settings of [config], as given by [type];
  /// an empty map when [config] has none, so the base settings apply (a
  /// config with `read` and no `write` writes with the base settings).
  Map<String, dynamic> getReadWriteConfig(
      Map<String, dynamic> config, String type) {
    final settings = config[type];
    if (settings == null) return <String, dynamic>{};
    return Map<String, dynamic>.from(settings as Map);
  }

  /// Returns a copy of [config] overridden by [merge], without the `read` and
  /// `write` keys.
  Map<String, dynamic> mergeReadWriteConfig(
      Map<String, dynamic> config, Map<String, dynamic> merge) {
    return {...config, ...merge}
      ..remove('read')
      ..remove('write');
  }

  /// Returns a copy of [config] with the defaults added.
  ///
  /// Sets `prefix` to `''` and `name` to [name] when they are missing or
  /// null. The caller's map is not changed: adding `name` to it gave a
  /// config map registered under two names the first name on both
  /// connections.
  Map<String, dynamic> parseConfig(Map<String, dynamic> config, String name) {
    return {
      ...config,
      'prefix': config['prefix'] ?? '',
      'name': config['name'] ?? name,
    };
  }

  /// Returns the connector for the `driver` of [config]: [MySqlConnector] for
  /// `mysql`, [PostgresConnector] for `pgsql`.
  ///
  /// Throws [ArgumentError] when the driver is missing or not supported.
  ConnectorInterface createConnector(Map<String, dynamic> config) {
    if (config['driver'] == null) {
      throw ArgumentError.notNull('driver');
    }

    switch (config['driver']) {
      case 'mysql':
        return MySqlConnector();

      case 'pgsql':
        return PostgresConnector();
    }

    throw ArgumentError.value(
        config['driver'], 'driver', 'Unsupported driver.');
  }

  /// Creates the [Connection] for [driver] over the driver connection [pdoP].
  ///
  /// [database] is the database name and [prefix] the table prefix. Throws
  /// [ArgumentError] when [driver] is not `mysql` or `pgsql`.
  Connection createConnection(String driver, PDOInterface pdoP, String database,
      [String prefix = '', Map<String, dynamic> config = const {}]) {
    switch (driver) {
      case 'mysql':
        return MySqlConnection(pdoP, database, prefix, config);

      case 'pgsql':
        return PostgresConnection(pdoP, database, prefix, config);
    }

    throw ArgumentError.value(driver, 'driver', 'Unsupported driver.');
  }
}
