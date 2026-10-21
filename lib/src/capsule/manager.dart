import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/container/container.dart';

/// Entry point for using the database outside a framework (Laravel's
/// "capsule"): registers connections and hands out [Connection]s, query
/// builders and schema builders.
///
/// ```dart
/// final manager = Manager()
///   ..addConnection({
///     'driver': 'pgsql',
///     'host': 'localhost',
///     'port': '5432',
///     'database': 'banco',
///     'username': 'dart',
///     'password': 'dart',
///   });
/// final db = await manager.connection();
/// ```
class Manager {
  /// The manager made global by [setAsGlobal], if any.
  static Manager? instance;

  /// The IoC container that holds the `config` and `events` bindings.
  late Container container;

  /// The database manager that creates and caches the connections.
  late DatabaseManager manager;

  /// Creates a manager on [container] (a new [Container] by default), with
  /// `default` as the default connection name.
  Manager([Container? container]) {
    this.setupContainer(container ?? Container());

    // The database manager reads its settings from the container's "config"
    // binding, so the defaults must be in place before it is created.
    this.setupDefaultConfiguration();
    this.setupManager();
  }

  /// Uses [containerP] and binds an empty [Fluent] as its `config` when it
  /// has none.
  void setupContainer(Container containerP) {
    this.container = containerP;

    if (!this.container.bound('config')) {
      this.container.instance('config', Fluent());
    }
  }

  /// Makes this manager available as [Manager.instance].
  void setAsGlobal() {
    instance = this;
  }

  /// The IoC container.
  Container? getContainer() {
    return this.container;
  }

  /// Replaces the IoC container. The database manager keeps the container
  /// it was created with.
  void setContainer(Container containerP) {
    this.container = containerP;
  }

  /// Sets `default` as the default connection name.
  void setupDefaultConfiguration() {
    this.container['config']['database.default'] = 'default';
  }

  /// Creates the [DatabaseManager] and its [ConnectionFactory].
  void setupManager() {
    var factory = ConnectionFactory(this.container);
    this.manager = DatabaseManager(this.container, factory);
  }

  /// The connection named [connection] (the default one when null).
  Future<Connection> connection([String? connection]) async {
    return await this.getConnection(connection);
  }

  /// A query builder for [table] on the connection named [connectionP].
  Future<QueryBuilder> table(String table, [String? connectionP]) async {
    final com = await this.connection(connectionP);
    return com.table(table);
  }

  /// The schema builder of the connection named [connectionP].
  Future<SchemaBuilder> schema([String? connectionP]) async {
    final com = await this.connection(connectionP);
    return com.getSchemaBuilder();
  }

  /// The connection named [name] (the default one when null), connecting on
  /// first use.
  Future<Connection> getConnection([String? name]) async {
    return await this.manager.connection(name);
  }

  /// Registers a connection [config] under [name].
  ///
  /// ```dart
  /// manager.addConnection({'driver': 'mysql', 'database': 'banco'}, 'mysql');
  /// final db = await manager.connection('mysql');
  /// ```
  void addConnection(Map<String, dynamic> config, [String name = 'default']) {
    var connections = this.container['config']['database.connections'];
    if (connections == null) {
      connections = {name: config};
    } else {
      connections[name] = config;
    }
    this.container['config']['database.connections'] = connections;
  }

  /// The database manager.
  DatabaseManager getDatabaseManager() {
    return this.manager;
  }

  /// The event dispatcher given to the connections, or null.
  dynamic getEventDispatcher() {
    if (this.container.bound('events')) {
      return this.container['events'];
    }
    return null;
  }

  /// Sets the event dispatcher given to the connections created from now on.
  void setEventDispatcher(dynamic dispatcher) {
    this.container.instance('events', dispatcher);
  }
}
