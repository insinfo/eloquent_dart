import 'package:eloquent/eloquent.dart';
import 'package:meta/meta.dart';

/// Schema Grammar specific to SQL Server (T-SQL).
/// Translates Blueprint commands into T-SQL DDL.
class SchemaSqlServerGrammar extends SchemaGrammar {
  /// Column modifiers supported by SQL Server in ALTER/CREATE TABLE.
  @override
  final List<String> modifiers = const [
    'Collate',
    'Nullable',
    'Default',
    'Incrementing', // Handled as IDENTITY property
    // 'Comment', // Handled via extended properties (sp_addextendedproperty) - Cannot be inline
    // 'VirtualAs', // AS (...)
    // 'StoredAs', // AS (...) PERSISTED
    // Not Supported: Unsigned, Charset, After, First, Srid (part of type)
  ];

  /// Blueprint types that map to SQL Server types supporting IDENTITY.
  @override
  final List<String> serials = const [
    'tinyInteger',
    'smallInteger',
    'integer',
    'bigInteger'
  ];

  SchemaSqlServerGrammar() : super();

  /// Overrides initialization for SQL Server specific modifiers.
  @override
  @protected
  Map<String, Function(Blueprint, Fluent)> initializeModifierCompilers() {
    return {
      'Collate': (b, c) => modifyCollate(b, c),
      'Nullable': (b, c) => modifyNullable(b, c),
      'Default': (b, c) => modifyDefault(b, c),
      'Incrementing': (b, c) => modifyIncrementing(b, c),
      // Modifiers returning null or throwing:
      'Comment': (b, c) => modifyComment(b, c),
      'VirtualAs': (b, c) =>
          modifyVirtualAs(b, c), // Requires separate handling
      'StoredAs': (b, c) => modifyStoredAs(b, c), // Requires separate handling
      'Unsigned': (b, c) => modifyUnsigned(b, c),
      'Charset': (b, c) => modifyCharset(b, c),
      'After': (b, c) => modifyAfter(b, c),
      'First': (b, c) => modifyFirst(b, c),
      'Srid': (b, c) => modifySrid(b, c),
    };
  }

  /// Compile the query to determine if a table exists.
  @override
  String compileTableExists() {
    // Uses sys.objects, generally preferred over information_schema in SQL Server
    return "select * from sys.objects where object_id = object_id(?) and type = 'U'";
    // Alternative using INFORMATION_SCHEMA:
    // return "select * from information_schema.tables where table_schema = ? and table_name = ? and table_type = 'BASE TABLE'";
  }

  /// Compile the query to determine the list of columns.
  @override
  String compileColumnExists(String table) {
    // Uses information_schema for better compatibility across versions/editions
    return "select column_name from information_schema.columns where table_catalog = DB_NAME() and table_schema = ? and table_name = ?";
    // Alternative using sys.columns:
    // return "select col.name from sys.columns col join sys.objects obj on col.object_id = obj.object_id join sys.schemas sc on obj.schema_id = sc.schema_id where obj.object_id = object_id(?) and obj.type = 'U'";
  }

  /// Compile a create table command.
  @override
  List<String> compileCreate(
      Blueprint blueprint, Fluent command, Connection connection) {
    // Use the base implementation which calls getColumns, wrapTable etc.
    // SQL Server doesn't typically include constraints like PK/FK inline here.
    final sql = compileCreateTable(blueprint, command, connection);

    // Comments need separate execution (sp_addextendedproperty) after table creation.
    // Collect comments here if needed, but don't include in CREATE TABLE DDL.
    final List<String> commentStatements = _compileComments(blueprint);

    return [sql, ...commentStatements];
  }

  /// Compile alter table commands for adding columns.
  @override
  List<String> compileAdd(Blueprint blueprint, Fluent command) {
    final table = wrapTable(blueprint);
    // `getColumns` creates "column type [modifier]" strings
    final columns = getColumns(blueprint);
    if (columns.isEmpty) return [];

    final List<String> statements = [];
    // SQL Server generally prefers adding columns one by one or grouped
    statements.add('alter table $table add ${columns.join(', ')}');

    // Add comments as separate statements if needed
    statements.addAll(_compileComments(blueprint, onlyAdded: true));

    return statements;
  }

