import 'package:eloquent/eloquent.dart';

import 'container/container.dart';

class DatabaseManager implements ConnectionResolverInterface {
  /// The container with the `config` binding (and, optionally, `events`).
  Container app;

  /// Creates the connections from their configuration.
  ConnectionFactory factory;

  /// The connections made so far, by name (with the `::read` or `::write`
  /// suffix they were asked for).
  Map<String, dynamic> connectionsProp = {};

  /// The connections being made, by name: concurrent first calls share one.
  final Map<String, Future<Connection>> _making = {};

  /// Reconnections in progress, by name: concurrent [reconnect] calls of a
  /// connection share one.
  final Map<String, Future<Connection>> _reconnecting = {};

  /// The custom connection resolvers, by connection or driver name; see
  /// [extend].
  Map<String, dynamic> extensions = {};

  /// Creates a manager that reads the configuration from [app] and makes
  /// the connections with [factory].
  DatabaseManager(this.app, this.factory);

  /// Returns the connection [nameP], making it on first use.
  ///
  /// [nameP] defaults to [getDefaultConnection]. A `::read` or `::write`
  /// suffix gives a connection, made from the configuration without the
  /// suffix, that uses only its read or only its write PDO (see
  /// [setPdoForType]); it is kept apart from the connection without the
  /// suffix, under the full name.
  Future<Connection> connection([String? nameP]) async {
    final name = nameP ?? this.getDefaultConnection();
    final made = this.connectionsProp[name];
    if (made != null) return made;

    // If we haven't created this connection, we'll create it based on the
    // config provided in the application. Once we've created the connection
    // we will set its read / write type.
    return _making[name] ??= _makeAndKeep(name).whenComplete(() {
      // A block: remove() returns this future, which whenComplete would
      // wait for.
      _making.remove(name);
    });
  }

  Future<Connection> _makeAndKeep(String name) async {
    final re = this.parseConnectionName(name);
    final connection = await this.makeConnection(re[0]);

    this.setPdoForType(connection, re[1]);

    this.connectionsProp[name] = this.prepare(connection, name);
    return connection;
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
    name = name ?? this.getDefaultConnection();
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
  /// A connection that was made is disconnected and gets the PDOs of a new
  /// one (see [refreshPdoConnections]); otherwise it is made. Concurrent
  /// calls for the same connection (several statements that lost it at
  /// once) share one reconnection: each making its own would replace the
  /// PDOs of the others and leave them open.
  ///
  /// With `'pool': true` the whole pool is closed and replaced, so the
  /// statements other requests are running on it fail too. That is why a
  /// lost connection only calls this with `pool_reconnect: 'replace'`: by
  /// default (`'keep'`) the pool discards the dead connection by itself (see
  /// [Connection.parsePoolReconnect]).
  Future<Connection> reconnect([String? name]) {
    final key = name ?? this.getDefaultConnection();
    // A block body: whenComplete waits for a returned future, and remove()
    // returns this very one.
    return _reconnecting[key] ??= _reconnect(key).whenComplete(() {
      _reconnecting.remove(key);
    });
  }

  Future<Connection> _reconnect(String name) async {
    await this.disconnect(name);

    if (!Utils.isset(this.connectionsProp[name])) {
      return this.connection(name);
    }

    return this.refreshPdoConnections(name);
  }

  /// Gives the connection [name] the PDOs of a newly made connection (with
  /// the read or write type of its `::read`/`::write` suffix) and returns
  /// it.
  Future<Connection> refreshPdoConnections(String name) async {
    final re = this.parseConnectionName(name);
    final fresh = await this.makeConnection(re[0]);
    this.setPdoForType(fresh, re[1]);

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
  /// and a reconnector that calls [reconnect] with [name] (default: the
  /// connection's `name` option), and returns [connection].
  Connection prepare(Connection connection, [String? name]) {
    if (this.app.bound('events')) {
      connection.setEventDispatcher(this.app['events']);
    }

    // Here we'll set a reconnector callback. This reconnector can be any
    // function so we will set one to reconnect from this manager with the
    // name of the connection, which will allow us to reconnect from the
    // connections.
    connection.setReconnector((con) async {
      await this.reconnect(name ?? con.getName());
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
