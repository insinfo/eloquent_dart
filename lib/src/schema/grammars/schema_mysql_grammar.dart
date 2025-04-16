//schema_mysql_grammar.dart
import 'package:eloquent/eloquent.dart';
import 'package:meta/meta.dart'; 

/// Schema Grammar specific to MySQL.
/// Translates Blueprint commands into MySQL DDL SQL.
class SchemaMySqlGrammar extends SchemaGrammar {
  /// The possible column modifiers specific to MySQL.
  /// Note: Incrementing is handled within type definition or modifyIncrement.
  @override
  final List<String> modifiers = const [
    'Unsigned',
    'Charset',
    'Collate',
    'VirtualAs',
    'StoredAs',
    'Nullable',
    'Default',
    'Increment', // Alias used in the map for 'Incrementing' logic
    'Comment',
    'After',
    'First',
    // 'Srid' is typically part of the GIS type, not a separate modifier in MySQL standard DDL
  ];

  /// The column types that can be auto-incrementing in MySQL.
  @override
  final List<String> serials = const [
    'bigInteger',
    'integer',
    'mediumInteger',
    'smallInteger',
    'tinyInteger'
  ];

  SchemaMySqlGrammar() : super();

  /// Overrides the initialization to map 'Increment' to the correct method.
  @override
  @protected
  Map<String, Function(Blueprint, Fluent)> initializeModifierCompilers() {
    // Get base compilers, then add/override MySQL specifics
    final Map<String, Function(Blueprint, Fluent)> compilers = {
      'Nullable': (b, c) => modifyNullable(b, c),
      'Default': (b, c) => modifyDefault(b, c),
      'Unsigned': (b, c) => modifyUnsigned(b, c),
      'Comment': (b, c) => modifyComment(b, c),
      'First': (b, c) => modifyFirst(b, c),
      'After': (b, c) => modifyAfter(b, c),
      'StoredAs': (b, c) => modifyStoredAs(b, c),
      'VirtualAs': (b, c) => modifyVirtualAs(b, c),
      // Map 'Increment' (from our adjusted modifiers list) to modifyIncrementing
      'Increment': (b, c) => modifyIncrementing(b, c),
      'Charset': (b, c) => modifyCharset(b, c),
      'Collate': (b, c) => modifyCollate(b, c),
      // Srid is not a standard MySQL modifier in ALTER/CREATE TABLE DDL
      // 'Srid': (b, c) => modifySrid(b, c), // Removed or return null
    };
    return compilers;
  }

  /// Compile the query to determine if a table exists.
  @override
  String compileTableExists() {
    // Uses information_schema, includes table_schema for accuracy
    return 'select 1 from information_schema.tables where table_schema = ? and table_name = ? limit 1';
  }

  /// Compile the query to determine the list of columns.
  @override
  String compileColumnExists(String table) {
    // Uses information_schema, includes table_schema
    return "select column_name from information_schema.columns where table_schema = ? and table_name = ?";
  }

  /// Compile a create table command.
  @override
  List<String> compileCreate(
      Blueprint blueprint, Fluent command, Connection connection) {
    // Base implementation handles column definitions
    String sql = compileCreateTable(blueprint, command, connection);
    // MySQL requires ENGINE, CHARSET, COLLATE after the columns
    sql = compileCreateEngine(sql, connection, blueprint);
    sql = _compileCreateEncoding(
        sql, connection, blueprint); // Use helper for charset/collation

    // Note: Fluent indexes (primary, unique, index defined on column)
    // are typically added via ALTER TABLE in Laravel's approach for MySQL,
    // handled by Blueprint.toSql calling the respective compile methods later.
    // Primary key for increments columns IS handled inline by modifyIncrementing.
    return [sql];
  }

  /// Append the engine specifications to a command.
  @override
  @protected
  String compileCreateEngine(
      String sql, Connection connection, Blueprint blueprint) {
    if (blueprint.tableEngine != null) {
      sql += ' engine = ${blueprint.tableEngine}';
    }
    return sql;
  }

  /// Append the character set and collation specifications to a command.

  @protected
  String _compileCreateEncoding(
      String sql, Connection connection, Blueprint blueprint) {
    // Usa a configuração específica da tabela OU a configuração da conexão como fallback.

    // O operador '??' é usado para fornecer um valor padrão se o da esquerda for null.
    String? charset = blueprint.tableCharset ??
        connection.getConfig('charset'); // Usa tableCharset
    if (charset != null && charset.isNotEmpty) {
      // Verifica se não é nulo ou vazio
      sql += ' default character set $charset';
    }

    String? collation = blueprint.tableCollation ??
        connection.getConfig('collation'); // Usa tableCollation
    if (collation != null && collation.isNotEmpty) {
      // Verifica se não é nulo ou vazio
      sql += ' collate $collation';
    }

    return sql;
  }