  /// Helper to compile COMMENT statements (using extended properties).
  List<String> _compileComments(Blueprint blueprint, {bool onlyAdded = false}) {
    final List<String> statements = [];
    // Seleciona as colunas apropriadas (adicionadas ou todas)
    final columnsToComment =
        (onlyAdded ? blueprint.getAddedColumns() : blueprint.getColumns())
            .whereType<Fluent>(); // Garante que são Fluent

    // REMOVIDO: Lógica para comentário da tabela
    // final String? tableComment = blueprint.getOption('comment'); // <--- Linha Removida
    // if(tableComment != null && tableComment.isNotEmpty) {
    //    statements.add(_compileAddTableComment(blueprint, tableComment));
    // }

    // Compila comentários das colunas que possuem o atributo 'comment'
    for (final column in columnsToComment) {
      final String? columnComment =
          column['comment']; // Acessa o atributo do Fluent da coluna
      if (columnComment != null && columnComment.isNotEmpty) {
        statements
            .add(_compileAddColumnComment(blueprint, column, columnComment));
      }
    }
    return statements;
  }

  /// Compile adding/updating an extended property for table comment.
  String compileAddTableComment(Blueprint blueprint, String comment) {
    final table = blueprint.getTable(); // Unquoted name for procedure
    final escapedComment = getDefaultValue(comment); // Escapes quotes
    final schema = 'dbo'; // TODO: Get actual schema if not default

    // Check if property exists, update if so, add if not
    return """
      IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE major_id = OBJECT_ID('${schema}.${table}') AND name = N'MS_Description' AND minor_id = 0)
          EXEC sp_updateextendedproperty N'MS_Description', $escapedComment, N'SCHEMA', N'$schema', N'TABLE', N'$table';
      ELSE
          EXEC sp_addextendedproperty N'MS_Description', $escapedComment, N'SCHEMA', N'$schema', N'TABLE', N'$table';
      """;
  }

  /// Compile adding/updating an extended property for column comment.
  String _compileAddColumnComment(
      Blueprint blueprint, Fluent column, String comment) {
    final table = blueprint.getTable();
    final columnName = column['name'] as String;
    final escapedComment = getDefaultValue(comment);
    final schema = 'dbo'; // TODO: Get actual schema

    return """
       IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE major_id = OBJECT_ID('${schema}.${table}') AND name = N'MS_Description' AND minor_id = COLUMNPROPERTY(OBJECT_ID('${schema}.${table}'), '$columnName', 'ColumnId'))
           EXEC sp_updateextendedproperty N'MS_Description', $escapedComment, N'SCHEMA', N'$schema', N'TABLE', N'$table', N'COLUMN', N'$columnName';
       ELSE
           EXEC sp_addextendedproperty N'MS_Description', $escapedComment, N'SCHEMA', N'$schema', N'TABLE', N'$table', N'COLUMN', N'$columnName';
       """;
  }

  /// Compile a primary key command (ALTER TABLE ... ADD CONSTRAINT ... PRIMARY KEY).
  @override
  List<String> compilePrimary(Blueprint blueprint, Fluent command) {
    final columns = columnize(command['columns'] as List);
    final indexName = wrap(
        command['index'] ?? 'PK_${blueprint.getTable()}'); // Default PK name
    return [
      'alter table ${wrapTable(blueprint)} add constraint $indexName primary key ($columns)'
    ];
  }

  /// Compile a unique key command (ALTER TABLE ... ADD CONSTRAINT ... UNIQUE).
  @override
  List<String> compileUnique(Blueprint blueprint, Fluent command) {
    final columns = columnize(command['columns'] as List);
    final indexName = wrap(command['index']); // Name is required
    return [
      'alter table ${wrapTable(blueprint)} add constraint $indexName unique ($columns)'
    ];
  }

  /// Compile a plain index key command (CREATE INDEX ... ON ...).
  @override
  List<String> compileIndex(Blueprint blueprint, Fluent command) {
    final indexName = wrap(command['index']);
    final table = wrapTable(blueprint);
    final columns = columnize(command['columns'] as List);
    // SQL Server syntax: CREATE INDEX index_name ON table_name (column1, column2, ...);
    return ['create index $indexName on $table ($columns)'];
  }

