// lib/src/migrations/database_migration_repository.dart
import 'dart:async';
import 'package:eloquent/eloquent.dart'; // Access to QueryBuilder, ConnectionResolverInterface, etc.
import 'package:eloquent/src/schema/schema_builder.dart';
import 'migration_repository_interface.dart';

/// Database-backed implementation of the migration repository.
///
/// Stores migration history in a specified database table.
/// Corresponds to Illuminate\Database\Migrations\DatabaseMigrationRepository.
class DatabaseMigrationRepository implements MigrationRepositoryInterface {
  /// The database connection resolver instance.
  final ConnectionResolverInterface resolver;

  /// The name of the migration table (e.g., 'migrations').
  final String table;

  /// The name of the database connection to use (null for default).
  String? connectionName;

  /// Create a new database migration repository instance.
  ///
  /// [resolver] Used to get database connections.
  /// [table] The name of the table to store migration logs.
  DatabaseMigrationRepository(this.resolver, this.table);

  /// Get the ran migrations.
  @override
  Future<List<String>> getRan() async {
    final query = await _table(); // Get QueryBuilder
    final results = await query
        .orderBy('batch', 'asc')
        .orderBy('migration', 'asc')
        .pluck('migration'); // Pluck returns List<dynamic>
    // Cast the result to List<String>
    return List<String>.from(results as List);
  }

  /// Get the last migration batch.
  @override
  Future<List<Map<String, dynamic>>> getLast() async {
    final lastBatch = await getLastBatchNumber();
    if (lastBatch == 0) return []; // No batches run yet

    final query = await _table();
    return query
        .where('batch', '=', lastBatch)
        .orderBy('migration', 'desc')
        .get();
  }

  /// Get the migrations based on a batch limit.
  @override
  Future<List<Map<String, dynamic>>> getMigrations(int steps) async {
    final query = await _table();
    final results = await query
        .where('batch', '>=', 1) // Ensure batch is valid
        .orderBy('batch', 'desc')
        .orderBy('migration', 'desc')
        .take(
            steps) // Limit by number of migrations, not batches directly like PHP
        .get();
    // Note: The PHP version limits by batch number difference, which is harder
    // to replicate precisely without knowing max batch first. This limits by row count.
    return results;
  }

  /// Log that a migration was run.
  @override
  Future<void> log(String file, int batch) async {
    final record = {'migration': file, 'batch': batch};
    final query = await _table();
    await query.insert(record); // insert returns Future<dynamic>
  }

  /// Remove a migration from the log.
  @override
  Future<void> delete(Map<String, dynamic> migration) async {
    // Assumes migration map has a 'migration' key with the file name
    final migrationName = migration['migration'] as String?;
    if (migrationName == null) return;

    final query = await _table();
    await query.where('migration', '=', migrationName).delete();
  }

  /// Get the next migration batch number.
  @override
  Future<int> getNextBatchNumber() async {
    return (await getLastBatchNumber()) + 1;
  }

  /// Get the last migration batch number.
  Future<int> getLastBatchNumber() async {
    final query = await _table();
    final maxBatch =
        await query.max('batch'); // max() might return num? or String?
    if (maxBatch == null) return 0;
    if (maxBatch is int) return maxBatch;
    if (maxBatch is double) return maxBatch.toInt(); // Handle potential double
    if (maxBatch is String) return (maxBatch as int?) ?? 0;
    return 0; // Default if type is unexpected
  }

  /// Create the migration repository data store.
  @override
  Future<void> createRepository() async {
    final schema = await _getSchemaBuilder();

    await schema.create(table, (Blueprint blueprint) {
      // Corresponds to $table->string('migration');
      blueprint.string('migration');
      // Corresponds to $table->integer('batch');
      blueprint.integer('batch');
    });
  }

  /// Determine if the migration repository exists.
  @override
  Future<bool> repositoryExists() async {
    final schema = await _getSchemaBuilder();
    return schema.hasTable(table);
  }

  /// Delete the migration repository data store.
  @override
  Future<void> deleteRepository() async {
    final schema = await _getSchemaBuilder();
    await schema.dropIfExists(table);
  }

  /// Get a query builder for the migration table. (Helper)
  Future<QueryBuilder> _table() async {
    final conn = await _getConnection();
    return conn.table(table);
  }

  /// Get the schema builder instance. (Helper)
  Future<SchemaBuilder> _getSchemaBuilder() async {
    final conn = await _getConnection();
    // Assuming ConnectionInterface or concrete Connection has getSchemaBuilder
    if (conn is Connection) {
      return conn.getSchemaBuilder();
    } else {
      // Need a way to get SchemaBuilder from ConnectionInterface
      throw UnsupportedError(
          'Cannot get SchemaBuilder from the provided connection.');
    }
  }

  /// Get the connection resolver instance.
  ConnectionResolverInterface getConnectionResolver() {
    return resolver;
  }

  /// Resolve the database connection instance. (Helper)
  Future<ConnectionInterface> _getConnection() async {
    return resolver.connection(connectionName!); // Pass optional connection name
  }

  /// Set the information source (connection name).
  @override
  void setSource(String? name) {
    connectionName = name;
  }
}