  /// Compile an add column command.
  @override
  List<String> compileAdd(Blueprint blueprint, Fluent command) {
    final table = wrapTable(blueprint);
    // getColumns generates the full 'column type modifiers' string for each column
    final columns = prefixArray('add', getColumns(blueprint));
    if (columns.isEmpty) return [];
    return ['alter table $table ${columns.join(', ')}'];
  }

  /// Compile a primary key command (MySQL: ALTER TABLE ... ADD PRIMARY KEY).
  @override
  List<String> compilePrimary(Blueprint blueprint, Fluent command) {
    // MySQL typically uses `ADD PRIMARY KEY (columns)` without explicit constraint name
    final columns = columnize(command['columns'] as List);
    return ['alter table ${wrapTable(blueprint)} add primary key ($columns)'];
  }

  /// Compile a unique key command (MySQL: ALTER TABLE ... ADD UNIQUE KEY).
  @override
  List<String> compileUnique(Blueprint blueprint, Fluent command) {
    return [_compileKey(blueprint, command, 'unique key')];
  }

  /// Compile a plain index key command (MySQL: ALTER TABLE ... ADD INDEX).
  @override
  List<String> compileIndex(Blueprint blueprint, Fluent command) {
    return [_compileKey(blueprint, command, 'index')];
  }

  /// Compile a spatial index key command (MySQL: ALTER TABLE ... ADD SPATIAL INDEX).
  @override
  List<String> compileSpatialIndex(Blueprint blueprint, Fluent command) {
    return [_compileKey(blueprint, command, 'spatial index')];
  }