  /// Compile a spatial index command (CREATE SPATIAL INDEX ... ON ...).
  @override
  List<String> compileSpatialIndex(Blueprint blueprint, Fluent command) {
    final indexName = wrap(command['index']);
    final table = wrapTable(blueprint);
    // Spatial index usually applies to a single geometry/geography column
    if ((command['columns'] as List).length != 1) {
      throw ArgumentError(
          "Spatial indexes must be created on a single column in SQL Server.");
    }
    final column = wrap(command['columns'][0]);
    // Basic syntax, might need USING or other options depending on specifics
    return ['create spatial index $indexName on $table ($column)'];
  }

  /// Compile a foreign key command (ALTER TABLE ... ADD CONSTRAINT ... FOREIGN KEY).
  @override
  List<String> compileForeign(Blueprint blueprint, Fluent command) {
    // Re-use base implementation as it's standard SQL
    return super.compileForeign(blueprint, command);
  }

  /// Compile a drop table command.
  @override
  List<String> compileDrop(Blueprint blueprint, Fluent command) {
    return ['drop table ${wrapTable(blueprint)}'];
  }

  /// Compile a drop table (if exists) command.
  @override
  List<String> compileDropIfExists(Blueprint blueprint, Fluent command) {
    // Modern SQL Server syntax
    return ['drop table if exists ${wrapTable(blueprint)}'];
  }

  /// Compile a drop column command (ALTER TABLE ... DROP COLUMN ...).
  @override
  List<String> compileDropColumn(Blueprint blueprint, Fluent command) {
    final table = wrapTable(blueprint);
    // SQL Server drops columns one by one or comma-separated
    final columns =
        prefixArray('drop column', wrapArray(command['columns'] as List));
    return ['alter table $table ${columns.join(', ')}'];
  }

  /// Compile a drop primary key command (ALTER TABLE ... DROP CONSTRAINT ...).
  @override
  List<String> compileDropPrimary(Blueprint blueprint, Fluent command) {
    // SQL Server requires the constraint name. Assume a default if not provided.
    final indexName = wrap(command['index'] ?? 'PK_${blueprint.getTable()}');
    return ['alter table ${wrapTable(blueprint)} drop constraint $indexName'];
  }

  /// Compile a drop unique key command (ALTER TABLE ... DROP CONSTRAINT ...).
  @override
  List<String> compileDropUnique(Blueprint blueprint, Fluent command) {
    final indexName = wrap(command['index']); // Constraint name is required
    return ['alter table ${wrapTable(blueprint)} drop constraint $indexName'];
  }

  /// Compile a drop index command (DROP INDEX ... ON ...).
  @override
  List<String> compileDropIndex(Blueprint blueprint, Fluent command) {
    final indexName = wrap(command['index']);
    final table = wrapTable(blueprint);
    // SQL Server syntax: DROP INDEX index_name ON table_name;
    return ['drop index $indexName on $table'];
  }

  /// Compile a drop spatial index command (DROP INDEX ... ON ...).
  @override
  List<String> compileDropSpatialIndex(Blueprint blueprint, Fluent command) {
    // Spatial indexes are dropped like regular indexes
    return compileDropIndex(blueprint, command);
  }

  /// Compile a drop foreign key command (ALTER TABLE ... DROP CONSTRAINT ...).
  @override
  List<String> compileDropForeign(Blueprint blueprint, Fluent command) {
    final indexName = wrap(command['index']); // Constraint name is required
    return ['alter table ${wrapTable(blueprint)} drop constraint $indexName'];
  }

  /// Compile a rename table command (sp_rename).
  @override
  List<String> compileRename(Blueprint blueprint, Fluent command) {
    final from = blueprint.getTable(); // sp_rename often prefers unquoted names
    final to = command['to'] as String;
    // Use sp_rename stored procedure
    return ["exec sp_rename N'$from', N'$to'"];
  }

  /// Compile a rename index command (sp_rename).
  @override
  List<String> compileRenameIndex(Blueprint blueprint, Fluent command) {
    final table = blueprint.getTable();
    final from = command['from'] as String;
    final to = command['to'] as String;
    // Use sp_rename: 'schema.table.old_index_name', 'new_index_name', 'INDEX'
    // Assuming default schema 'dbo' for simplicity
    return ["exec sp_rename N'dbo.$table.$from', N'$to', N'INDEX'"];
  }

