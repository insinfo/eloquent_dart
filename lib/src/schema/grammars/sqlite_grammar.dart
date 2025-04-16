import 'package:eloquent/eloquent.dart';
import 'package:meta/meta.dart';

/// Schema Grammar specific to SQLite.
/// Translates Blueprint commands into SQLite DDL SQL.
class SchemaSqliteGrammar extends SchemaGrammar {
  /// The possible column modifiers supported by SQLite (simplified).
  /// SQLite has limited ALTER TABLE capabilities.
  @override
  final List<String> modifiers = const [
    'Nullable',
    'Default',
    'Increment', // Maps to PRIMARY KEY AUTOINCREMENT
    // Modifiers like Unsigned, Charset, Collate, After, First, Comment, Srid, VirtualAs, StoredAs are NOT standard SQLite features.
  ];

  /// The column types that can be implicitly auto-incrementing in SQLite
  /// when combined with PRIMARY KEY. Only 'integer' is truly special.
  @override
  final List<String> serials = const [
    'integer', // Only INTEGER PRIMARY KEY truly auto-increments in SQLite standard behavior
    'bigInteger', // Maps to INTEGER
    'mediumInteger', // Maps to INTEGER
    'smallInteger', // Maps to INTEGER
    'tinyInteger', // Maps to INTEGER
  ];

  SchemaSqliteGrammar() : super();

  /// Overrides initialization for SQLite specific modifiers.
  @override
  @protected
  Map<String, Function(Blueprint, Fluent)> initializeModifierCompilers() {
    // Only include modifiers actually handled by SQLite Grammar
    return {
      'Nullable': (b, c) => modifyNullable(b, c),
      'Default': (b, c) => modifyDefault(b, c),
      'Increment': (b, c) =>
          modifyIncrementing(b, c), // Handles PRIMARY KEY AUTOINCREMENT
    };
  }

  /// Compile the query to determine if a table exists.
  @override
  String compileTableExists() {
    // SQLite uses sqlite_master (or sqlite_schema in newer versions)
    return "select * from sqlite_master where type = 'table' and name = ?";
  }

  /// Compile the query to determine the list of columns.
  /// Note: Table name might need escaping/sanitizing if it contains special chars.
  @override
  String compileColumnExists(String table) {
    // Use PRAGMA table_info. Replace dots in table name as SQLite doesn't support them directly.
    // Wrapping might be needed if table names have spaces or reserved words.
    // Let's assume basic names for now, wrapTable handles quoting.
    final wrappedTable =
        wrapValue(table.replaceAll('.', '__')); // Basic dot replacement
    return 'pragma table_info($wrappedTable)';
  }

  /// Compile a create table command.
  /// SQLite requires PRIMARY KEY and FOREIGN KEY definitions inline.
  @override
  List<String> compileCreate(
      Blueprint blueprint, Fluent command, Connection connection) {
    final columns = getColumns(blueprint).join(', ');

    String sql = blueprint.temporaryV ? 'create temporary' : 'create';
    sql += ' table ${wrapTable(blueprint)} ($columns';

    // Add foreign keys defined in the blueprint inline
    sql += _addForeignKeys(blueprint);

    // Add primary key defined in the blueprint inline (if not already handled by autoincrement)
    sql += _addPrimaryKeys(blueprint);

    sql += ')';

    // SQLite doesn't support ENGINE, CHARSET, COLLATION clauses
    return [sql];
  }

  /// Get the foreign key syntax for a table creation statement.
  @protected
  String _addForeignKeys(Blueprint blueprint) {
    String sql = '';
    final foreigns = getCommandsByName(blueprint, 'foreign');

    for (final foreign in foreigns) {
      sql += _getForeignKey(foreign); // Get base FK clause

      // Add ON DELETE / ON UPDATE clauses
      if (foreign['onDelete'] != null) {
        sql += ' on delete ${foreign['onDelete']}';
      }
      if (foreign['onUpdate'] != null) {
        sql += ' on update ${foreign['onUpdate']}';
      }
      // SQLite supports DEFERRABLE INITIALLY DEFERRED/IMMEDIATE, but less common
    }
    return sql;
  }

