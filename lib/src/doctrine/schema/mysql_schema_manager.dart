import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/schema/grammars/schema_mysql_grammar.dart';
import 'abstract_schema_manager.dart';
import 'column.dart';
import 'index.dart';
import 'foreign_key_constraint.dart';
import 'view.dart';
import 'sequence.dart';
//import 'schema_config.dart';
import 'package:meta/meta.dart';
import 'dart:async';

/// Schema manager implementation for MySQL/MariaDB.
/// Inspired by Doctrine\DBAL\Schema\MySQLSchemaManager.
class MySqlSchemaManager extends AbstractSchemaManager {
  String? _currentDatabase; // Cache for current database name

  MySqlSchemaManager(ConnectionInterface connection)
      : super(connection, SchemaMySqlGrammar()); // Use MySQL grammar

  /// Helper to get the current database name, caching the result.
  @protected
  Future<String> _getCurrentDatabase() async {
    _currentDatabase ??= connection.getDatabaseName();
    // Fallback if connection doesn't provide it directly
    if (_currentDatabase == null || _currentDatabase!.isEmpty) {
      try {
        final result = await connection.selectOne('SELECT DATABASE() as db');
        _currentDatabase = result?['db'] as String?;
      } catch (e) {
        print("Warning: Could not determine current database. Error: $e");
        // You might want to throw or return a default/empty string depending on requirements
        throw Exception("Could not determine current database.");
      }
    }
    if (_currentDatabase == null || _currentDatabase!.isEmpty) {
      throw Exception("Current database name is unknown.");
    }
    return _currentDatabase!;
  }

  @override
  Future<List<String>> listTableNames() async {
    final dbName = await _getCurrentDatabase();
    final sql = '''
        SELECT TABLE_NAME
        FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = ?
          AND TABLE_TYPE = 'BASE TABLE'
        ORDER BY TABLE_NAME
    ''';
    final results = await connection.select(sql, [dbName]);
    return results.map((row) => row['TABLE_NAME'] as String).toList();
  }

  @override
  Future<Map<String, Column>> listTableColumns(String tableName) async {
    final dbName = await _getCurrentDatabase();
    final sql = '''
        SELECT
           COLUMN_NAME        AS field,
           COLUMN_TYPE        AS type,
           IS_NULLABLE        AS `null`,
           COLUMN_KEY         AS `key`,
           COLUMN_DEFAULT     AS `default`,
           EXTRA,
           COLUMN_COMMENT     AS comment,
           CHARACTER_SET_NAME AS characterset,
           COLLATION_NAME     AS collation,
           -- Approximate length for types where it's not explicit in COLUMN_TYPE
           COALESCE(CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION) AS length
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
        ORDER BY ORDINAL_POSITION
    ''';

    final results = await connection.select(sql, [dbName, tableName]);
    final Map<String, Column> columns = {};
    for (final row in results) {
      // Convert keys to lowercase for consistency like the PHP version
      final lowerCaseRow =
          Utils.map_change_key_case_sd(Map<String, dynamic>.from(row));
      final column = parsePortableTableColumnDefinition(lowerCaseRow);
      columns[column.getCanonicalName()] = column;
    }
    return columns;
  }

  @override
  Future<Map<String, Index>> listTableIndexes(String tableName) async {
    final dbName = await _getCurrentDatabase();
    final sql = '''
        SELECT
            INDEX_NAME  AS Key_name,
            NON_UNIQUE  AS Non_Unique,
            COLUMN_NAME AS Column_Name,
            SUB_PART    AS Sub_Part,
            INDEX_TYPE  AS Index_Type
        FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
        ORDER BY Key_name, SEQ_IN_INDEX
    ''';
    final results = await connection.select(sql, [dbName, tableName]);

    // Group results by index name
    final Map<String, List<Map<String, dynamic>>> indexesData = {};
    for (final row in results) {
      final lowerCaseRow =
          Utils.map_change_key_case_sd(Map<String, dynamic>.from(row));
      final indexName = lowerCaseRow['key_name'] as String;
      indexesData.putIfAbsent(indexName, () => []).add(lowerCaseRow);
    }

    final Map<String, Index> indexes = {};
    indexesData.forEach((indexName, indexRows) {
      try {
        final index = parsePortableTableIndexDefinition(indexRows.first,
            indexRows); // Pass first row and all rows for the index
        indexes[index.getCanonicalName()] = index;
      } catch (e) {
        print("Warning: Could not parse index '$indexName'. Error: $e");
      }
    });

    return indexes;
  }

