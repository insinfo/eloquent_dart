// ignore_for_file: unnecessary_null_comparison

import 'package:eloquent/eloquent.dart';
import 'package:meta/meta.dart';
import 'dart:async';

/// Provides an API for managing the database schema.
/// Mirrors Laravel's Illuminate\Database\Schema\Builder.
class SchemaBuilder {
  /// The database connection.
  late Connection connection;

  /// The schema grammar instance, determined by the connection.
  late SchemaGrammar grammar;

  /// An optional callback to resolve Blueprint instances.
  /// Allows for customizing Blueprint creation.
  Function(String table, Function(Blueprint)? callback)? resolver;

  /// Precision of the time columns (`timestamp`, `dateTime`, `time` and their
  /// `Tz` forms) made without an explicit `precision:` (Laravel 11's
  /// `Schema::defaultTimePrecision`).
  ///
  /// `null` (the default) writes no precision: PostgreSQL keeps
  /// microseconds, which the DateTime bindings send. `0` is Laravel's
  /// default (`timestamp(0)`): PostgreSQL then rounds a fraction to the
  /// nearest second, so 10:20:30.6 is stored as 10:20:31.
  static int? defaultTimePrecision;

  /// Creates a schema builder for [connection], with its schema grammar.
  SchemaBuilder(Connection connection) {
    setConnection(
        connection); // Use setter to initialize connection and grammar
  }

  /// Whether the table [tableName] (without the table prefix) exists in the
  /// connection's schema.
  ///
  /// The schema is the first name of the `schema` config, else the
  /// `database` config, else the connection's database name, else `public`.
  Future<bool> hasTable(String tableName) async {
    final String schema = await _getSchemaName();
    final String sql = grammar.compileTableExists();
    // Query information_schema using schema and table name without prefix
    final results = await connection.select(sql, [schema, tableName]);
    return results.isNotEmpty;
  }

  /// Whether the table [tableName] (without the table prefix) has the column
  /// [columnName]. Case is ignored.
  Future<bool> hasColumn(String tableName, String columnName) async {
    final column = columnName.toLowerCase();
    // getColumnListing is now async
    final tableColumns = await getColumnListing(tableName);
    return tableColumns.map((c) => c.toLowerCase()).contains(column);
  }

  /// Whether the table [tableName] (without the table prefix) has all of
  /// [columns]. Case is ignored.
  Future<bool> hasColumns(String tableName, List<String> columns) async {
    final tableColumns = (await getColumnListing(tableName)) // await async call
        .map((c) => c.toLowerCase())
        .toSet(); // Use Set for efficient lookups

    for (final column in columns) {
      if (!tableColumns.contains(column.toLowerCase())) {
        return false;
      }
    }
    return true;
  }

  /// Returns the column names of the table [tableName] (without the table
  /// prefix) in the connection's schema (see [hasTable]).
  Future<List<String>> getColumnListing(String tableName) async {
    final String schema = await _getSchemaName();
    final String sql = grammar
        .compileColumnExists(tableName); // Grammar expects unprefixed name

    // Query information_schema using schema and table name
    final results = await connection.select(sql, [schema, tableName]);

    if (results.isEmpty) {
      return [];
    }
    // Assumes the query returns maps with 'column_name' key
    return results.map((row) => row['column_name'] as String).toList();
  }

  /// Modifies the existing table [tableName]; [callback] receives the
  /// [Blueprint] that describes the changes.
  Future<void> table(String tableName, Function(Blueprint) callback) async {
    // The blueprint runs the callback when it is created.
    await build(createBlueprint(tableName, callback));
  }

  /// Creates the table [tableName]; [callback] receives the [Blueprint] that
  /// defines its columns and indexes.
  Future<void> create(String tableName, Function(Blueprint) callback) async {
    final blueprint = createBlueprint(tableName);
    blueprint.create(); // Marca a intenção de criar
    callback(blueprint); // Permite ao usuário definir a estrutura
    await build(blueprint); // Executa o blueprint
  }

  /// Drops the table [tableName].
  Future<void> drop(String tableName) async {
    final blueprint = createBlueprint(tableName);
    blueprint.drop();
    await build(blueprint);
  }

  /// Drops the table [tableName] if it exists.
  Future<void> dropIfExists(String tableName) async {
    final blueprint = createBlueprint(tableName);
    blueprint.dropIfExists();
    await build(blueprint);
  }

