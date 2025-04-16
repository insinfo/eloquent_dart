// lib/src/migrations/migration_repository_interface.dart
import 'dart:async';

/// Interface defining the contract for migration repositories.
///
/// Corresponds to Illuminate\Database\Migrations\MigrationRepositoryInterface.
abstract class MigrationRepositoryInterface {

  /// Get the list of migration file names that have already been run.
  /// Returns a list of migration file names (e.g., '2023_10_27_000000_create_users_table').
  Future<List<String>> getRan();

  /// Get the migrations from the latest batch number.
  /// Returns a list of migration records (typically Maps).
  Future<List<Map<String, dynamic>>> getLast();

  /// Get the list of migrations based on a batch limit.
  /// [steps] The number of batches to retrieve migrations from.
  /// Returns a list of migration records (typically Maps).
  Future<List<Map<String, dynamic>>> getMigrations(int steps); // Added based on Migrator usage

  /// Log that a migration was run.
  ///
  /// [file] The name of the migration file.
  /// [batch] The batch number it belongs to.
  Future<void> log(String file, int batch);

  /// Remove a migration record from the log.
  ///
  /// [migration] The migration record (Map) or just the migration name (String).
  ///             Using Map allows access to 'migration' key like the PHP object.
  Future<void> delete(Map<String, dynamic> migration);

  /// Get the next migration batch number.
  Future<int> getNextBatchNumber();

  /// Create the migration repository data store (the migrations table).
  Future<void> createRepository();

  /// Determine if the migration repository (the table) exists.
  Future<bool> repositoryExists();

  /// Delete the migration repository data store.
  Future<void> deleteRepository(); // Added based on Migrator usage

  /// Set the information source (database connection name) to gather data from.
  /// [name] The name of the connection.
  void setSource(String? name);
}