  @override
  Future<Map<String, ForeignKeyConstraint>> listTableForeignKeys(
      String tableName) async {
    final dbName = await _getCurrentDatabase();
    final sql = '''
        SELECT DISTINCT
            k.CONSTRAINT_NAME,
            k.COLUMN_NAME,
            k.REFERENCED_TABLE_NAME,
            k.REFERENCED_COLUMN_NAME,
            k.ORDINAL_POSITION,
            rc.UPDATE_RULE,
            rc.DELETE_RULE
        FROM information_schema.key_column_usage k
        INNER JOIN information_schema.referential_constraints rc
          ON rc.CONSTRAINT_CATALOG = k.CONSTRAINT_CATALOG
         AND rc.CONSTRAINT_SCHEMA = k.CONSTRAINT_SCHEMA
         AND rc.CONSTRAINT_NAME = k.CONSTRAINT_NAME
         AND rc.TABLE_NAME = k.TABLE_NAME -- Added for potentially better join performance
        WHERE k.TABLE_SCHEMA = ?
          AND k.TABLE_NAME = ?
          AND rc.CONSTRAINT_SCHEMA = ? -- Ensures constraint is in the same schema
          AND k.REFERENCED_COLUMN_NAME IS NOT NULL
        ORDER BY k.CONSTRAINT_NAME, k.ORDINAL_POSITION
    ''';

    final results = await connection.select(sql, [dbName, tableName, dbName]);

    // Group results by constraint name
    final Map<String, List<Map<String, dynamic>>> fkData = {};
    for (final row in results) {
      final lowerCaseRow =
          Utils.map_change_key_case_sd(Map<String, dynamic>.from(row));
      final constraintName = lowerCaseRow['constraint_name'] as String;
      fkData.putIfAbsent(constraintName, () => []).add(lowerCaseRow);
    }

    final Map<String, ForeignKeyConstraint> foreignKeys = {};
    fkData.forEach((constraintName, fkRows) {
      try {
        final fk = parsePortableTableForeignKeyDefinition(fkRows.first, fkRows);
        foreignKeys[fk.getCanonicalName()] = fk;
      } catch (e) {
        print(
            "Warning: Could not parse foreign key '$constraintName'. Error: $e");
      }
    });

    return foreignKeys;
  }

  @override
  Future<Map<String, dynamic>> fetchTableOptions(String tableName) async {
    final dbName = await _getCurrentDatabase();
    final sql = '''
            SELECT
                ENGINE,
                TABLE_COLLATION,
                TABLE_COMMENT,
                CREATE_OPTIONS,
                AUTO_INCREMENT
            FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
        ''';
    final results = await connection.select(sql, [dbName, tableName]);

    if (results.isEmpty) {
      return {};
    }

    final data =
        Utils.map_change_key_case_sd(Map<String, dynamic>.from(results.first));
    final options = <String, dynamic>{};

    if (data['engine'] != null) options['engine'] = data['engine'];
    if (data['table_collation'] != null)
      options['collation'] = data['table_collation'];
    if (data['table_comment'] != null)
      options['comment'] = data['table_comment'];
    if (data['auto_increment'] != null)
      options['autoincrement'] = data['auto_increment'];

    // Parse CREATE_OPTIONS (e.g., "ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8")
    if (data['create_options'] != null &&
        (data['create_options'] as String).isNotEmpty) {
      options['create_options'] =
          _parseCreateOptions(data['create_options'] as String?);
    }
    // Fetch charset separately if needed (COLLATION implies CHARSET in MySQL/MariaDB)
    // if (options['collation'] != null) {
    //    options['charset'] = options['collation'].split('_')[0]; // Heuristic
    // }

    return options;
  }