  /// Renames the table [from] to [to].
  Future<void> rename(String from, String to) async {
    final blueprint = createBlueprint(from);
    blueprint.rename(to);
    await build(blueprint);
  }

  /// Enables foreign key constraints, if the grammar supports it.
  ///
  /// Returns `true` when the statements ran, and `false`, after printing a
  /// message, when the grammar has no statements for it or one of them fails.
  Future<bool> enableForeignKeyConstraints() async {
    // Asks the grammar for the SQL.
    final List<String> sqlCommands =
        grammar.compileEnableForeignKeyConstraints();
    if (sqlCommands.isEmpty) {
      print(
          "Warning: enableForeignKeyConstraints() is not supported by the current database grammar (${grammar.runtimeType}).");
      return false; // Não suportado pela gramática
    }
    try {
      for (final sql in sqlCommands) {
        // execute(), as these statements return no rows.
        await connection.execute(sql);
      }
      return true;
    } catch (e) {
      print("Error enabling foreign key constraints: $e");
      return false; // Falha na execução
    }
  }

  /// Disables foreign key constraints, if the grammar supports it.
  ///
  /// Returns `true` when the statements ran, and `false`, after printing a
  /// message, when the grammar has no statements for it or one of them fails.
  Future<bool> disableForeignKeyConstraints() async {
    final List<String> sqlCommands =
        grammar.compileDisableForeignKeyConstraints();
    if (sqlCommands.isEmpty) {
      print(
          "Warning: disableForeignKeyConstraints() is not supported by the current database grammar (${grammar.runtimeType}).");
      return false;
    }
    try {
      for (final sql in sqlCommands) {
        await connection.execute(sql);
      }
      return true;
    } catch (e) {
      print("Error disabling foreign key constraints: $e");
      return false;
    }
  }

  /// Runs the statements of [blueprint] on [connection].
  @protected
  Future<void> build(Blueprint blueprint) async {
    // The blueprint compiles its commands with [grammar] and runs them.
    await blueprint.build(connection, grammar);
  }

  /// Creates the [Blueprint] for [table], with [resolver] when it is set.
  /// [callback], if given, receives the new blueprint.
  @protected
  Blueprint createBlueprint(String table, [Function(Blueprint)? callback]) {
    if (resolver != null) {
      // The resolver must return a Blueprint.
      return resolver!(table, callback) as Blueprint;
    }
    return Blueprint(table, callback);
  }

  /// Returns the database connection.
  ConnectionInterface getConnection() {
    return connection;
  }

  /// Sets the database connection and takes the schema grammar from it.
  SchemaBuilder setConnection(Connection connectionP) {
    connection = connectionP;

    grammar = connection.getSchemaGrammar();

    return this;
  }

  /// Sets the [resolver] that creates the blueprints; `null` goes back to the
  /// [Blueprint] constructor.
  void blueprintResolver(
      Function(String table, Function(Blueprint)? callback)? resolverCallback) {
    resolver = resolverCallback;
  }

  /// Returns the schema used for introspection: the first name of the
  /// `schema` config, else the `database` config, else the connection's
  /// database name, else `public` (with a warning).
  Future<String> _getSchemaName() async {
    String? schema;

    final connImpl = connection;
    // The 'schema' config may be a String, a comma-separated String, or a List
    // (search path). Normalize to the first schema name for introspection.
    schema = _normalizeSchemaConfig(connImpl.getConfig('schema')) ??
        _normalizeSchemaConfig(connImpl.getConfig('database'));

    // Not in the config: use the connection's database name.
    schema ??= connection.getDatabaseName();

    if (schema == null || schema.isEmpty) {
      print(
          "Warning: Could not determine schema/database name. Falling back to 'public' or potential errors.");
      // The usual PostgreSQL default; it may be wrong for other databases.
      return 'public';
    }
    return schema;
  }

  /// Normalize a schema config value (String | List | comma-separated String)
  /// to a single schema name (the first one), or null when empty.
  String? _normalizeSchemaConfig(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      return value.isEmpty ? null : value.first.toString();
    }
    final s = value.toString();
    if (s.isEmpty) return null;
    final comma = s.indexOf(',');
    return comma == -1 ? s : s.substring(0, comma).trim();
  }
}