  /// Compile a rename column command (sp_rename).
  @override
  List<String> compileRenameColumn(
      Blueprint blueprint, Fluent command, Connection connection) {
    final table = blueprint.getTable();
    final from = command['from'] as String;
    final to = command['to'] as String;
    // Use sp_rename: 'schema.table.old_column_name', 'new_column_name', 'COLUMN'
    return ["exec sp_rename N'dbo.$table.$from', N'$to', N'COLUMN'"];
  }

  /// Compile a change column command (ALTER TABLE ... ALTER COLUMN ...).
  /// WARNING: Simplified. SQL Server often requires dropping constraints/defaults first.
  @override
  List<String> compileChange(
      Blueprint blueprint, Fluent command, Connection connection) {
    print(
        "Warning: compileChange for SQL Server is simplified. Complex changes (like IDENTITY, defaults, constraints) might require manual steps or table recreation.");
    final table = wrapTable(blueprint);
    final List<String> statements = [];

    for (final column in blueprint.getChangedColumns()) {
      final colName = wrap(column);
      // Get the new full definition (type + nullable)
      final String? typeSql = getType(column);
      final String? nullSql =
          modifyNullable(blueprint, column); // Get NULL or NOT NULL

      // Basic ALTER COLUMN for type and nullability
      statements.add(
          'alter table $table alter column $colName $typeSql${nullSql ?? ""}');

      // Handling DEFAULT constraint is tricky, typically requires DROP and ADD
      if (column.attributes.containsKey('default')) {
        final String? defaultSql = modifyDefault(blueprint, column);
        final String constraintName =
            "DF_${blueprint.getTable()}_${column['name']}"; // Assumed default constraint name

        // Add drop existing default constraint (if it exists - requires knowing the name)
        statements.add(
            "if exists (select * from sys.default_constraints where name = '$constraintName') alter table $table drop constraint $constraintName");

        // Add new default constraint
        if (defaultSql != null && defaultSql.isNotEmpty) {
          statements.add(
              'alter table $table add constraint $constraintName$defaultSql for $colName');
        }
      }
      // Collation might also need ALTER COLUMN ... COLLATE
      final String? collateSql = modifyCollate(blueprint, column);
      if (collateSql != null && collateSql.isNotEmpty) {
        statements.add(
            'alter table $table alter column $colName $typeSql$collateSql${nullSql ?? ""}');
      }

      // Comments require sp_addextendedproperty (not handled here inline)
      modifyComment(blueprint, column);
    }

    return statements;
  }

  // --- Type Definitions for SQL Server ---

  @override
  String typeChar(Fluent column) => 'nchar(${column['length']})';
  @override
  String typeString(Fluent column) => 'nvarchar(${column['length']})';
  @override
  String typeText(Fluent column) => 'nvarchar(max)';
  @override
  String typeMediumText(Fluent column) => 'nvarchar(max)';
  @override
  String typeLongText(Fluent column) => 'nvarchar(max)';

  @override
  String typeInteger(Fluent column) => 'int';
  @override
  String typeBigInteger(Fluent column) => 'bigint';
  @override
  String typeMediumInteger(Fluent column) {
    print("Warning: SQL Server does not have MEDIUMINT. Using INT.");
    return 'int';
  } // Map to int

  @override
  String typeSmallInteger(Fluent column) => 'smallint';
  @override
  String typeTinyInteger(Fluent column) => 'tinyint';

  @override
  String typeFloat(Fluent column) =>
      'float'; // SQL Server float is 53 precision (like double)
  @override
  String typeDouble(Fluent column) => 'float'; // Map double to float
  @override
  String typeDecimal(Fluent column) =>
      'decimal(${column['total']}, ${column['places']})';
  @override
  String typeUnsignedDecimal(Fluent column) {
    print("Warning: SQL Server does not support UNSIGNED columns.");
    return typeDecimal(column);
  }

