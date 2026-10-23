// lib/src/migrations/migration_repository_interface.dart
import 'dart:async';

/// Interface defining the contract for migration repositories.
///
/// Corresponds to Illuminate\Database\Migrations\MigrationRepositoryInterface.
abstract class MigrationRepositoryInterface {
  /// Returns the names of the migrations that have already run (e.g.
  /// `2023_10_27_000000_create_users_table`).
  Future<List<String>> getRan();

  /// Returns the records of the migrations in the latest batch.
  Future<List<Map<String, dynamic>>> getLast();

  /// Returns the records of the migrations in the last [steps] batches.
  Future<List<Map<String, dynamic>>> getMigrations(
      int steps); // Added based on Migrator usage

  /// Records that the migration [file] ran, in batch [batch].
  Future<void> log(String file, int batch);

  /// Removes [migration], a record whose `migration` key is the migration
  /// name, from the log.
  Future<void> delete(Map<String, dynamic> migration);

  /// Get the next migration batch number.
  Future<int> getNextBatchNumber();

  /// Create the migration repository data store (the migrations table).
  Future<void> createRepository();

  /// Determine if the migration repository (the table) exists.
  Future<bool> repositoryExists();

  /// Delete the migration repository data store.
  Future<void> deleteRepository(); // Added based on Migrator usage

  /// Sets the name of the connection the repository uses; `null` is the
  /// default connection.
  void setSource(String? name);
}
