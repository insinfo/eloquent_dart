import 'package:eloquent/eloquent.dart';

class SchemaBuilder {
  ///
  /// The database connection instance.
  ///
  /// @var \Illuminate\Database\Connection
  ///
  late Connection connection;

  ///
  /// The schema grammar instance.
  ///
  /// @var \Illuminate\Database\Schema\Grammars\Grammar
  ///
  late SchemaGrammar grammar;

  ///
  /// The Blueprint resolver callback.
  ///
  /// @var \Closure
  ///
  Function? resolver;

  ///
  /// Create a new database Schema manager.
  ///
  /// @param  \Illuminate\Database\Connection  $connection
  ///
  ///
  SchemaBuilder(this.connection) {
    grammar = connection.getSchemaGrammar();
  }

  ///
  /// Determine if the given table exists.
  ///
  /// @param  string  $table
  /// @return bool
  ///
  bool hasTable(String tableP) {
    var sql = grammar.compileTableExists();

    var table = this.connection.getTablePrefix() + tableP;

    return Utils.count(this.connection.select(sql, [table])) > 0;
  }

  ///
  /// Determine if the given table has a given column.
  ///
  /// @param  string  $table
  /// @param  string  $column
  /// @return bool
  ///
  bool hasColumn(String table, String columnP) {
    var column = Utils.strtolower(columnP);
    return Utils.in_array(
        column, Utils.array_map(Utils.strtolower, getColumnListing(table)));
  }

  ///
  /// Determine if the given table has given columns.
  ///
  /// @param  string  $table
  /// @param  array   $columns
  /// @return bool
  ///
  bool hasColumns(String table, List columns) {
    var tableColumns =
        Utils.array_map(Utils.strtolower, getColumnListing(table));

    for (var column in columns) {
      if (!Utils.in_array(Utils.strtolower(column), tableColumns)) {
        return false;
      }
    }

    return true;
  }

  ///
  /// Get the column listing for a given table.
  ///
  /// @param  string  $table
  /// @return array
  ///
  List getColumnListing(String tableP) {
    var table = connection.getTablePrefix() + tableP;
    var results = connection.select(grammar.compileColumnExists(table));
    return connection.getPostProcessor().processColumnListing(results);
  }

  ///
  /// Modify a table on the schema.
  ///
  /// @param  string    $table
  /// @param  \Closure  $callback
  /// @return \Illuminate\Database\Schema\Blueprint
  ///
  dynamic table(String table, Function callback) {
    build(createBlueprint(table, callback));
  }

  ///
  /// Create a new table on the schema.
  ///
  /// @param  string    $table
  /// @param  \Closure  $callback
  /// @return \Illuminate\Database\Schema\Blueprint
  ///
  dynamic create(String table, Function callback) {
    var blueprint = createBlueprint(table);

    blueprint.create();

    callback(blueprint);

    build(blueprint);
  }

  ///
  /// Drop a table from the schema.
  ///
  /// @param  string  $table
  /// @return \Illuminate\Database\Schema\Blueprint
  ///
  dynamic drop(String table) {
    var blueprint = createBlueprint(table);

    blueprint.drop();

    build(blueprint);
  }

  ///
  /// Drop a table from the schema if it exists.
  ///
  /// @param  string  $table
  /// @return \Illuminate\Database\Schema\Blueprint
  ///
  dynamic dropIfExists(String table) {
    var blueprint = createBlueprint(table);

    blueprint.dropIfExists();

    build(blueprint);
  }

  ///
  /// Rename a table on the schema.
  ///
  /// @param  string  $from
  /// @param  string  $to
  /// @return \Illuminate\Database\Schema\Blueprint
  ///
  dynamic rename(String from, String to) {
    var blueprint = createBlueprint(from);

    blueprint.rename(to);

    build(blueprint);
  }

  ///
  /// Execute the blueprint to build / modify the table.
  ///
  /// @param  \Illuminate\Database\Schema\Blueprint  $blueprint
  /// @return void
  ///
  void build(Blueprint blueprint) {
    blueprint.build(connection, grammar);
  }

  ///
  /// Create a new command set with a Closure.
  ///
  /// @param  string  $table
  /// @param  \Closure|null  $callback
  /// @return \Illuminate\Database\Schema\Blueprint
  ///
  dynamic createBlueprint(String table, [Function? callback]) {
    if (this.resolver != null) {
      //return call_user_func($this->resolver, $table, $callback);
      this.resolver!(table, callback);
    }

    return Blueprint(table, callback);
  }

  ///
  /// Get the database connection instance.
  ///
  /// @return \Illuminate\Database\Connection
  ///
  Connection getConnection() {
    return connection;
  }

  ///
  /// Set the database connection instance.
  ///
  /// @param  \Illuminate\Database\Connection  $connection
  /// @return $this
  ///
  dynamic setConnection(Connection connectionP) {
    connection = connectionP;
    return this;
  }

  ///
  /// Set the Schema Blueprint resolver callback.
  ///
  /// @param  \Closure  $resolver
  /// @return void
  ///
  void blueprintResolver(Function resolver) {
    resolver = resolver;
  }
}