  /// Get the SQL snippet for a single foreign key definition (inline).
  @protected
  String _getForeignKey(Fluent foreign) {
    final onTable = wrapTable(foreign['on']);
    final columns = columnize(foreign['columns'] as List);
    final onColumns =
        columnize(List<String>.from(foreign['references'] as List));

    // SQLite uses `, FOREIGN KEY (...) REFERENCES ...` syntax inline
    return ', foreign key($columns) references $onTable($onColumns)';
  }

  /// Get the primary key syntax for a table creation statement (if not handled by AUTOINCREMENT).
  @protected
  String _addPrimaryKeys(Blueprint blueprint) {
    final primary = getCommandByName(blueprint, 'primary');

    // Check if a primary key command exists AND if no column is already marked
    // as autoincrement (which implies PRIMARY KEY in SQLite when type is INTEGER)
    bool autoIncrementExists = blueprint
        .getColumns()
        .any((col) => col['autoIncrement'] == true && col['type'] == 'integer');

    if (primary != null && !autoIncrementExists) {
      final columns = columnize(primary['columns'] as List);
      // SQLite uses `, PRIMARY KEY (...)` syntax inline
      return ', primary key ($columns)';
    }
    return ''; // Return empty if handled by autoincrement or no PK command
  }

  /// Compile alter table commands for adding columns.
  /// SQLite adds columns one by one.
  @override
  List<String> compileAdd(Blueprint blueprint, Fluent command) {
    final table = wrapTable(blueprint);
    // getColumns() generates the full definition for each new column
    final columnsDefinitions = getColumns(blueprint);

    final statements = <String>[];
    for (final columnDefinition in columnsDefinitions) {
      // SQLite uses ALTER TABLE ... ADD COLUMN syntax
      statements.add('alter table $table add column $columnDefinition');
    }
    return statements;
  }

  /// Compile a unique key command.
  /// SQLite creates unique constraints via CREATE UNIQUE INDEX.
  @override
  List<String> compileUnique(Blueprint blueprint, Fluent command) {
    final indexName = wrap(command['index']);
    final columns = columnize(command['columns'] as List);
    final table = wrapTable(blueprint);
    return ['create unique index $indexName on $table ($columns)'];
  }

  /// Compile a plain index key command.
  /// SQLite creates indexes via CREATE INDEX.
  @override
  List<String> compileIndex(Blueprint blueprint, Fluent command) {
    final indexName = wrap(command['index']);
    final columns = columnize(command['columns'] as List);
    final table = wrapTable(blueprint);
    return ['create index $indexName on $table ($columns)'];
  }

  /// Compile a spatial index command.
  /// SQLite requires specific extensions (like SpatiaLite) and syntax for spatial indexes.
  /// This basic implementation throws an error.
  @override
  List<String> compileSpatialIndex(Blueprint blueprint, Fluent command) {
    throw UnimplementedError(
        "Spatial indexes require specific extensions (e.g., SpatiaLite) and are not supported by the default SQLite grammar.");
    // Example (if SpatiaLite was assumed):
    // final indexName = wrap(command['index']);
    // final table = blueprint.getTable(); // SpatiaLite functions often use unquoted names
    // final column = wrap(command['columns'][0]); // Assuming single column for simplicity
    // return ["SELECT CreateSpatialIndex(${escapeString(table)}, ${escapeString(column)})"]; // Needs proper escaping
  }

  /// Compile a foreign key command (adding FK after table creation).
  /// SQLite does NOT support adding foreign keys via ALTER TABLE.
  @override
  List<String> compileForeign(Blueprint blueprint, Fluent command) {
    print(
        "Warning: SQLite does not support adding foreign keys to existing tables. Foreign keys must be defined during table creation.");
    return []; // Return empty list
  }

  /// Compile a drop table command.
  @override
  List<String> compileDrop(Blueprint blueprint, Fluent command) {
    return ['drop table ${wrapTable(blueprint)}'];
  }

  /// Compile a drop table (if exists) command.
  @override
  List<String> compileDropIfExists(Blueprint blueprint, Fluent command) {
    return ['drop table if exists ${wrapTable(blueprint)}'];
  }