  @override
  String typeBoolean(Fluent column) => 'bit'; // SQL Server uses bit
  @override
  String typeEnum(Fluent column) {
    print(
        "Warning: SQL Server does not have ENUM. Emulating with NVARCHAR and CHECK constraint.");
    final allowed = (column['allowed'] as List)
        .map((e) => "'${e.toString().replaceAll("'", "''")}'")
        .join(',');
    // Use nvarchar(255) for enum emulation
    return 'nvarchar(255) check (${wrap(column['name'])} in ($allowed))';
  }

  @override
  String typeJson(Fluent column) => 'nvarchar(max)'; // Store JSON as text
  @override
  String typeJsonb(Fluent column) => 'nvarchar(max)'; // Store JSON as text

  @override
  String typeDate(Fluent column) => 'date';
  @override
  String typeDateTime(Fluent column) =>
      'datetime2(${column['precision'] ?? 7})'; // Use datetime2 for better precision
  @override
  String typeDateTimeTz(Fluent column) =>
      'datetimeoffset(${column['precision'] ?? 7})';
  @override
  String typeTime(Fluent column) => 'time(${column['precision'] ?? 7})';
  @override
  String typeTimeTz(Fluent column) {
    print("Warning: SQL Server does not have TIME WITH TIMEZONE. Using TIME.");
    return typeTime(column);
  } // No direct equivalent

  @override
  String typeTimestamp(Fluent column) =>
      'datetime2(${column['precision'] ?? 7})'; // Use datetime2
  @override
  String typeTimestampTz(Fluent column) =>
      'datetimeoffset(${column['precision'] ?? 7})';
  @override
  String typeYear(Fluent column) {
    print("Warning: SQL Server does not have YEAR. Using SMALLINT.");
    return 'smallint';
  } // Map to smallint

  @override
  String typeBinary(Fluent column) =>
      'varbinary(max)'; // Or binary(n), image (deprecated)
  @override
  String typeUuid(Fluent column) =>
      'uniqueidentifier'; // SQL Server native UUID type

  @override
  String typeIpAddress(Fluent column) {
    print("Warning: SQL Server has no IPADDRESS. Using NVARCHAR(45).");
    return 'nvarchar(45)';
  }

  @override
  String typeMacAddress(Fluent column) {
    print("Warning: SQL Server has no MACADDRESS. Using NVARCHAR(17).");
    return 'nvarchar(17)';
  }

  // GIS Types (SQL Server Spatial)
  @override
  String typeGeometry(Fluent column) => 'geometry';
  @override
  String typePoint(Fluent column) =>
      'geometry'; // Specific type often not used in definition
  @override
  String typeLineString(Fluent column) => 'geometry';
  @override
  String typePolygon(Fluent column) => 'geometry';
  @override
  String typeGeometryCollection(Fluent column) => 'geometry';
  @override
  String typeMultiPoint(Fluent column) => 'geometry';
  @override
  String typeMultiLineString(Fluent column) => 'geometry';
  @override
  String typeMultiPolygon(Fluent column) => 'geometry';

  // --- Modifier Implementations for SQL Server ---

  /// Modificador para NULL/NOT NULL.
  @override
  @protected
  String? modifyNullable(Blueprint blueprint, Fluent column) {
    // SQL Server default is NULL unless it's an IDENTITY or PRIMARY KEY column
    if (column['autoIncrement'] == true && serials.contains(column['type'])) {
      return ' not null'; // IDENTITY columns must be NOT NULL
    }
    // Check explicit setting
    if (column.attributes.containsKey('nullable')) {
      return column['nullable'] == true ? ' null' : ' not null';
    }
    // Default is NULL
    return ' null';
  }

  /// Modificador para valor DEFAULT (requires named constraint).
  @override
  @protected
  String? modifyDefault(Blueprint blueprint, Fluent column) {
    if (column.attributes.containsKey('default')) {
      // SQL Server requires named default constraints, typically added separately
      // `add constraint DF_table_col default value for col`
      // This modifier can only return the value part for inline use (less common)
      print(
          "Warning: SQL Server DEFAULT constraints are typically added separately with names. Inline default may not always work as expected with ALTER statements.");
      return ' default ${getDefaultValue(column['default'])}';
    }
    return null;
  }

  /// Modificador para IDENTITY (AUTO_INCREMENT).
  @override
  @protected
  String? modifyIncrementing(Blueprint blueprint, Fluent column) {
    if (serials.contains(column['type']) && column['autoIncrement'] == true) {
      // IDENTITY(seed, increment) - default is (1,1)
      return ' identity(1,1)'; // Cannot be added via ALTER COLUMN
    }
    return null;
  }

  /// Modificador para COLLATE.
  @override
  @protected
  String? modifyCollate(Blueprint blueprint, Fluent column) {
    if (column['collation'] != null) {
      // Use wrapValue (brackets) if collation name needs quoting
      return ' collate ${wrapValue(column['collation'] as String)}';
    }
    return null;
  }

  /// Modificador para COMMENT (Requires sp_addextendedproperty).
  @override
  @protected
  String? modifyComment(Blueprint blueprint, Fluent column) {
    if (column['comment'] != null) {
      print(
          "Info: Column comment for '${column['name']}' requires separate sp_addextendedproperty execution.");
    }
    return null; // Cannot be applied inline
  }

  // --- Unsupported Modifiers for SQL Server ---
  @override
  @protected
  String? modifyUnsigned(Blueprint blueprint, Fluent column) {
    print("Warning: SQL Server does not support UNSIGNED columns.");
    return null;
  }

  @override
  @protected
  String? modifyCharset(Blueprint blueprint, Fluent column) {
    print("Warning: SQL Server handles charsets via collation.");
    return null;
  }

  @override
  @protected
  String? modifyFirst(Blueprint blueprint, Fluent column) {
    print("Warning: SQL Server does not support FIRST column modifier.");
    return null;
  }

  @override
  @protected
  String? modifyAfter(Blueprint blueprint, Fluent column) {
    print("Warning: SQL Server does not support AFTER column modifier.");
    return null;
  }

  @override
  @protected
  String? modifyStoredAs(Blueprint blueprint, Fluent column) {
    if (column['storedAs'] != null) {
      return ' as (${_resolveExpression(column['storedAs'])}) persisted';
    }
    return null;
  }

  @override
  @protected
  String? modifyVirtualAs(Blueprint blueprint, Fluent column) {
    if (column['virtualAs'] != null) {
      return ' as (${_resolveExpression(column['virtualAs'])})';
    }
    return null;
  }

  @override
  @protected
  String? modifySrid(Blueprint blueprint, Fluent column) {
    if (column['srid'] != null) {
      print(
          "Info: SRID for SQL Server spatial types is usually part of the data, not the column definition.");
    }
    return null;
  }

  /// Resolve potential QueryExpression for generated columns.
  @protected
  String _resolveExpression(dynamic expression) {
    return expression is QueryExpression
        ? expression.getValue().toString()
        : expression.toString();
  }

  // --- Overrides for Wrapping and Default Values ---

  /// Wrap a single string in keyword identifiers (brackets for SQL Server).
  @override
  String wrapValue(String value) {
    if (value == '*') return value;
    // Escape closing bracket by doubling: [My]]Column] -> "My]Column"
    return '[${value.replaceAll(']', ']]')}]';
  }

  /// Format the default value for SQL Server.
  @override
  @protected
  String getDefaultValue(dynamic value) {
    if (value is QueryExpression) {
      // Handle common SQL Server functions
      final exprValue = value.getValue().toString().toUpperCase();
      if (exprValue == 'CURRENT_TIMESTAMP' || exprValue == 'GETDATE()')
        return 'GETDATE()';
      if (exprValue == 'NEWID()') return 'NEWID()';
      return exprValue; // Return other expressions as-is
    }
    if (value is bool) return value ? '1' : '0'; // SQL Server uses 1/0 for bit
    if (value == null) return 'NULL';
    if (value is String)
      return "'${value.replaceAll("'", "''")}'"; // Single quotes, escape internal single quotes
    return value.toString(); // Numbers
  }

  // --- Foreign Key Constraint Toggling ---
  @override
  List<String> compileEnableForeignKeyConstraints() {
    // Enables ALL foreign keys on ALL tables - use with caution
    return [
      'EXEC sp_msforeachtable @command1="ALTER TABLE ? WITH CHECK CHECK CONSTRAINT ALL";'
    ];
  }

  @override
  List<String> compileDisableForeignKeyConstraints() {
    // Disables ALL foreign keys on ALL tables - use with caution
    return [
      'EXEC sp_msforeachtable @command1="ALTER TABLE ? NOCHECK CONSTRAINT ALL";'
    ];
  }
}
