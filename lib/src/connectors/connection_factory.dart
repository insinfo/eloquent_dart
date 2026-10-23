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

  /// Opens a connection with the settings in [config].
  Future<Connection> createSingleConnection(Map<String, dynamic> config) async {
    var conC = createConnector(config);

    var pdo = await conC.connect(config);

    return createConnection(
        config['driver'], pdo, config['database'], config['prefix'], config);
  }

  /// Opens a read/write connection.
  ///
  /// The connection is opened with the `write` settings of [config] and gets
  /// a second driver connection, opened with the `read` settings, for reads.
  Future<Connection> createReadWriteConnection(
      Map<String, dynamic> config) async {
    var connection = await createSingleConnection(getWriteConfig(config));
    var pdo = await createReadPdo(config);
    connection.setReadPdo(pdo);
    return connection;
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
  /// When `read['host']` is a list, one of its hosts is picked at random.
  Map<String, dynamic> getReadConfig(Map<String, dynamic> config) {
    var readConfig = getReadWriteConfig(config, 'read');

    if (readConfig['host'] != null && Utils.is_array(readConfig['host'])) {
      readConfig['host'] = Utils.count(readConfig['host']) > 1
          ? readConfig['host'][Utils.array_rand(readConfig['host'])]
          : readConfig['host'][0];
    }

    return mergeReadWriteConfig(config, readConfig);
  }

  /// Returns a copy of [config] with its `write` settings merged in (see
  /// [mergeReadWriteConfig]).
  Map<String, dynamic> getWriteConfig(Map<String, dynamic> config) {
    var writeConfig = getReadWriteConfig(config, 'write');
    return mergeReadWriteConfig(config, writeConfig);
  }

  /// Returns the `read` or `write` settings of [config], as given by [type].
  Map<String, dynamic> getReadWriteConfig(
      Map<String, dynamic> config, String type) {
    return config[type];
  }

  /// Returns a copy of [config] overridden by [merge], without the `read` and
  /// `write` keys.
  Map<String, dynamic> mergeReadWriteConfig(
      Map<String, dynamic> config, Map<String, dynamic> merge) {
    return Utils.map_except_sd(
        Utils.map_merge_sd(config, merge), ['read', 'write']);
  }

  /// Adds the defaults to [config] and returns it.
  ///
  /// Sets `prefix` to `''` and `name` to [name] when they are missing. The map
  /// is modified in place.
  Map<String, dynamic> parseConfig(Map<String, dynamic> config, String name) {
    var arr = Utils.map_add_sd(config, 'prefix', '');
    var result = Utils.map_add_sd(arr, 'name', name);
    return result;
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
