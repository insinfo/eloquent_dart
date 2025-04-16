// lib/src/migrations/migrator.dart
import 'package:meta/meta.dart';
import 'dart:async';
import 'dart:io'; // For Directory and File access
import 'package:path/path.dart' as p; // For path manipulation
import 'package:eloquent/eloquent.dart'; // Main package imports
import 'migration_repository_interface.dart';
import 'migration.dart';
//import '../support/str.dart'; 

/// Manages and runs database migrations.
/// Corresponds to Illuminate\Database\Migrations\Migrator.
class Migrator {
  /// The migration repository implementation.
  final MigrationRepositoryInterface repository;

  /// The database connection resolver instance.
  final ConnectionResolverInterface resolver;

  // Filesystem interaction needs adaptation for Dart.
  // We might pass a directory path or use dart:io directly.
  // final Filesystem files; // Replace with Dart equivalent if needed

  /// The name of the default connection.
  String? connection;

  /// The notes for the current operation.
  final List<String> notes = [];

  /// Registry mapping migration names (e.g., '2023_..._create_users_table')
  /// to factory functions that create Migration instances.
  /// THIS NEEDS TO BE POPULATED BY THE USER OR A CODE GENERATOR.
  final Map<String, Migration Function()> migrationRegistry;

  /// Create a new migrator instance.
  ///
  /// [repository] Stores migration history.
  /// [resolver] Resolves database connections.
  /// [migrationRegistry] Maps migration names to factories.
  Migrator(this.repository, this.resolver, this.migrationRegistry);


  /// Runs the outstanding migrations found in the specified paths.
  ///
  /// [paths] A list of directory paths containing migration files.
  /// [options] Options map, supporting 'pretend' (bool) and 'step' (bool).
  Future<void> run(List<String> paths, {bool pretend = false, bool step = false}) async {
    notes.clear();

    // 1. Get all migration file names from paths
    final List<String> files = await _getMigrationFiles(paths);

    // 2. Get migrations already run from the repository
    // Ensure repository exists before proceeding
    if (!await repository.repositoryExists()) {
       note('<error>Migration table not found.</error> Run migration setup first.');
       return; // Or throw?
    }
    final List<String> ran = await repository.getRan();

    // 3. Determine migrations to run (files not in ran)
    final List<String> migrationsToRun = files.where((file) => !ran.contains(file)).toList();

    // 4. Run the migrations
    await runMigrationList(migrationsToRun, pretend: pretend, step: step);
  }

  /// Run a specific list of migrations.
  ///
  /// [migrations] List of migration file names to run.
  /// [options] Options map, supporting 'pretend' (bool) and 'step' (bool).
  Future<void> runMigrationList(List<String> migrations, {bool pretend = false, bool step = false}) async {
    if (migrations.isEmpty) {
      note('<info>Nothing to migrate.</info>');
      return;
    }

    // Get the next batch number ONLY if not pretending
    int batch = pretend ? 0 : await repository.getNextBatchNumber();

    // Run migrations
    for (final file in migrations) {
      await _runUp(file, batch, pretend);

      if (step && !pretend) {
        batch++; // Increment batch number for each step if not pretending
      }
    }
  }

  /// Run "up" a migration instance.
  @protected
  Future<void> _runUp(String file, int batch, bool pretend) async {
    // Resolve the migration instance from the registry
    final Migration migration = _resolve(file);

    // Set connection name for the migration instance if needed
    migration.connectionName = connection;
    // Inject DatabaseManager if needed by the Migration's schema getter
    // This depends on how DB access is managed. Example:
    // migration.db = resolver as DatabaseManager; // If resolver is the DB manager

    if (pretend) {
       await _pretendToRun(migration, 'up');
       return; // Don't log in pretend mode
    }

    // Get connection for this migration
    //final conn = await _resolveConnection(migration.getConnectionName());

    // TODO: Implement transaction logic if desired per migration
    try {
       // Execute the 'up' method
       await migration.up();

       // Log the migration if execution was successful
       await repository.log(file, batch);
       note("<info>Migrated:</info> $file");
    } catch (e, s) {
       note("<error>Failed Migration:</error> $file - $e");
       // Optionally rethrow or handle the error
       print(s); // Print stack trace for debugging
       rethrow;
    }
  }

  /// Rollback the last migration operation.
  ///
  /// [steps] How many batches to roll back.
  /// [pretend] If true, simulate the rollback.
  /// Returns the number of migrations rolled back.
  Future<int> rollback({int steps = 1, bool pretend = false}) async {
    notes.clear();

    if (!await repository.repositoryExists()) {
       note('<error>Migration table not found.</error>');
       return 0;
    }

    // Get the migrations from the last 'steps' batches
    final List<Map<String, dynamic>> migrations = await repository.getMigrations(steps);

    final count = migrations.length;

    if (count == 0) {
      note('<info>Nothing to rollback.</info>');
    } else {
       note('<info>Rolling back migrations:</info>');
      // Rollback in reverse order they were retrieved (which was desc)
      for (final migrationMap in migrations) {
        await _runDown(migrationMap, pretend);
      }
    }
    return count;
  }


  /// Rolls all of the currently applied migrations back.
  ///
  /// [pretend] If true, simulate the reset.
  /// Returns the number of migrations rolled back.
  Future<int> reset({bool pretend = false}) async {
    notes.clear();

     if (!await repository.repositoryExists()) {
       note('<error>Migration table not found.</error>');
       return 0;
     }

    // Get all ran migrations in reverse order they should be run down
    final List<String> migrationsToReset = (await repository.getRan()).reversed.toList();
    final count = migrationsToReset.length;

    if (count == 0) {
      note('<info>Nothing to rollback.</info>');
    } else {
       note('<info>Rolling back all migrations:</info>');
      for (final migrationName in migrationsToReset) {
        // Create a map structure similar to what repository->getLast() returns
        final migrationMap = {'migration': migrationName, 'batch': -1}; // Batch number doesn't matter much for reset down
        await _runDown(migrationMap, pretend);
      }
    }
    return count;
  }

