// lib/src/migrations/migration.dart
import 'dart:async';
import '../schema/schema_builder.dart'; // Need Schema facade
import '../database_manager.dart'; // Need DatabaseManager or similar

/// Abstract base class for database migrations.
///
/// Subclasses should implement the `up()` and `down()` methods.
/// Corresponds to Illuminate\Database\Migrations\Migration.
abstract class Migration {
  /// The database connection instance to use for the migration.
  /// This might be injected or resolved differently than in Laravel.
  /// Option 1: Inject the connection directly.
  /// Option 2: Inject a resolver and connection name.
  /// For simplicity here, we'll assume access to a global resolver or pass connection.
  // late ConnectionInterface connection; // Option 1
  DatabaseManager? db; // Or a similar way to access connections/schema builder
  String? connectionName; // Option 2

  /// The Schema builder instance for the default or specified connection.
  Future<SchemaBuilder> get schema async {
    // <--- Marcado como async
    if (db == null) {
      throw StateError('DatabaseManager (db) is not set on this migration.');
    }
    // Usa await para esperar o Future<SchemaBuilder> retornado pelo DatabaseManager
    return await db!.schema(connectionName); // <--- Usa await
  }

  /// Runs the migration "up" - applying schema changes.
  /// Must be implemented by subclasses.
  Future<void> up();

  /// Reverts the migration "down" - undoing schema changes.
  /// Must be implemented by subclasses.
  Future<void> down();

  /// Get the migration connection name.
  /// Returns the specific connection this migration should run on, or null for default.
  String? getConnectionName() {
    return connectionName;
  }
}