  /// Compile a drop column command.
  /// SQLite support for DROP COLUMN was added in version 3.35.0 (2021-03-12).
  /// Older versions require recreating the table. This implementation assumes modern SQLite.
  @override
  List<String> compileDropColumn(Blueprint blueprint, Fluent command) {
    print(
        "Warning: Dropping columns in SQLite might not work on versions older than 3.35.0.");
    final table = wrapTable(blueprint);
    final columns =
        prefixArray('drop column', wrapArray(command['columns'] as List));
    return ['alter table $table ${columns.join(', ')}'];
  }

  /// Compile a drop primary key command.
  /// SQLite does NOT support dropping primary keys directly. Requires table recreation.
  @override
  List<String> compileDropPrimary(Blueprint blueprint, Fluent command) {
    print(
        "Warning: SQLite does not support dropping primary keys directly. Table recreation is required.");
    return []; // Cannot be done with simple SQL
  }

  /// Compile a drop unique key command (drops the underlying index).
  @override
  List<String> compileDropUnique(Blueprint blueprint, Fluent command) {
    // Dropping a unique constraint means dropping the corresponding unique index
    final indexName = wrap(command['index']);
    return ['drop index if exists $indexName']; // Use IF EXISTS for safety
  }

  /// Compile a drop index command.
  @override
  List<String> compileDropIndex(Blueprint blueprint, Fluent command) {
    final indexName = wrap(command['index']);
    return ['drop index if exists $indexName'];
  }

  /// Compile a drop foreign key command.
  /// SQLite does NOT support dropping foreign keys directly. Requires table recreation.
  @override
  List<String> compileDropForeign(Blueprint blueprint, Fluent command) {
    print(
        "Warning: SQLite does not support dropping foreign keys directly. Table recreation is required.");
    return [];
  }

  /// Compile a drop spatial index command.
  /// Requires specific extension handling (e.g., SpatiaLite).
  @override
  List<String> compileDropSpatialIndex(Blueprint blueprint, Fluent command) {
    throw UnimplementedError(
        "Dropping spatial indexes requires specific extension (e.g., SpatiaLite) handling.");
    // Example (if SpatiaLite was assumed):
    // final indexName = wrap(command['index']);
    // return ["SELECT DisableSpatialIndex(...)"]; // Fictional example
  }

  /// Compile a rename table command (ALTER TABLE ... RENAME TO ...).
  @override
  List<String> compileRename(Blueprint blueprint, Fluent command) {
    final from = wrapTable(blueprint);
    final to = wrapTable(command['to'] as String);
    return ['alter table $from rename to $to'];
  }

  /// Compile a rename index command.
  /// SQLite does NOT support renaming indexes directly. Requires drop and recreate.
  @override
  List<String> compileRenameIndex(Blueprint blueprint, Fluent command) {
    print(
        "Warning: SQLite does not support renaming indexes directly. Drop and recreate the index.");
    return [];
  }

  /// Compile a rename column command (ALTER TABLE ... RENAME COLUMN ... TO ...).
  /// Supported from SQLite 3.25.0 (2018-09-15).
  @override
  List<String> compileRenameColumn(
      Blueprint blueprint, Fluent command, Connection connection) {
    print(
        "Warning: Renaming columns might not work on SQLite versions older than 3.25.0.");
    final table = wrapTable(blueprint);
    final from = wrap(command['from'] as String);
    final to = wrap(command['to'] as String);
    return ['alter table $table rename column $from to $to'];
  }

  /// Compile a change column command.
  /// SQLite has very limited ALTER TABLE capabilities. Changing type, constraints, etc.,
  /// usually requires recreating the table.
  @override
  List<String> compileChange(
      Blueprint blueprint, Fluent command, Connection connection) {
    print(
        "Warning: SQLite has limited support for changing column definitions. Complex changes require table recreation.");
    // Basic renaming is handled by compileRenameColumn. Other changes are generally not possible via ALTER TABLE.
    return [];
  }

  // --- Type Definitions for SQLite ---
  // SQLite uses type affinity. These map to common affinities.