  /// Run "down" a migration instance.
  @protected
  Future<void> _runDown(Map<String, dynamic> migrationMap, bool pretend) async {
    final file = migrationMap['migration'] as String;

    final Migration instance = _resolve(file);

    // Set connection name and potentially db manager
    instance.connectionName = connection;
    // instance.db = resolver as DatabaseManager; // If needed

    if (pretend) {
       await _pretendToRun(instance, 'down');
       return; // Don't delete from repository in pretend mode
    }

     // Get connection for this migration
    //final conn = await _resolveConnection(instance.getConnectionName());

    try {
      // Execute the 'down' method
      await instance.down();

      // Delete the migration record if successful
      await repository.delete(migrationMap);
      note("<info>Rolled back:</info> $file");
    } catch (e, s) {
      note("<error>Failed Rollback:</error> $file - $e");
      print(s);
      rethrow;
    }
  }

  /// Get all migration filenames from the given paths.
  Future<List<String>> _getMigrationFiles(List<String> paths) async {
    final List<String> files = [];
    for (final path in paths) {
      final dir = Directory(path);
      if (await dir.exists()) {
        final List<FileSystemEntity> entities = await dir.list().toList();
        for (final entity in entities) {
          if (entity is File) {
            final filename = p.basename(entity.path);
            // Basic pattern matching: YYYY_MM_DD_HHMMSS_*.dart
            if (RegExp(r'^\d{4}_\d{2}_\d{2}_\d{6}_.*?\.dart$').hasMatch(filename)) {
              // Remove .dart extension for the name
              files.add(filename.substring(0, filename.length - 5));
            }
          }
        }
      } else {
         note("<warning>Migration path not found:</warning> $path");
      }
    }
    // Sort files chronologically based on the timestamp prefix
    files.sort();
    return files;
  }

  // Dart doesn't require files explicitly like PHP's requireOnce.
  // Instantiation happens via the registry.
  // void requireFiles(String path, List<String> files) { }

  /// Pretend to run the migrations.
  /// REQUIRES connection.pretend() to be implemented.
  Future<void> _pretendToRun(Migration migration, String method) async {
    final conn = await _resolveConnection(migration.getConnectionName());

    // Check if the connection object supports pretend mode
    if (conn is! Connection || !(conn ).getConfigs()['pretend'] == true ) {
        note("<warning>Pretend mode not supported or enabled for this connection.</warning> Simulating $method for ${migration.runtimeType}");
        if (method == 'up') {
           note(" -> Would run up() method.");
        } else {
           note(" -> Would run down() method.");
        }
        return;
        // Or throw an exception?
        // throw UnsupportedError("Pretend mode requires a Connection object with the 'pretend' config option enabled.");
    }

    try {
        final List<Map<String, dynamic>> queries = await (conn ).pretend(() async {
          if (method == 'up') {
            await migration.up();
          } else {
            await migration.down();
          }
        });

        if (queries.isEmpty) {
            note("<comment>No queries simulated for:</comment> ${migration.runtimeType}.$method()");
        }

        for (final query in queries) {
          final name = migration.runtimeType.toString();
          final sql = query['query'] ?? 'N/A';
          final bindings = query['bindings'] ?? [];
          note("<info>$name:</info> $sql <comment>Bindings: $bindings</comment>");
        }
    } catch (e, s) {
       note("<error>Error during pretend run for ${migration.runtimeType}.$method():</error> $e");
       print(s);
    }
  }

  // getQueries is effectively replaced by pretendToRun

  /// Resolve a migration instance from a file name using the registry.
  @protected
  Migration _resolve(String file) {
    if (!migrationRegistry.containsKey(file)) {
      throw Exception("Migration not found in registry: $file. Ensure migrations are registered.");
    }
    // Call the factory function to get a new instance
    return migrationRegistry[file]!();

    // PHP logic to derive class name:
    // final parts = file.split('_');
    // if (parts.length < 5) throw Exception("Invalid migration filename format: $file");
    // final namePart = parts.sublist(4).join('_');
    // final className = Str.studly(namePart); // Requires Str.studly utility
    // // Instantiation would need reflection or registry here in Dart
    // throw UnimplementedError("Cannot dynamically instantiate class '$className' from file '$file' without reflection or registry.");
  }

  /// Raise a note event for the migrator.
  @protected
  void note(String message) {
    // Simple print for now, replace with proper logging/output
    print(message);
    notes.add(message);
  }

  /// Get the notes for the last operation.
  List<String> getNotes() {
    return List.unmodifiable(notes);
  }

  /// Resolve the database connection instance.
  @protected
  Future<ConnectionInterface> _resolveConnection(String? connectionName) async {
    return resolver.connection(connectionName ?? connection!); // Use instance connection if name is null
  }

  /// Set the default connection name.
  Future<void> setConnection(String? name) async {
    // Set default on resolver ONLY if name is provided
    if (name != null) {
      resolver.setDefaultConnection(name);
    }
    // Set source on repository
    repository.setSource(name);
    // Store the connection name for this migrator instance
    connection = name;
  }

  /// Get the migration repository instance.
  MigrationRepositoryInterface getRepository() {
    return repository;
  }

  /// Determine if the migration repository exists.
  Future<bool> repositoryExists() {
    return repository.repositoryExists();
  }

  // Filesystem instance is not directly used in this Dart version
  // Filesystem getFilesystem() { return files; }
}