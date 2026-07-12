// bin/eloquent.dart
//
// Minimal scaffolding CLI for the eloquent package.
//
//   dart run eloquent:eloquent make:migration create_users_table --create=users
//   dart run eloquent:eloquent make:migration add_age_to_users --table=users
//   dart run eloquent:eloquent make:seeder UsersSeeder
//
// `make:migration` and `make:seeder` generate source files only (no code
// generation / reflection). Running/rolling back migrations and seeding are
// done from your own app entrypoint, which owns the explicit registry:
//
//   final migrator = Migrator(repo, manager, {
//     '2026_..._create_users_table': () => CreateUsersTable(),
//   }, databaseManager: manager);
//   await migrator.runMigrationList([...]);
//
// See docs/PERFORMANCE_REWRITE_PLAN.md and the integration test
// test/migrations_seeders_integration_test.dart for a full example.

import 'dart:io';

import 'package:eloquent/eloquent.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _usage();
    exit(64);
  }

  final command = args.first;
  final rest = args.sublist(1);
  final flags = _parseFlags(rest);
  final positional = rest.where((a) => !a.startsWith('--')).toList();

  switch (command) {
    case 'make:migration':
      await _makeMigration(positional, flags);
      break;
    case 'make:seeder':
      await _makeSeeder(positional, flags);
      break;
    case 'help':
    case '--help':
    case '-h':
      _usage();
      break;
    default:
      stderr.writeln('Unknown command: $command\n');
      _usage();
      exit(64);
  }
}

Future<void> _makeMigration(
    List<String> positional, Map<String, String> flags) async {
  if (positional.isEmpty) {
    stderr.writeln('Usage: make:migration <name> '
        '[--table=<t> | --create=<t>] [--path=<dir>]');
    exit(64);
  }
  final name = positional.first;
  final path = flags['path'] ?? 'migrations';

  String? table = flags['table'] ?? flags['create'];
  final create = flags.containsKey('create');

  final creator = MigrationCreator();
  final filePath =
      await creator.create(name, path, table: table, create: create);
  stdout.writeln('Created migration: $filePath');
}

Future<void> _makeSeeder(
    List<String> positional, Map<String, String> flags) async {
  if (positional.isEmpty) {
    stderr.writeln('Usage: make:seeder <ClassName> [--path=<dir>]');
    exit(64);
  }
  final className = positional.first;
  final path = flags['path'] ?? 'seeders';
  await Directory(path).create(recursive: true);

  final fileName = '${_snake(className)}.dart';
  final filePath = '$path/$fileName';
  final file = File(filePath);
  if (await file.exists()) {
    stderr.writeln('Seeder file already exists: $filePath');
    exit(1);
  }

  await file.writeAsString('''
import 'package:eloquent/eloquent.dart';

/// Seeder: $className
class $className extends Seeder {
  @override
  Future<void> run() async {
    final conn = await db!.connection(connectionName);
    // await conn.table('table_name').insert({'column': 'value'});
  }
}
''');
  stdout.writeln('Created seeder: $filePath');
}

Map<String, String> _parseFlags(List<String> args) {
  final flags = <String, String>{};
  for (final a in args) {
    if (a.startsWith('--')) {
      final eq = a.indexOf('=');
      if (eq == -1) {
        flags[a.substring(2)] = '';
      } else {
        flags[a.substring(2, eq)] = a.substring(eq + 1);
      }
    }
  }
  return flags;
}

String _snake(String s) {
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    final lower = ch.toLowerCase();
    if (ch != lower && i > 0) buf.write('_');
    buf.write(lower);
  }
  return buf.toString();
}

void _usage() {
  stdout.writeln('''
eloquent — scaffolding CLI

Commands:
  make:migration <name> [--create=<table> | --table=<table>] [--path=migrations]
      Generate a migration file. --create scaffolds a CREATE TABLE migration;
      --table scaffolds an ALTER TABLE migration.

  make:seeder <ClassName> [--path=seeders]
      Generate a Seeder subclass file.

  help
      Show this help.

Note: running/rolling back migrations and seeding are driven from your app,
which owns the explicit migration registry (no code generation). See
docs/PERFORMANCE_REWRITE_PLAN.md.
''');
}
