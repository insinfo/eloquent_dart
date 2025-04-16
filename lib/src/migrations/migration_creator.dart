// lib/src/migrations/migration_creator.dart
import 'dart:io';
import 'package:path/path.dart' as p; // For path joining and manipulation
import 'package:intl/intl.dart'; // For date formatting
import '../support/str.dart'; // For Str.studly()

/// Creates new migration files.
/// Corresponds to Illuminate\Database\Migrations\MigrationCreator.
class MigrationCreator {
  // Use dart:io FileSystemEntity for basic operations
  // For more complex scenarios or testing, consider the 'file' package.

  /// Registered post-creation hooks.
  final List<Function()> _postCreate = [];

  /// Stub content for a blank migration.
  static const String _blankStub = '''
import 'package:eloquent/eloquent.dart';

/// Migration: CreateClassName
class CreateClassName extends Migration {
  /// Run the migrations.
  @override
  Future<void> up() async {
    // Example:
    // await schema.create('table_name', (Blueprint table) {
    //     table.id();
    //     // other columns...
    //     table.timestamps();
    // });
  }

  /// Reverse the migrations.
  @override
  Future<void> down() async {
    // Example:
    // await schema.dropIfExists('table_name');
  }
}
''';

  /// Stub content for creating a new table.
  static const String _createStub = '''
import 'package:eloquent/eloquent.dart';

/// Migration: CreateClassName
class CreateClassName extends Migration {
  /// Run the migrations.
  @override
  Future<void> up() async {
    await schema.create('DummyTable', (Blueprint table) {
        table.id(); // Creates an auto-incrementing BigInt primary key 'id'
        // Add other columns here...
        table.timestamps(); // Adds created_at and updated_at columns
    });
  }

  /// Reverse the migrations.
  @override
  Future<void> down() async {
    await schema.dropIfExists('DummyTable');
  }
}
''';

  /// Stub content for updating/altering an existing table.
  static const String _updateStub = '''
import 'package:eloquent/eloquent.dart';

/// Migration: CreateClassName
class CreateClassName extends Migration {
  /// Run the migrations.
  @override
  Future<void> up() async {
    await schema.table('DummyTable', (Blueprint table) {
        // Add column modifications or new columns here
        // Example: table.string('new_column').nullable();
        // Example: table.renameColumn('old_name', 'new_name');
    });
  }

  /// Reverse the migrations.
  @override
  Future<void> down() async {
    await schema.table('DummyTable', (Blueprint table) {
        // Reverse the changes made in the 'up' method
        // Example: table.dropColumn('new_column');
        // Example: table.renameColumn('new_name', 'old_name');
    });
  }
}
''';


  /// Create a new migration creator instance.
  MigrationCreator(); // Filesystem operations are static in dart:io

  /// Create a new migration file at the given path.
  ///
  /// [name] The descriptive name of the migration (e.g., 'create_users_table').
  /// [path] The directory path where the migration file should be created.
  /// [table] The table name associated with the migration (optional).
  /// [create] Whether the migration creates the table (true) or modifies it (false). Ignored if [table] is null.
  /// Returns the full path to the created migration file.
  /// Throws [FileSystemException] on file system errors.
  Future<String> create(String name, String path, {String? table, bool create = false}) async {
    // Ensure the directory exists
    await _ensureDirectoryExists(path);

    // Get the full path for the new file
    final String filePath = _getPath(name, path);

    // Check if file already exists
    if (await File(filePath).exists()) {
      throw FileSystemException("Migration file already exists.", filePath);
    }

    // Get the appropriate stub content
    final String stub = _getStub(table, create);

    // Populate placeholders in the stub
    final String content = _populateStub(name, stub, table);

    // Write the content to the file
    final file = File(filePath);
    await file.writeAsString(content);

    // Fire post-creation hooks
    _firePostCreateHooks();

    return filePath;
  }

  /// Get the content of the appropriate migration stub file.
  String _getStub(String? table, bool create) {
    if (table == null) {
      return _blankStub;
    } else {
      return create ? _createStub : _updateStub;
    }
  }

  /// Populate the place-holders in the migration stub.
  String _populateStub(String name, String stub, String? table) {
    // Replace DummyClass with the StudlyCase version of the migration name
    String content = stub.replaceAll('CreateClassName', _getClassName(name));

    // Replace DummyTable if a table name was provided
    if (table != null) {
      content = content.replaceAll('DummyTable', table);
    }

    return content;
  }

  /// Get the class name from a migration name.
  /// Example: 'create_users_table' -> 'CreateUsersTable'
  String _getClassName(String name) {
    return Str.studly(name); // Use the Str utility class
  }

  /// Fire the registered post create hooks.
  void _firePostCreateHooks() {
    for (final callback in _postCreate) {
      try {
        callback();
      } catch (e, s) {
        print("Error executing post-create migration hook: $e\n$s");
        // Decide if you want to stop execution or just log errors
      }
    }
  }

  /// Register a post migration create hook.
  void afterCreate(Function() callback) {
    _postCreate.add(callback);
  }

  /// Get the full path name for the migration file.
  String _getPath(String name, String path) {
    // Uses dart:io path joining and date prefix
    return p.join(path, '${_getDatePrefix()}_$name.dart');
  }

  /// Get the date prefix for the migration (YYYY_MM_DD_HHMMSS).
  String _getDatePrefix() {
    final now = DateTime.now();
    // Use intl package for reliable formatting
    return DateFormat('yyyy_MM_dd_HHmmss').format(now);
  }

  /// Ensure the migration directory exists.
  Future<void> _ensureDirectoryExists(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  // StubPath is not directly applicable as stubs are inline strings
  // String getStubPath() { ... }

  // Filesystem instance is not held as a member variable
  // Filesystem getFilesystem() { ... }
}