  @override
  String typeChar(Fluent column) => 'varchar'; // Maps to TEXT affinity
  @override
  String typeString(Fluent column) => 'varchar'; // Maps to TEXT affinity
  @override
  String typeText(Fluent column) => 'text'; // Maps to TEXT affinity
  @override
  String typeMediumText(Fluent column) => 'text';
  @override
  String typeLongText(Fluent column) => 'text';

  @override
  String typeInteger(Fluent column) =>
      'integer'; // Maps to INTEGER affinity (special for autoincrement)
  @override
  String typeBigInteger(Fluent column) => 'integer'; // Maps to INTEGER affinity
  @override
  String typeMediumInteger(Fluent column) => 'integer';
  @override
  String typeTinyInteger(Fluent column) => 'integer';
  @override
  String typeSmallInteger(Fluent column) => 'integer';

  @override
  String typeFloat(Fluent column) => 'float'; // Maps to REAL affinity
  @override
  String typeDouble(Fluent column) => 'float'; // Maps to REAL affinity
  @override
  String typeDecimal(Fluent column) => 'numeric'; // Maps to NUMERIC affinity
  @override
  String typeUnsignedDecimal(Fluent column) =>
      typeDecimal(column); // No unsigned in SQLite

  @override
  String typeBoolean(Fluent column) =>
      'boolean'; // Maps to NUMERIC affinity (stores 0 or 1)

