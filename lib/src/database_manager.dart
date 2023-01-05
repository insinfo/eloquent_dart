import 'package:eloquent/eloquent.dart';

import 'container/container.dart';

class DatabaseManager implements ConnectionResolverInterface {
  ///
  /// The application instance.
  ///
  /// @var \Illuminate\Foundation\Application
  ///
  Container app;

  ///
  /// The database connection factory instance.
  ///
  /// @var \Illuminate\Database\Connectors\ConnectionFactory
  ///
  ConnectionFactory factory;

  ///
  /// The active connection instances.
  ///
  /// @var array
  ///
  Map<String, dynamic> connectionsProp = {};

  ///
  /// The custom connection resolvers.
  ///
  /// @var array
  ///
  Map<String, dynamic> extensions = {};

  ///
  /// Create a new database manager instance.
  ///
  /// @param  \Illuminate\Foundation\Application  $app
  /// @param  \Illuminate\Database\Connectors\ConnectionFactory  $factory
  /// @return void
  ///
  DatabaseManager(this.app, this.factory);

  ///
  /// Get a database connection instance.
  ///
  /// @param  string  $name
  /// @return \Illuminate\Database\Connection
  ///
  Future<Connection> connection([String? nameP]) async {
    var re = this.parseConnectionName(nameP);

    var name = re[0];
    var type = re[1];
    // If we haven't created this connection, we'll create it based on the config
    // provided in the application. Once we've created the connections we will
    // set the "fetch mode" for PDO which determines the query return types.

    if (!Utils.isset(this.connectionsProp[name])) {
      var connection = await this.makeConnection(name);

      this.setPdoForType(connection, type);

      this.connectionsProp[name] = this.prepare(connection);
    }

    return this.connectionsProp[name];
  }

  ///
  /// Parse the connection into an array of the name and read / write type.
  ///
  /// @param  string  $name
  /// @return array
  ///
  List parseConnectionName(String? name) {
    name = name ?? this.getDefaultConnection();

    return Utils.endsWith(name, ['::read', '::write'])
        ? Utils.explode('::', name, 2)
        : [name, null];
  }

  ///
  /// Disconnect from the given database and remove from local cache.
  ///
  /// @param  string  $name
  /// @return void
  ///
  void purge([String? name]) {
    this.disconnect(name);
    this.connectionsProp.remove(name);
    //unset(this.connectionsProp[name]);
  }

  ///
  /// Disconnect from the given database.
  ///
  /// @param  string  $name
  /// @return void
  ///
  Future<void> disconnect([String? name]) async {
    name = name ?? this.getDefaultConnection();

    if (Utils.isset(this.connectionsProp[name])) {
      await this.connectionsProp[name].disconnect();
    }
  }

  ///
  /// Reconnect to the given database.
  ///
  /// @param  string  $name
  /// @return \Illuminate\Database\Connection
  ///
  Future<Connection> reconnect([String? name]) {
    name = name ?? this.getDefaultConnection();
    this.disconnect(name);

    if (!Utils.isset(this.connectionsProp[name])) {
      return this.connection(name);
    }

    return this.refreshPdoConnections(name);
  }

  ///
  /// Refresh the PDO connections on a given connection.
  ///
  /// @param  string  $name
  /// @return \Illuminate\Database\Connection
  ///
  Future<Connection> refreshPdoConnections(String name) async {
    var fresh = await this.makeConnection(name);

    return this
        .connectionsProp[name]
        .setPdo(fresh.getPdo())
        .setReadPdo(fresh.getReadPdo());
  }

