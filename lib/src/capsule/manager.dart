//
import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/container/container.dart';
import 'package:eloquent/src/schema/schema_builder.dart';

import '../support/traits/capsule_manager_trait.dart';

//with CapsuleManagerTrait
class Manager {
  ///
  /// The current globally used instance.
  ///
  /// @var object
  ///
  static Manager? instance;

  ///
  /// The container instance.
  ///
  /// @var \Illuminate\Contracts\Container\Container
  ///
  late Container container;

  ///
  /// Setup the IoC container instance.
  ///
  /// @param  \Illuminate\Contracts\Container\Container  $container
  /// @return void
  ///
  void setupContainer(Container containerP) {
    this.container = containerP;

    if (!this.container.bound('config')) {
      this.container.instance('config', Fluent());
    }
  }

  ///
  /// Make this capsule instance available globally.
  ///
  /// @return void
  ///
  void setAsGlobal() {
    instance = this;
  }

  ///
  /// Get the IoC container instance.
  ///
  /// @return \Illuminate\Contracts\Container\Container
  ///
  Container? getContainer() {
    return this.container;
  }

  ///
  /// Set the IoC container instance.
  ///
  /// @param  \Illuminate\Contracts\Container\Container  $container
  /// @return void
  ///
  void setContainer(Container containerP) {
    this.container = containerP;
  }

  ///
  ///  The database manager instance.
  ///
  ///  @var \Illuminate\Database\DatabaseManager
  ///
  late DatabaseManager manager;

  ///
  ///  Create a new database capsule manager.
  ///
  ///  @param  \Illuminate\Container\Container|null  $container
  ///  @return void
  ///
  Manager([Container? container]) {
    this.setupContainer(container ?? Container());

    // Once we have the container setup, we will setup the default configuration
    // options in the container "config" binding. This will make the database
    // manager behave correctly since all the correct binding are in place.
    this.setupDefaultConfiguration();

    this.setupManager();
  }

  ///
  ///  Setup the default database configuration options.
  ///
  ///  @return void
  ///
  void setupDefaultConfiguration() {
    this.container['config']['database.fetch'] = 5; //'PDO::FETCH_OBJ';
    this.container['config']['database.default'] = 'default';
  }

  ///
  ///  Build the database manager instance.
  ///
  ///  @return void
  ///
  void setupManager() {
    var factory = ConnectionFactory(this.container);

    this.manager = DatabaseManager(this.container, factory);
  }

  ///
  ///  Get a connection instance from the global manager.
  ///
  ///  @param  string  $connection
  ///  @return \Illuminate\Database\Connection
  ///
  Connection connection([String? connection]) {
    return instance!.getConnection(connection);
  }

  ///
  ///  Get a fluent query builder instance.
  ///
  ///  @param  string  $table
  ///  @param  string  $connection
  ///  @return \Illuminate\Database\Query\Builder
  ///
  QueryBuilder table(String table, [String? connectionP]) {
    var com = instance!.connection(connectionP);
    return com.table(table);
  }

  ///
  ///  Get a schema builder instance.
  ///
  ///  @param  string  $connection
  ///  @return \Illuminate\Database\Schema\Builder
  ///
  SchemaBuilder schema([String? connection]) {
    return instance!.connection(connection).getSchemaBuilder();
  }

  ///
  ///  Get a registered connection instance.
  ///
  ///  @param  string  $name
  ///  @return \Illuminate\Database\Connection
  ///
  Connection getConnection([String? name]) {
    return this.manager.connection(name);
  }

  ///
  ///  Register a connection with the manager.
  ///
  ///  @param  array   $config
  ///  @param  string  $name
  ///  @return void
  ///
  void addConnection(Map<String, dynamic> config, [String name = 'default']) {
    var connections = this.container['config']['database.connections'];
    if (connections == null) {
      connections = {name: config};
    } else {
      connections[name] = config;
    }
    this.container['config']['database.connections'] = connections;
  }

  ///
  ///  Bootstrap Eloquent so it is ready for usage.
  ///
  ///  @return void
  ///
  void bootEloquent() {
    //Eloquent::setConnectionResolver(this.manager);

    // If we have an event dispatcher instance, we will go ahead and register it
    // with the Eloquent ORM, allowing for model callbacks while creating and
    // updating "model" instances; however, if it not necessary to operate.
    // if ($dispatcher = this.getEventDispatcher()) {
    //     Eloquent::setEventDispatcher($dispatcher);
    // }
  }

  ///
  ///  Set the fetch mode for the database connections.
  ///
  ///  @param  int  $fetchMode
  ///  @return $this
  ///
  Manager setFetchMode(int fetchMode) {
    this.container['config']['database.fetch'] = fetchMode;

    return this;
  }

  ///
  ///  Get the database manager instance.
  ///
  ///  @return \Illuminate\Database\DatabaseManager
  ///
  DatabaseManager getDatabaseManager() {
    return this.manager;
  }

  ///
  ///  Get the current event dispatcher instance.
  ///
  ///  @return \Illuminate\Contracts\Events\Dispatcher|null
  ///
  dynamic getEventDispatcher() {
    if (this.container.bound('events')) {
      return this.container['events'];
    }
  }

  ///
  ///  Set the event dispatcher instance to be used by connections.
  ///
  ///  @param  \Illuminate\Contracts\Events\Dispatcher  $dispatcher
  ///  @return void
  ///
  void setEventDispatcher($dispatcher) {
    this.container.instance('events', $dispatcher);
  }

  ///
  ///  Dynamically pass methods to the default connection.
  ///
  ///  @param  string  $method
  ///  @param  array   $parameters
  ///  @return mixed
  ///
  // public static function __callStatic($method, $parameters)
  // {
  //     return call_user_func_array([static::connection(), $method], $parameters);
  // }
}
