import 'dart:async';

import '../database_manager.dart';

/// Base class for database seeders (no code generation).
///
/// Subclasses implement [run] to insert data. Seeders are registered and
/// executed explicitly by the application (or via the CLI), e.g.:
///
/// ```dart
/// class DatabaseSeeder extends Seeder {
///   @override
///   Future<void> run() async {
///     await call(UsersSeeder());
///     await db!.table('settings').insert({'key': 'installed', 'value': '1'});
///   }
/// }
///
/// await SeederRunner(manager).call(DatabaseSeeder());
/// ```
abstract class Seeder {
  /// The database manager, injected before [run] is invoked.
  DatabaseManager? db;

  /// The connection name to use (null = default).
  String? connectionName;

  /// Seed the application's database.
  Future<void> run();

  /// Run one or more child seeders, propagating [db]/[connectionName].
  Future<void> call(dynamic seeders) async {
    final list = seeders is Iterable ? seeders : [seeders];
    for (final s in list) {
      if (s is Seeder) {
        s.db ??= db;
        s.connectionName ??= connectionName;
        await s.run();
      } else {
        throw ArgumentError.value(
          s,
          'seeders',
          'Expected a Seeder or Iterable<Seeder>.',
        );
      }
    }
  }
}
