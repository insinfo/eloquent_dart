import 'dart:async';

import '../database_manager.dart';
import 'seeder.dart';

/// Runs [Seeder]s, injecting the [DatabaseManager] so seeders can reach the
/// query builder via `db!.table(...)`.
class SeederRunner {
  final DatabaseManager manager;
  final String? connectionName;

  SeederRunner(this.manager, {this.connectionName});

  /// Run a single seeder or an iterable of seeders.
  Future<void> call(dynamic seeders) async {
    final list = seeders is Iterable ? seeders : [seeders];
    for (final s in list) {
      if (s is! Seeder) {
        throw ArgumentError.value(
          s,
          'seeders',
          'Expected a Seeder or Iterable<Seeder>.',
        );
      }
      s.db ??= manager;
      s.connectionName ??= connectionName;
      await s.run();
    }
  }
}