  /// Helper to parse MySQL's CREATE_OPTIONS string.
  Map<String, dynamic> _parseCreateOptions(String? createOptions) {
    final options = <String, dynamic>{};
    if (createOptions == null || createOptions.isEmpty) {
      return options;
    }
    final pairs = createOptions.split(' ');
    for (final pair in pairs) {
      final parts = pair.split('=');
      if (parts.length == 2) {
        options[parts[0].toLowerCase()] = parts[1];
      } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
        options[parts[0].toLowerCase()] = true; // Option without value
      }
    }
    return options;
  }

  @override
  @protected
  Column parsePortableTableColumnDefinition(Map<String, dynamic> tableColumn) {
    final String dbTypeFull =
        (tableColumn['type'] as String? ?? '').toLowerCase();
    String dbType = dbTypeFull.split(RegExp(r'[(),\s]')).first; // Get base type

    int? length;
    int? precision;
    int scale = 0; // Default scale
    bool fixed = false;
    List<String>? values; // For enum/set

    final name = tableColumn['field'] as String;

    // Extract length, precision, scale from `type` string
    final typeMatch = RegExp(r'^[a-z]+\((.+)\)').firstMatch(dbTypeFull);
    if (typeMatch != null) {
      final args = typeMatch.group(1)!.split(',');
      if (args.isNotEmpty) {
        if (args.length == 1) {
          // Could be length for string types, or precision for others
          final val = int.tryParse(args[0].trim());
          if ([
            'char',
            'varchar',
            'binary',
            'varbinary',
            'text',
            'blob',
            'tinytext',
            'mediumtext',
            'longtext',
            'tinyblob',
            'mediumblob',
            'longblob'
          ].contains(dbType)) {
            length = val;
          } else if (['decimal', 'numeric', 'float', 'double', 'real']
              .contains(dbType)) {
            precision = val;
          } else if (dbType == 'enum' || dbType == 'set') {
            values = _parseEnumOrSetExpression(typeMatch.group(1)!);
          }
          // Ignore for int types where length is often display width
        } else if (args.length == 2) {
          precision = int.tryParse(args[0].trim());
          scale = int.tryParse(args[1].trim()) ?? 0;
          length = null; // Precision/scale override length
        }
      }
    } else {
      // Handle types without explicit length/precision in definition string
      switch (dbType) {
        case 'tinytext':
          length = 255;
          break;
        case 'text':
          length = 65535;
          break;
        case 'mediumtext':
          length = 16777215;
          break;
        case 'longtext':
          length = 4294967295;
          break;
        case 'tinyblob':
          length = 255;
          break;
        case 'blob':
          length = 65535;
          break;
        case 'mediumblob':
          length = 16777215;
          break;
        case 'longblob':
          length = 4294967295;
          break;
        case 'year':
          length = 4;
          break; // MySQL YEAR length
        // Int types don't have inherent length here
        case 'tinyint':
        case 'smallint':
        case 'mediumint':
        case 'int':
        case 'bigint':
          length = null;
          break;
      }
    }

    if (dbType == 'char' || dbType == 'binary') {
      fixed = true;
    }

    final String dartType = _mapMySqlTypeToDartType(dbType);

    // Handle default value (needs MariaDB awareness for true correctness)
    // Simplified version:
    dynamic columnDefault = tableColumn['default'];
    if (columnDefault == 'NULL') {
      columnDefault = null;
    } else if (columnDefault != null && columnDefault is String) {
      // Basic check for quoted strings - might need refinement for MariaDB escapes
      if (columnDefault.startsWith("'") && columnDefault.endsWith("'")) {
        columnDefault = columnDefault
            .substring(1, columnDefault.length - 1)
            .replaceAll("''", "'"); // Unescape doubled quotes
      } else if (columnDefault.toLowerCase() == 'current_timestamp' ||
          columnDefault.toLowerCase() == 'current_timestamp()') {
        columnDefault = QueryExpression('CURRENT_TIMESTAMP');
      }
    }

    final options = <String, dynamic>{
      'length': length,
      'unsigned': dbTypeFull.contains('unsigned'),
      'fixed': fixed,
      'default': columnDefault,
      'notnull': tableColumn['null'] == 'NO',
      'scale': scale,
      'precision': precision,
      'autoIncrement': (tableColumn['extra'] as String? ?? '')
          .toLowerCase()
          .contains('auto_increment'),
      if (values != null)
        'allowed': values, // Use 'allowed' for consistency with Blueprint
      'comment': tableColumn['comment'],
      'charset': tableColumn['characterset'],
      'collation': tableColumn['collation'],
    };

    return Column(name, dartType, options: options);
  }

  /// Maps MySQL/MariaDB types to portable types used by Column/Blueprint.
  String _mapMySqlTypeToDartType(String mysqlType) {
    mysqlType = mysqlType.toLowerCase();
    // Prioritize exact matches first
    switch (mysqlType) {
      case 'char':
        return 'char';
      case 'varchar':
        return 'string';
      case 'text':
        return 'text';
      case 'mediumtext':
        return 'mediumText';
      case 'longtext':
        return 'longText';
      case 'tinyint':
        return 'tinyInteger';
      case 'smallint':
        return 'smallInteger';
      case 'mediumint':
        return 'mediumInteger';
      case 'int':
      case 'integer':
        return 'integer';
      case 'bigint':
        return 'bigInteger';
      case 'float':
        return 'float';
      case 'double':
        return 'double';
      case 'real':
        return 'double'; // Often alias for double
      case 'decimal':
        return 'decimal';
      case 'numeric':
        return 'decimal'; // Often alias for decimal
      case 'bit':
        return 'boolean'; // Common mapping for BIT(1)
      case 'bool':
      case 'boolean':
        return 'boolean';
      case 'date':
        return 'date';
      case 'datetime':
        return 'dateTime';
      case 'timestamp':
        return 'timestamp';
      case 'time':
        return 'time';
      case 'year':
        return 'year';
      case 'enum':
        return 'enum';
      case 'set':
        return 'string'; // Often mapped to string or requires special handling
      case 'json':
        return 'json';
      case 'binary':
        return 'binary';
      case 'varbinary':
        return 'binary';
      case 'blob':
        return 'binary';
      case 'tinyblob':
        return 'binary';
      case 'mediumblob':
        return 'binary';
      case 'longblob':
        return 'binary';
      case 'geometry':
        return 'geometry';
      case 'point':
        return 'point';
      case 'linestring':
        return 'lineString';
      case 'polygon':
        return 'polygon';
      case 'geometrycollection':
        return 'geometryCollection';
      case 'multipoint':
        return 'multiPoint';
      case 'multilinestring':
        return 'multiLineString';
      case 'multipolygon':
        return 'multiPolygon';

      // --- Add other MySQL specific types if needed ---

      default:
        print(
            "Warning: Unmapped MySQL type '$mysqlType'. Falling back to 'string'.");
        return 'string'; // Fallback for unknown types
    }
  }

  /// Parses the arguments inside ENUM('a','b',...) or SET('a','b',...).
  List<String> _parseEnumOrSetExpression(String expression) {
    final List<String> values = [];
    // Matches quoted values, handling escaped quotes inside
    final matches = RegExp(r"'((?:[^'\\]|\\.)*)'").allMatches(expression);
    for (final match in matches) {
      // Unescape standard SQL double quotes ('') and MySQL/MariaDB backslash escapes (\')
      String value = match.group(1)!;
      value = value.replaceAll("''", "'").replaceAll("\\'", "'");
      // TODO: Handle other potential backslash escapes if necessary (e.g., \\ -> \)
      values.add(value);
    }
    return values;
  }

  /// Parses index data, needs grouping logic from the caller.
  @override
  @protected
  Index parsePortableTableIndexDefinition(Map<String, dynamic> indexRow,
      [List<Map<String, dynamic>>? allIndexRows]) {
    // Assume indexRows contains all rows for THIS specific index
    final indexName = indexRow['key_name'] as String;
    final isPrimary = indexName == 'PRIMARY';
    final isUnique =
        !(indexRow['non_unique'] as bool? ?? true); // 0 means unique
    final indexType = (indexRow['index_type'] as String? ?? '').toUpperCase();

    // Extract columns from all rows for this index
    final columnNames = <String>[];
    final columnLengths = <String, int?>{}; // Store prefix lengths if any
    if (allIndexRows != null) {
      for (var row in allIndexRows) {
        final colName = row['column_name'] as String;
        columnNames.add(colName);
        if (row['sub_part'] != null) {
          columnLengths[colName] = int.tryParse(row['sub_part'].toString());
        }
      }
    } else {
      columnNames.add(indexRow['column_name'] as String);
      if (indexRow['sub_part'] != null) {
        columnLengths[indexRow['column_name'] as String] =
            int.tryParse(indexRow['sub_part'].toString());
      }
    }

    final List<String> flags = [];
    if (indexType.contains('FULLTEXT')) flags.add('FULLTEXT');
    if (indexType.contains('SPATIAL')) flags.add('SPATIAL');
    // Add other potential flags based on indexType if needed (BTREE, HASH are common but often default)

    final Map<String, dynamic> options = {};
    if (columnLengths.isNotEmpty && !flags.contains('SPATIAL')) {
      // Store prefix lengths in options for non-spatial indexes
      options['lengths'] = columnLengths;
    }
    // MySQL doesn't store WHERE conditions for partial indexes in information_schema easily

    return Index(
      name: indexName,
      columns: columnNames,
      isPrimary: isPrimary,
      isUnique: isUnique,
      flags: flags,
      options: options,
    );
  }

  /// Parses foreign key data, needs grouping logic from the caller.
  @override
  @protected
  ForeignKeyConstraint parsePortableTableForeignKeyDefinition(
      Map<String, dynamic> fkRow,
      [List<Map<String, dynamic>>? allFkRows]) {
    // Assume fkRows contains all rows for THIS specific constraint
    final constraintName = fkRow['constraint_name'] as String;
    final foreignTable = fkRow['referenced_table_name'] as String;
    final onDelete = (fkRow['delete_rule'] as String? ?? '').toUpperCase();
    final onUpdate = (fkRow['update_rule'] as String? ?? '').toUpperCase();

    // Extract columns from all rows
    final localColumns = <String>[];
    final foreignColumns = <String>[];
    if (allFkRows != null) {
      for (var row in allFkRows) {
        localColumns.add(row['column_name'] as String);
        foreignColumns.add(row['referenced_column_name'] as String);
      }
    } else {
      localColumns.add(fkRow['column_name'] as String);
      foreignColumns.add(fkRow['referenced_column_name'] as String);
    }

    final options = <String, dynamic>{};
    if (onDelete.isNotEmpty && onDelete != 'RESTRICT')
      options['onDelete'] = onDelete;
    if (onUpdate.isNotEmpty && onUpdate != 'RESTRICT')
      options['onUpdate'] = onUpdate;

    return ForeignKeyConstraint(
      name: constraintName,
      localColumns: localColumns,
      foreignTableName: foreignTable,
      foreignColumns: foreignColumns,
      options: options,
    );
  }

  // --- Implementações para Views e Sequences ---

  @override
  Future<List<String>> listViews() async {
    final dbName = await _getCurrentDatabase();
    const sql = '''
      SELECT TABLE_NAME
      FROM information_schema.VIEWS
      WHERE TABLE_SCHEMA = ?
      ORDER BY TABLE_NAME
    ''';
    final results = await connection.select(sql, [dbName]);
    return results.map((row) => row['TABLE_NAME'] as String).toList();
  }

  @override
  Future<View> listViewDetails(String viewName) async {
    final dbName = await _getCurrentDatabase();
    const sql = '''
      SELECT VIEW_DEFINITION
      FROM information_schema.VIEWS
      WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
    ''';
    final results = await connection.select(sql, [dbName, viewName]);

    if (results.isEmpty) {
      throw Exception('View "$viewName" not found in database "$dbName".');
    }

    final viewData = Map<String, dynamic>.from(results.first);
    viewData['view_name'] = viewName; // Add name for the parser
    return parsePortableViewDefinition(viewData);
  }

  @override
  @protected
  View parsePortableViewDefinition(Map<String, dynamic> viewData) {
    final name = viewData['view_name'] as String; // Use the added name
    final sql = viewData['VIEW_DEFINITION'] as String? ?? '';
    return View(name, sql);
  }

  @override
  Future<List<String>> listSequences() async {
    // MySQL/MariaDB do not have sequences in the same way as PostgreSQL or Oracle.
    // AUTO_INCREMENT handles this. Return empty list.
    print(
        "Warning: MySQL/MariaDB do not support sequences directly. Use AUTO_INCREMENT columns.");
    return [];
  }

  @override
  Future<Sequence> listSequenceDetails(String sequenceName) async {
    // Since MySQL doesn't have sequences, this method is not applicable.
    throw UnsupportedError("MySQL/MariaDB do not support sequences directly.");
  }

  @override
  @protected
  Sequence parsePortableSequenceDefinition(Map<String, dynamic> sequenceData) {
    // Not applicable for MySQL.
    throw UnsupportedError("MySQL/MariaDB do not support sequences directly.");
  }

  // --- Helpers Internos (já existentes ou adaptados) ---
  /// Verifica se um identificador está entre aspas (", `, []).
  bool isIdentifierQuoted(String identifier) {
    if (identifier.length < 2) return false;
    final firstChar = identifier[0];
    final lastChar = identifier[identifier.length - 1];
    return (firstChar == '"' && lastChar == '"') ||
        (firstChar == '`' && lastChar == '`') || // MySQL uses backticks
        (firstChar == '[' && lastChar == ']'); // SQL Server uses brackets
  }

  /// Remove as aspas delimitadoras (", `, []).
  String trimQuotes(String identifier) {
    if (isIdentifierQuoted(identifier)) {
      return identifier.substring(1, identifier.length - 1);
    }
    return identifier;
  }

  bool isNumericType(String dartTypeName) {
    // (Implementation mantida como estava no PostgreSQLSchemaManager)
    final numericTypes = {
      'integer',
      'tinyinteger',
      'smallinteger',
      'mediuminteger',
      'biginteger',
      'decimal',
      'float',
      'double',
      'real',
      'numeric',
      'money'
    };
    return numericTypes.contains(dartTypeName.toLowerCase());
  }
}