  @override
  String typeEnum(Fluent column) {
    // Emulated with TEXT and CHECK constraint
    print(
        "Warning: SQLite does not have a native ENUM type. Emulating with TEXT and CHECK constraint.");
    final allowed = (column['allowed'] as List)
        .map((e) => "'${e.toString().replaceAll("'", "''")}'")
        .join(',');
    return 'text check (${wrap(column['name'])} in ($allowed))';
  }

  @override
  String typeJson(Fluent column) => 'text'; // Store JSON as TEXT
  @override
  String typeJsonb(Fluent column) => 'text'; // Store JSON as TEXT

  @override
  String typeDate(Fluent column) =>
      'date'; // Store as TEXT (ISO8601) or REAL (Julian day) or INTEGER (Unix time) - TEXT is common
  @override
  String typeDateTime(Fluent column) => 'datetime'; // Store as TEXT
  @override
  String typeDateTimeTz(Fluent column) =>
      'datetime'; // Store as TEXT, lose timezone info
  @override
  String typeTime(Fluent column) => 'time'; // Store as TEXT
  @override
  String typeTimeTz(Fluent column) =>
      'time'; // Store as TEXT, lose timezone info
  @override
  String typeTimestamp(Fluent column) => 'datetime'; // Store as TEXT
  @override
  String typeTimestampTz(Fluent column) =>
      'datetime'; // Store as TEXT, lose timezone info
  @override
  String typeYear(Fluent column) {
    print("Warning: SQLite has no YEAR type. Using INTEGER.");
    return 'integer';
  } // Store as INTEGER

  @override
  String typeBinary(Fluent column) => 'blob'; // Maps to BLOB affinity
  @override
  String typeUuid(Fluent column) => 'varchar(36)'; // Store as TEXT

  // --- GIS Types are not standard SQLite, require SpatiaLite ---
  @override
  String typeGeometry(Fluent column) => _throwSpatialiteRequired();
  @override
  String typePoint(Fluent column) => _throwSpatialiteRequired();
  @override
  String typeLineString(Fluent column) => _throwSpatialiteRequired();
  @override
  String typePolygon(Fluent column) => _throwSpatialiteRequired();
  @override
  String typeGeometryCollection(Fluent column) => _throwSpatialiteRequired();
  @override
  String typeMultiPoint(Fluent column) => _throwSpatialiteRequired();
  @override
  String typeMultiLineString(Fluent column) => _throwSpatialiteRequired();
  @override
  String typeMultiPolygon(Fluent column) => _throwSpatialiteRequired();

  String _throwSpatialiteRequired() {
    throw UnsupportedError(
        "Spatial types require the SpatiaLite extension for SQLite.");
  }

  // --- Modifier Implementations for SQLite ---

  /// Modificador para NULL/NOT NULL.
  @override
  @protected
  String? modifyNullable(Blueprint blueprint, Fluent column) {
    // SQLite defaults to NULL if not specified, unless it's PRIMARY KEY.
    // The autoIncrement logic handles PRIMARY KEY.
    if (column.attributes.containsKey('nullable')) {
      return column['nullable'] == true ? ' null' : ' not null';
    }
    // Don't add 'not null' by default unless it's an auto-incrementing PK
    if (column['autoIncrement'] == true && column['type'] == 'integer') {
      return ' not null';
    }
    return null; // Default is NULL
  }

  /// Modificador para valor DEFAULT.
  @override
  @protected
  String? modifyDefault(Blueprint blueprint, Fluent column) {
    if (column.attributes.containsKey('default')) {
      // Use the overridden getDefaultValue for SQLite formatting
      return ' default ${getDefaultValue(column['default'])}';
    }
    return null;
  }

  /// Modificador para AUTOINCREMENT.
  /// Note: In SQLite, this MUST be combined with 'INTEGER PRIMARY KEY'.
  @override
  @protected
  String? modifyIncrementing(Blueprint blueprint, Fluent column) {
    // Only applies to 'integer' type and implies PRIMARY KEY
    if (column['type'] == 'integer' && column['autoIncrement'] == true) {
      return ' primary key autoincrement';
    }
    return null;
  }

  // --- Modifiers Not Supported by SQLite ---
  @override
  @protected
  String? modifyUnsigned(Blueprint blueprint, Fluent column) => null;
  @override
  @protected
  String? modifyComment(Blueprint blueprint, Fluent column) => null;
  @override
  @protected
  String? modifyFirst(Blueprint blueprint, Fluent column) => null;
  @override
  @protected
  String? modifyAfter(Blueprint blueprint, Fluent column) => null;
  @override
  @protected
  String? modifyStoredAs(Blueprint blueprint, Fluent column) =>
      null; // Check SQLite version for GENERATED support
  @override
  @protected
  String? modifyVirtualAs(Blueprint blueprint, Fluent column) =>
      null; // Check SQLite version for GENERATED support
  @override
  @protected
  String? modifyCharset(Blueprint blueprint, Fluent column) => null;
  @override
  @protected
  String? modifyCollate(Blueprint blueprint, Fluent column) {
    // COLLATE can be used in SQLite, but usually per-expression or table definition
    if (column['collation'] != null) {
      // Quote collation name? Usually not needed for standard ones (BINARY, NOCASE, RTRIM)
      return ' collate ${column['collation']}';
    }
    return null;
  }

  @override
  @protected
  String? modifySrid(Blueprint blueprint, Fluent column) =>
      null; // Requires SpatiaLite

  // --- Overrides for Wrapping and Default Values ---

  /// Wrap a single string in keyword identifiers (double quotes for SQLite).
  @override
  String wrapValue(String value) {
    if (value == '*') return value;
    // SQLite uses double quotes for identifiers, escape internal double quotes
    return '"${value.replaceAll('"', '""')}"';
  }

  /// Format the default value for SQLite.
  @override
  @protected
  String getDefaultValue(dynamic value) {
    if (value is QueryExpression) return value.getValue().toString();
    if (value is bool) return value ? '1' : '0'; // SQLite uses 1/0 for booleans
    if (value == null) return 'NULL';
    if (value is String)
      return "'${value.replaceAll("'", "''")}'"; // Single quotes for strings
    return value.toString(); // Numbers
  }

  // --- Foreign Key Constraint Toggling (Not supported by SQLite) ---
  @override
  List<String> compileEnableForeignKeyConstraints() {
    print(
        "Warning: SQLite uses 'PRAGMA foreign_keys = ON;' (per connection), not compiled DDL.");
    return [];
  }

  @override
  List<String> compileDisableForeignKeyConstraints() {
    print(
        "Warning: SQLite uses 'PRAGMA foreign_keys = OFF;' (per connection), not compiled DDL.");
    return [];
  }
}
