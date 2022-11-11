import 'package:eloquent/eloquent.dart';

class ConnectionFactory {
  ConnectionFactory();

  ///
  /// Establish a PDO connection based on the configuration.
  ///
  /// @param  array   $config
  /// @param  string  $name
  /// @return \Illuminate\Database\Connection
  ///
  Future<Connection> make(Map<String, dynamic> configP,
      [String name = 'default']) async {
    var config = parseConfig(configP, name);

    if (config['read'] != null) {
      return createReadWriteConnection(config);
    }

    return createSingleConnection(config);
  }

  ///
  /// Create a single database connection instance.
  ///
  /// @param  array  $config
  /// @return \Illuminate\Database\Connection
  ///
  Future<Connection> createSingleConnection(Map<String, dynamic> config) async {
    var pdo = await createConnector(config).connect(config);

    return createConnection(
        config['driver'], pdo, config['database'], config['prefix'], config);
  }

  ///
  /// Create a single database connection instance.
  ///
  /// @param  array  $config
  /// @return \Illuminate\Database\Connection
  ///
  Future<Connection> createReadWriteConnection(
      Map<String, dynamic> config) async {
    var connection = await createSingleConnection(getWriteConfig(config));
    var pdo = createReadPdo(config);
    connection.setReadPdo(pdo);
    return connection;
  }

  ///
  /// Create a new PDO instance for reading.
  ///
  /// @param  array  $config
  /// @return \PDO
  ///
  Future<dynamic> createReadPdo(Map<String, dynamic> config) async {
    var readConfig = getReadConfig(config);

    return createConnector(readConfig).connect(readConfig);
  }

  ///
  /// Get the read configuration for a read / write connection.
  ///
  /// @param  array  $config
  /// @return array
  ///
  Map<String, dynamic> getReadConfig(Map<String, dynamic> config) {
    var readConfig = getReadWriteConfig(config, 'read');

    if (readConfig['host'] != null && Utils.is_array(readConfig['host'])) {
      readConfig['host'] = Utils.count(readConfig['host']) > 1
          ? readConfig['host'][Utils.array_rand(readConfig['host'])]
          : readConfig['host'][0];
    }

    return mergeReadWriteConfig(config, readConfig);
  }

  ///
  /// Get the read configuration for a read / write connection.
  ///
  /// @param  array  $config
  /// @return array
  ///
  Map<String, dynamic> getWriteConfig(Map<String, dynamic> config) {
    var writeConfig = getReadWriteConfig(config, 'write');
    return mergeReadWriteConfig(config, writeConfig);
  }

  ///
  /// Get a read / write level configuration.
  ///
  /// @param  array   $config
  /// @param  string  $type
  /// @return array
  ///
  Map<String, dynamic> getReadWriteConfig(
      Map<String, dynamic> config, String type) {
    // if (config[type][0] != null) {
    //     return config[type][array_rand($config[$type])];
    // }

    return config[type];
  }

  ///
  /// Merge a configuration for a read / write connection.
  ///
  /// @param  array  $config
  /// @param  array  $merge
  /// @return array
  ///
  Map<String, dynamic> mergeReadWriteConfig(
      Map<String, dynamic> config, Map<String, dynamic> merge) {
    return Utils.map_except_sd(
        Utils.map_merge_sd(config, merge), ['read', 'write']);
  }

  ///
  /// Parse and prepare the database configuration.
  ///
  /// @param  Map<String,dynamic>   config
  /// @param  String  name
  /// @return Map<String,dynamic>
  ///
  Map<String, dynamic> parseConfig(Map<String, dynamic> config, String name) {
    return Utils.map_add_sd(
        Utils.map_add_sd(config, 'prefix', ''), 'name', name);
  }

  /**
     * Create a connector instance based on the configuration.
     *
     * @param  array  $config
     * @return \Illuminate\Database\Connectors\ConnectorInterface
     *
     * @throws \InvalidArgumentException
     */
  ConnectorInterface createConnector(Map<String, dynamic> config) {
    if (config['driver'] == null) {
      throw InvalidArgumentException('A driver must be specified.');
    }

    // if ($this->container->bound($key = "db.connector.{$config['driver']}")) {
    //     return $this->container->make($key);
    // }

    switch (config['driver']) {
      // case 'mysql':
      //     return new MySqlConnector;

      case 'pgsql':
        return PostgresConnector();

      // case 'sqlite':
      //     return new SQLiteConnector;

      // case 'sqlsrv':
      //     return new SqlServerConnector;
    }

    throw InvalidArgumentException("Unsupported driver [${config['driver']}]");
  }

  /**
     * Create a new connection instance.
     *
     * @param  string   $driver
     * @param  \PDO     $connection
     * @param  string   $database
     * @param  string   $prefix
     * @param  array    $config
     * @return \Illuminate\Database\Connection
     *
     * @throws \InvalidArgumentException
     */
  Connection createConnection(String driver, PDO connection, String database,
      [String prefix = '', Map<String, dynamic> config = const {}]) {
    // if ($this->container->bound($key = "db.connection.{$driver}")) {
    //     return $this->container->make($key, [$connection, $database, $prefix, $config]);
    // }

    switch (driver) {
      // case 'mysql':
      //     return new MySqlConnection($connection, $database, $prefix, $config);

      case 'pgsql':
        return PostgresConnection(connection, database, prefix, config);

      // case 'sqlite':
      //     return new SQLiteConnection($connection, $database, $prefix, $config);

      // case 'sqlsrv':
      //     return new SqlServerConnection($connection, $database, $prefix, $config);
    }

    throw InvalidArgumentException("Unsupported driver [$driver]");
  }
}