  /// Compile an index creation command (helper for MySQL).
  @protected
  String _compileKey(Blueprint blueprint, Fluent command, String type) {
    final columns = columnize(command['columns'] as List);
    final table = wrapTable(blueprint);
    final indexName =
        wrap(command['index']); // Index name is required for unique/index

    return 'alter table $table add $type $indexName($columns)';
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

  /// Compile a drop column command (MySQL: ALTER TABLE ... DROP COLUMN ...).
  @override
  List<String> compileDropColumn(Blueprint blueprint, Fluent command) {
    final table = wrapTable(blueprint);
    // MySQL uses DROP COLUMN `column_name`
    final columns =
        prefixArray('drop column', wrapArray(command['columns'] as List));
    return ['alter table $table ${columns.join(', ')}'];
  }

  /// Compile a drop primary key command (MySQL: ALTER TABLE ... DROP PRIMARY KEY).
  @override
  List<String> compileDropPrimary(Blueprint blueprint, Fluent command) {
    return ['alter table ${wrapTable(blueprint)} drop primary key'];
  }

  /// Compile a drop unique key command (MySQL: ALTER TABLE ... DROP INDEX ...).
  @override
  List<String> compileDropUnique(Blueprint blueprint, Fluent command) {
    final indexName = wrap(command['index']);
    return ['alter table ${wrapTable(blueprint)} drop index $indexName'];
  }

  /// Compile a drop index command (MySQL: ALTER TABLE ... DROP INDEX ...).
  @override
  List<String> compileDropIndex(Blueprint blueprint, Fluent command) {
    final indexName = wrap(command['index']);
    return ['alter table ${wrapTable(blueprint)} drop index $indexName'];
  }

  /// Compile a drop foreign key command (MySQL: ALTER TABLE ... DROP FOREIGN KEY ...).
  @override
  List<String> compileDropForeign(Blueprint blueprint, Fluent command) {
    final indexName = wrap(command['index']); // Constraint name
    return ['alter table ${wrapTable(blueprint)} drop foreign key $indexName'];
  }

  /// Compile a drop spatial index command (MySQL: ALTER TABLE ... DROP INDEX ...).
  @override
  List<String> compileDropSpatialIndex(Blueprint blueprint, Fluent command) {
    // Spatial indexes are dropped like regular indexes in MySQL
    return compileDropIndex(blueprint, command);
  }

  /// Compile a rename table command (MySQL: RENAME TABLE ... TO ...).
  @override
  List<String> compileRename(Blueprint blueprint, Fluent command) {
    final from = wrapTable(blueprint);
    final to = wrapTable(command['to'] as String);
    return ['rename table $from to $to'];
  }

  /// Compile a rename index command (MySQL: ALTER TABLE ... RENAME INDEX ... TO ...).
  @override
  List<String> compileRenameIndex(Blueprint blueprint, Fluent command) {
    final table = wrapTable(blueprint);
    final from = wrap(command['from'] as String);
    final to = wrap(command['to'] as String);
    return ['alter table $table rename index $from to $to'];
  }

  /// Compile a rename column command (MySQL: ALTER TABLE ... CHANGE COLUMN ...).
  /// WARNING: Requires full column definition. This is a simplified version.
  @override
  List<String> compileRenameColumn(
      Blueprint blueprint, Fluent command, Connection connection) {
    print(
        "Warning: compileRenameColumn in MySQL requires the full current column definition. This implementation is simplified.");
    final table = wrapTable(blueprint);
    final from = wrap(command['from'] as String);
    final to = wrap(command['to'] as String);
    // Placeholder: You MUST fetch the current column definition from the database
    // using a SchemaManager or similar for this to be reliable.
    final String currentDefinition =
        'VARCHAR(255)'; // FIXME: Replace with actual definition lookup
    return ['alter table $table change column $from $to $currentDefinition'];
  }

  /// Compile a change column command (MySQL: ALTER TABLE ... MODIFY COLUMN ...).
  /// WARNING: Requires schema introspection (like Doctrine) for reliability. Stub implementation.
  @override
  List<String> compileChange(
      Blueprint blueprint, Fluent command, Connection connection) {
    print(
        "Warning: compileChange requires schema introspection for reliable operation. This implementation is a basic stub.");
    final table = wrapTable(blueprint);
    final List<String> changes = [];

    for (final column in blueprint.getChangedColumns()) {
      final colName = wrap(column);
      // Needs the FULL new definition including type and all modifiers
      final String? typeSql = getType(column);
      final String modifiersSql = addModifiers('', blueprint, column).trim();

      changes.add('modify column $colName $typeSql $modifiersSql');
    }

    if (changes.isEmpty) return [];
    return ['alter table $table ${changes.join(', ')}'];
  }

  // --- Type Definitions for MySQL ---
  // (Mostly inherited, override where MySQL differs significantly)

  @override
  String typeInteger(Fluent column) => 'int';
  @override
  String typeMediumInteger(Fluent column) => 'mediumint';
  @override
  String typeTinyInteger(Fluent column) => 'tinyint';
  @override
  String typeSmallInteger(Fluent column) => 'smallint';
  @override
  String typeBigInteger(Fluent column) => 'bigint';

  @override
  String typeBoolean(Fluent column) => 'tinyint(1)';

  @override
  String typeDouble(Fluent column) {
    // MySQL uses specific syntax for total/places with DOUBLE
    if (column['total'] != null && column['places'] != null) {
      return "double(${column['total']}, ${column['places']})";
    }
    return 'double';
  }

  @override
  String typeFloat(Fluent column) {
    // MySQL uses specific syntax for total/places with FLOAT
    if (column['total'] != null && column['places'] != null) {
      return "float(${column['total']}, ${column['places']})";
    }
    return 'float';
  }

  @override
  String typeDateTime(Fluent column) =>
      'datetime'; // Precision handled differently if needed
  @override
  String typeDateTimeTz(Fluent column) {
    print(
        "Warning: MySQL does not support DATETIME WITH TIMEZONE. Using DATETIME.");
    return 'datetime';
  }

  @override
  String typeTime(Fluent column) => 'time'; // Precision handled differently
  @override
  String typeTimeTz(Fluent column) {
    print("Warning: MySQL does not support TIME WITH TIMEZONE. Using TIME.");
    return 'time';
  }

  @override
  String typeTimestamp(Fluent column) {
    String type = 'timestamp';
    // MySQL TIMESTAMP default needs special handling via modifyDefault/modifyNullable
    return type;
  }

  @override
  String typeTimestampTz(Fluent column) {
    print(
        "Warning: MySQL does not support TIMESTAMP WITH TIMEZONE. Using TIMESTAMP.");
    return typeTimestamp(column);
  }

  @override
  String typeYear(Fluent column) => 'year'; // MySQL specific
  @override
  String typeBinary(Fluent column) => 'blob'; // Or other blob types
  @override
  String typeUuid(Fluent column) => 'char(36)';
  @override
  String typeIpAddress(Fluent column) => 'varchar(45)';
  @override
  String typeMacAddress(Fluent column) => 'varchar(17)';
  @override
  String typeJsonb(Fluent column) => 'json'; // MySQL uses JSON

  // --- MySQL Specific Modifier Implementations ---

  @override
  @protected
  String? modifyUnsigned(Blueprint blueprint, Fluent column) {
    if (column['unsigned'] == true) {
      return ' unsigned';
    }
    return null;
  }

  @override
  @protected
  String? modifyCharset(Blueprint blueprint, Fluent column) {
    if (column['charset'] != null) {
      return ' character set ${column['charset']}';
    }
    return null;
  }

  @override
  @protected
  String? modifyCollate(Blueprint blueprint, Fluent column) {
    if (column['collation'] != null) {
      // Use wrapValue which uses backticks for MySQL if collation name needs quoting
      return ' collate ${wrapValue(column['collation'] as String)}';
    }
    return null;
  }

  @override
  @protected
  String? modifyNullable(Blueprint blueprint, Fluent column) {
    // MySQL default is NOT NULL unless specified. Handle autoIncrement separately.
    if (column['autoIncrement'] == true && serials.contains(column['type'])) {
      return ' not null'; // Auto increment columns are implicitly not null
    }
    // Check explicit setting
    if (column.attributes.containsKey('nullable')) {
      return column['nullable'] == true ? ' null' : ' not null';
    }
    // Default to NOT NULL if 'nullable' key is absent
    return ' not null';
  }

  @override
  @protected
  String? modifyDefault(Blueprint blueprint, Fluent column) {
    if (column.attributes.containsKey('default')) {
      // Handle potential CURRENT_TIMESTAMP default for TIMESTAMP/DATETIME
      if ((column['type'] == 'timestamp' || column['type'] == 'datetime') &&
          (column['default'] is QueryExpression &&
              (column['default'] as QueryExpression)
                      .getValue()
                      .toString()
                      .toUpperCase() ==
                  'CURRENT_TIMESTAMP')) {
        return ' default CURRENT_TIMESTAMP';
      }
      // Use the overridden getDefaultValue for MySQL formatting
      return ' default ${getDefaultValue(column['default'])}';
    }
    return null;
  }

  /// Modificador para AUTO_INCREMENT (MySQL).
  /// Note: MySQL combina `auto_increment` com `primary key` frequentemente.
  /// Se `increments()` foi usado no Blueprint, `autoIncrement` será true.
  /// Se `primary()` também foi chamado para a mesma coluna, a gramática base
  /// pode tentar adicionar a PK novamente. A ordem de execução importa.
  /// Assumimos que se `autoIncrement` for true, ele definirá a PK.
  @override
  @protected
  String? modifyIncrementing(Blueprint blueprint, Fluent column) {
    if (serials.contains(column['type']) && column['autoIncrement'] == true) {
      return ' auto_increment'; // PRIMARY KEY é adicionado separadamente ou via `increments()`
    }
    return null;
  }

  @override
  @protected
  String? modifyFirst(Blueprint blueprint, Fluent column) {
    if (column['first'] == true) {
      return ' first';
    }
    return null;
  }

  @override
  @protected
  String? modifyAfter(Blueprint blueprint, Fluent column) {
    if (column['after'] != null) {
      return ' after ${wrap(column['after'])}';
    }
    return null;
  }

  @override
  @protected
  String? modifyComment(Blueprint blueprint, Fluent column) {
    if (column['comment'] != null) {
      final comment = column['comment'] as String;
      // Escape single quotes and backslashes for MySQL COMMENT
      final escapedComment =
          comment.replaceAll("\\", "\\\\").replaceAll("'", "\\'");
      return " comment '$escapedComment'";
    }
    return null;
  }

  @override
  @protected
  String? modifyVirtualAs(Blueprint blueprint, Fluent column) {
    if (column['virtualAs'] != null) {
      return ' as (${_resolveExpression(column['virtualAs'])}) virtual';
    }
    return null;
  }

  @override
  @protected
  String? modifyStoredAs(Blueprint blueprint, Fluent column) {
    if (column['storedAs'] != null) {
      return ' as (${_resolveExpression(column['storedAs'])}) stored';
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

  /// Wrap a single string in keyword identifiers (backticks for MySQL).
  @override
  String wrapValue(String value) {
    if (value == '*') return value;
    // Escape backticks within the identifier
    return '`${value.replaceAll('`', '``')}`';
  }

  /// Format the default value for MySQL.
  @override
  @protected
  String getDefaultValue(dynamic value) {
    if (value is QueryExpression) {
      return value.getValue().toString();
    }
    if (value is bool) {
      return value ? '1' : '0'; // MySQL uses 1/0
    }
    if (value == null) {
      return 'NULL';
    }
    if (value is String) {
      // Escape backslashes and single quotes
      return "'${value.replaceAll("\\", "\\\\").replaceAll("'", "\\'")}'";
    }
    return value.toString(); // Numbers, etc.
  }

  /// Compila o comando SQL para habilitar restrições de chave estrangeira no MySQL.
  @override
  List<String> compileEnableForeignKeyConstraints() {
    return ['SET FOREIGN_KEY_CHECKS=1;'];
  }

  /// Compila o comando SQL para desabilitar restrições de chave estrangeira no MySQL.
  @override
  List<String> compileDisableForeignKeyConstraints() {
    return ['SET FOREIGN_KEY_CHECKS=0;'];
  }
}
