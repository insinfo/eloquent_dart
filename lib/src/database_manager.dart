import 'package:eloquent/eloquent.dart';

import 'container/container.dart';

class DatabaseManager implements ConnectionResolverInterface {
  /// The container with the `config` binding (and, optionally, `events`).
  Container app;

  /// Creates the connections from their configuration.
  ConnectionFactory factory;

  /// The connections made so far, by name.
  Map<String, dynamic> connectionsProp = {};

  /// The custom connection resolvers, by connection or driver name; see
  /// [extend].
  Map<String, dynamic> extensions = {};

  /// Creates a manager that reads the configuration from [app] and makes
  /// the connections with [factory].
  DatabaseManager(this.app, this.factory);

  /// Returns the connection [nameP], making it on first use.
  ///
  /// [nameP] defaults to [getDefaultConnection]. A `::read` or `::write`
  /// suffix makes the connection use only its read or only its write PDO;
  /// see [setPdoForType]. The connection is kept under the name without the
  /// suffix.
  Future<Connection> connection([String? nameP]) async {
    var re = this.parseConnectionName(nameP);

    var name = re[0];
    var type = re[1];
    // If we haven't created this connection, we'll create it based on the
    // config provided in the application. Once we've created the connection
    // we will set its read / write type.

    if (!Utils.isset(this.connectionsProp[name])) {
      final connection = await this.makeConnection(name);

      this.setPdoForType(connection, type);

      this.connectionsProp[name] = this.prepare(connection);
    }

    return this.connectionsProp[name];
  }

  /// Returns a schema builder for the connection [connectionName] (default:
  /// the default connection).
  Future<SchemaBuilder> schema([String? connectionName]) async {
    // 1. Resolve the connection.
    final Connection resolvedConnection = await connection(connectionName);
    // 2. Get the schema builder of the resolved connection.
    return resolvedConnection.getSchemaBuilder();
  }

  /// Splits [name] (default: [getDefaultConnection]) into `[name, type]`,
  /// where type is `'read'`, `'write'` or null.
  List parseConnectionName(String? name) {
    name = name ?? this.getDefaultConnection();

    return Utils.endsWith(name, ['::read', '::write'])
        ? Utils.explode('::', name, 2)
        : [name, null];
  }

  /// Disconnects from the connection [name] and forgets it, so the next
  /// [connection] call makes it again.
  Future<void> purge([String? name]) async {
    await this.disconnect(name);
    this.connectionsProp.remove(name);
  }

  /// Disconnects from the connection [name] (default: the default
  /// connection), if it was made. The connection is kept.
  Future<void> disconnect([String? name]) async {
    name = name ?? this.getDefaultConnection();

    if (Utils.isset(this.connectionsProp[name])) {
      await this.connectionsProp[name].disconnect();
    }
  }

  /// Reconnects the connection [name] (default: the default connection).
  ///
  /// A connection that was made gets the PDOs of a new one (see
  /// [refreshPdoConnections]); otherwise it is made.
  Future<Connection> reconnect([String? name]) {
    name = name ?? this.getDefaultConnection();
    this.disconnect(name);

    if (!Utils.isset(this.connectionsProp[name])) {
      return this.connection(name);
    }

    return this.refreshPdoConnections(name);
  }

  /// Gives the connection [name] the PDOs of a newly made connection and
  /// returns it.
  Future<Connection> refreshPdoConnections(String name) async {
    var fresh = await this.makeConnection(name);

    return this
        .connectionsProp[name]
        .setPdo(fresh.getPdo())
        .setReadPdo(fresh.getReadPdo());
  }

  /// Makes a new connection [name] from its configuration.
  ///
  /// It uses the resolver registered with [extend] for the name, else the
  /// one for its driver, else [factory].
  Future<Connection> makeConnection(String name) {
    var config = this.getConfig(name);

    // First we will check by the connection name to see if an extension has
    // been registered specifically for that connection. If it has we will
    // call it and pass it the config allowing it to resolve the connection.
    if (Utils.isset(this.extensions[name])) {
      return this.extensions[name](config, name);
    }

    var driver = config['driver'];

    // Next we will check to see if an extension has been registered for a
    // driver and will call it if so, which allows us to have a more generic
    // resolver for the drivers themselves which applies to all connections.
    if (Utils.isset(this.extensions[driver])) {
      return this.extensions[driver](config, name);
    }

    return this.factory.make(config, name);
  }

  /// Sets the event dispatcher of [connection] (when [app] has `events`)
  /// and a reconnector that calls [reconnect], and returns [connection].
  Connection prepare(Connection connection) {
    if (this.app.bound('events')) {
      connection.setEventDispatcher(this.app['events']);
    }

    // Here we'll set a reconnector callback. This reconnector can be any
    // function so we will set one to reconnect from this manager with the
    // name of the connection, which will allow us to reconnect from the
    // connections.
    connection.setReconnector((con) async {
      await this.reconnect(con.getName());
    });

    return connection;
  }

  /// Makes [connection] use only its read PDO (`type == 'read'`) or only
  /// its write PDO (`'write'`), and returns it. Other values change
  /// nothing.
  ConnectionInterface setPdoForType(Connection connection, [String? type]) {
    if (type == 'read') {
      connection.setPdo(connection.getReadPdo());
    } else if (type == 'write') {
      connection.setReadPdo(connection.getPdo());
    }

    return connection;
  }

  /// Returns the configuration of the connection [name] (default: the
  /// default connection) from `database.connections`.
  ///
  /// Throws an [ArgumentError] when it is not configured.
  Map<String, dynamic> getConfig(String? name) {
    name = name ?? this.getDefaultConnection();

    // To get the database connection configuration, we will just pull each of
    // the connection configurations and get the configurations for the given
    // name.
    // If the configuration doesn't exist, we'll throw an exception and bail.
    var connections = this.app['config']['database.connections'];

    var config = Utils.array_get(connections, name);

    if (Utils.is_null(config)) {
      throw ArgumentError.value(name, 'name', 'Database not configured.');
    }

    return config;
  }

  /// Returns the name of the default connection (`database.default`).
  String getDefaultConnection() {
    return this.app['config']['database.default'];
  }

  /// Sets the name of the default connection.
  void setDefaultConnection(String name) {
    this.app['config']['database.default'] = name;
  }

  /// Returns the driver names Laravel supports. Only `mysql` and `pgsql`
  /// have connectors in this package.
  List supportedDrivers() {
    return ['mysql', 'pgsql', 'sqlite', 'sqlsrv'];
  }

  /// Returns the same list as [supportedDrivers].
  List availableDrivers() {
    return supportedDrivers();
  }

  /// Registers [resolver] for the connection or driver [name].
  ///
  /// [resolver] is called with the configuration and the connection name
  /// and must return a `Future<Connection>`.
  dynamic extend(String name, Function resolver) {
    this.extensions[name] = resolver;
  }

  /// Returns the connections made so far, by name.
  dynamic getConnections() {
    return this.connectionsProp;
  }

  /// Does nothing and returns null.
  dynamic call(String method, List parameters) {
    // Laravel forwards the call to the default connection (PHP's __call).
  }
}