  ///
  /// Make the database connection instance.
  ///
  /// @param  string  $name
  /// @return \Illuminate\Database\Connection
  ///
  Future<Connection> makeConnection(String name) {
    var config = this.getConfig(name);

    // First we will check by the connection name to see if an extension has been
    // registered specifically for that connection. If it has we will call the
    // Closure and pass it the config allowing it to resolve the connection.
    if (Utils.isset(this.extensions[name])) {
      return this.extensions[name](config, name);
    }

    var driver = config['driver'];

    // Next we will check to see if an extension has been registered for a driver
    // and will call the Closure if so, which allows us to have a more generic
    // resolver for the drivers themselves which applies to all connections.
    if (Utils.isset(this.extensions[driver])) {
      //return call_user_func($this->extensions[$driver], $config, $name);
      return this.extensions[name](config, name);
    }

    return this.factory.make(config, name);
  }

  ///
  /// Prepare the database connection instance.
  ///
  /// @param  \Illuminate\Database\Connection  $connection
  /// @return \Illuminate\Database\Connection
  ///
  Connection prepare(Connection connection) {
    connection.setFetchMode(this.app['config']['database.fetch']);

    if (this.app.bound('events')) {
      connection.setEventDispatcher(this.app['events']);
    }

    // Here we'll set a reconnector callback. This reconnector can be any callable
    // so we will set a Closure to reconnect from this manager with the name of
    // the connection, which will allow us to reconnect from the connections.
    connection.setReconnector((con) async {
      await this.reconnect(con.getName());
    });

    return connection;
  }

  ///
  /// Prepare the read write mode for database connection instance.
  ///
  /// @param  \Illuminate\Database\Connection  $connection
  /// @param  string  $type
  /// @return \Illuminate\Database\Connection
  ///
  ConnectionInterface setPdoForType(Connection connection, [String? type]) {
    if (type == 'read') {
      connection.setPdo(connection.getReadPdo());
    } else if (type == 'write') {
      connection.setReadPdo(connection.getPdo());
    }

    return connection;
  }

  ///
  /// Get the configuration for a connection.
  ///
  /// @param  string  $name
  /// @return array
  ///
  /// @throws \InvalidArgumentException
  ///
  Map<String, dynamic> getConfig(String? name) {
    name = name ?? this.getDefaultConnection();

    // To get the database connection configuration, we will just pull each of the
    // connection configurations and get the configurations for the given name.
    // If the configuration doesn't exist, we'll throw an exception and bail.
    var connections = this.app['config']['database.connections'];

    var config = Utils.array_get(connections, name);

    if (Utils.is_null(config)) {
      throw InvalidArgumentException("Database [$name] not configured.");
    }

    return config;
  }

  ///
  /// Get the default connection name.
  ///
  /// @return string
  ///
  String getDefaultConnection() {
    return this.app['config']['database.default'];
  }

  ///
  /// Set the default connection name.
  ///
  /// @param  string  $name
  /// @return void
  ///
  void setDefaultConnection(String name) {
    this.app['config']['database.default'] = name;
  }

  ///
  /// Get all of the support drivers.
  ///
  /// @return array
  ///
  List supportedDrivers() {
    return ['mysql', 'pgsql', 'sqlite', 'sqlsrv'];
  }

  ///
  /// Get all of the drivers that are actually available.
  ///
  /// @return array
  ///
  List availableDrivers() {
    //return array_intersect($this->supportedDrivers(), str_replace('dblib', 'sqlsrv', PDO::getAvailableDrivers()));
    return supportedDrivers();
  }

  ///
  /// Register an extension connection resolver.
  ///
  /// @param  string    $name
  /// @param  callable  $resolver
  /// @return void
  ///
  dynamic extend(String name, Function resolver) {
    this.extensions[name] = resolver;
  }

  ///
  /// Return all of the created connections.
  ///
  /// @return array
  ///
  dynamic getConnections() {
    return this.connectionsProp;
  }

  ///
  /// Dynamically pass methods to the default connection.
  ///
  /// @param  string  $method
  /// @param  array   $parameters
  /// @return mixed
  ///
  dynamic call(String method, List parameters) {
    //return call_user_func_array([$this->connection(), $method], $parameters);
  }
}
