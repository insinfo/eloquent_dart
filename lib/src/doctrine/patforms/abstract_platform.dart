// File: C:\MyDartProjects\eloquent\lib\src\doctrine\abstract_platform.dart
//import 'package:eloquent/eloquent.dart';
import '../connection.dart';
import 'package:eloquent/src/doctrine/lock_mode.dart';
// import 'package:eloquent/src/doctrine/patforms/exception/patforms_exception.dart';
// import 'package:eloquent/src/doctrine/schema/unique_constraint.dart';
import 'package:eloquent/src/doctrine/transaction_isolation_level.dart';

import 'package:meta/meta.dart';

// Import necessary Dart types and utility classes
// import '../schema/column.dart';
// import '../schema/table.dart';
import '../schema/index.dart';
import '../schema/foreign_key_constraint.dart';
import '../schema/sequence.dart';
// import '../schema/schema_diff.dart';
import '../schema/table_diff.dart';
import '../exceptions/doctrine_exceptions.dart';
import 'keywords/keyword_list.dart';
import '../schema/abstract_schema_manager.dart';
// import '../schema/identifier.dart';

// Enums corresponding to PHP types/constants
enum TrimMode { LEADING, TRAILING, BOTH, UNSPECIFIED }

enum DateIntervalUnit { SECOND, MINUTE, HOUR, DAY, WEEK, MONTH, QUARTER, YEAR }

/// Base class for all DatabasePlatforms. Central point for platform-specific behaviors.
/// Corresponds to Doctrine\DBAL\Platforms\AbstractPlatform.
abstract class AbstractPlatform {
  /// Cached mapping from DB types (lowercase) to Doctrine/Application types.
  Map<String, String>? _doctrineTypeMapping;

  /// Cached KeywordList instance for the platform.
  KeywordList? _keywords;

  /// Constructor - subclasses might initialize mappings here.
  AbstractPlatform();

  // --- Abstract Methods (Must be implemented by subclasses) ---

  /// Returns the SQL snippet that declares a boolean column.
  String getBooleanTypeDeclarationSQL(Map<String, dynamic> column);

  /// Returns the SQL snippet that declares a 4 byte integer column (integer).
  String getIntegerTypeDeclarationSQL(Map<String, dynamic> column);

  /// Returns the SQL snippet that declares an 8 byte integer column (bigint).
  String getBigIntTypeDeclarationSQL(Map<String, dynamic> column);

  /// Returns the SQL snippet that declares a 2 byte integer column (smallint).
  String getSmallIntTypeDeclarationSQL(Map<String, dynamic> column);

  /// Returns the SQL snippet that declares common properties of an integer column.
  String getCommonIntegerTypeDeclarationSQL(Map<String, dynamic> column);

  /// Initializes the platform's default Doctrine Type Mappings.
  @protected
  void initializeDoctrineTypeMappings();

  /// Returns the SQL snippet used to declare a CLOB column type.
  String getClobTypeDeclarationSQL(Map<String, dynamic> column);

  /// Returns the SQL Snippet used to declare a BLOB column type.
  String getBlobTypeDeclarationSQL(Map<String, dynamic> column);

  /// Returns the SQL snippet to get the position of the first occurrence of a substring.
  String getLocateExpression(String string, String substring, [String? start]);

  /// Returns the SQL to calculate the difference in days between two dates (date1 - date2).
  String getDateDiffExpression(String date1, String date2);

  /// Returns the SQL for a date arithmetic expression using intervals.
  String _getDateArithmeticIntervalExpression(
      String date, String operator, String interval, DateIntervalUnit unit);

  /// Returns the SQL expression representing the currently selected database.
  String getCurrentDatabaseExpression();

  /// Returns the SQL to list all views of a database or user.
  /// Used internally by AbstractSchemaManager.
  String getListViewsSQL(String database);

  /// Returns the SQL to set the transaction isolation level.
  String getSetTransactionIsolationSQL(
      TransactionIsolationLevel level); // Define enum

  /// Obtains DBMS specific SQL to be used to create datetime columns.
  String getDateTimeTypeDeclarationSQL(Map<String, dynamic> column);

  /// Obtains DBMS specific SQL to be used to create date columns.
  String getDateTypeDeclarationSQL(Map<String, dynamic> column);

  /// Obtains DBMS specific SQL to be used to create time columns.
  String getTimeTypeDeclarationSQL(Map<String, dynamic> column);

  /// Gets the SQL statements for altering an existing table based on a diff.
  List<String> getAlterTableSQL(TableDiff diff); // Define TableDiff

  /// Creates an instance of the reserved keyword list for this platform.
  @protected
  KeywordList createReservedKeywordsList(); // Define KeywordList

  /// Creates the schema manager for inspecting/changing the schema.
  AbstractSchemaManager createSchemaManager(
      DoctrineConnection connection); // Use correct Connection type

  // --- Concrete Methods (Provide default implementations or translate logic) ---

  /// Initializes Doctrine Type Mappings with platform defaults and registered types.
  void _initializeAllDoctrineTypeMappings() {
    if (_doctrineTypeMapping != null) return; // Already initialized

    initializeDoctrineTypeMappings(); // Call abstract subclass initialization

    // This part requires a Dart equivalent of the Doctrine Type system (Type, Type::getTypesMap, etc.)
    // For now, we'll just initialize the map. Subclasses fill it in initializeDoctrineTypeMappings.
    _doctrineTypeMapping ??= {};

    // Example of how it might work with a hypothetical TypeRegistry:
    /*
    TypeRegistry.getTypesMap().forEach((typeName, typeClass) {
      final type = TypeRegistry.getType(typeName); // Get Type instance
      for (final dbType in type.getMappedDatabaseTypes(this)) {
        _doctrineTypeMapping![dbType.toLowerCase()] = typeName;
      }
    });
    */
    print(
        "Warning: Full Doctrine Type mapping requires a ported Type registry system.");
  }

  /// Returns the SQL snippet for declaring an ASCII string column.
  /// Defaults to using the regular string type declaration.
  String getAsciiStringTypeDeclarationSQL(Map<String, dynamic> column) {
    return getStringTypeDeclarationSQL(column);
  }

  /// Returns the SQL snippet for declaring a generic string column.
  /// Differentiates between fixed-length (CHAR) and variable-length (VARCHAR).
  String getStringTypeDeclarationSQL(Map<String, dynamic> column) {
    final length = column['length'] as int?;
    final bool isFixed = column['fixed'] == true;

    try {
      if (!isFixed) {
        return _getVarcharTypeDeclarationSQLSnippet(length);
      }
      return _getCharTypeDeclarationSQLSnippet(length);
    } on InvalidColumnTypeException catch (e) {
      // Use custom exception
      final colName = column['name'] as String? ?? 'unknown';
      throw InvalidColumnDeclarationException.fromInvalidColumnType(colName, e);
    }
  }

  /// Returns the SQL snippet for declaring a binary string column.
  /// Differentiates between fixed-length (BINARY) and variable-length (VARBINARY).
  String getBinaryTypeDeclarationSQL(Map<String, dynamic> column) {
    final length = column['length'] as int?;
    final bool isFixed = column['fixed'] == true;

    try {
      if (!isFixed) {
        return _getVarbinaryTypeDeclarationSQLSnippet(length);
      }
      return _getBinaryTypeDeclarationSQLSnippet(length);
    } on InvalidColumnTypeException catch (e) {
      // Use custom exception
      final colName = column['name'] as String? ?? 'unknown';
      throw InvalidColumnDeclarationException.fromInvalidColumnType(colName, e);
    }
  }

  /// Returns the SQL snippet to declare a CHAR column.
  @protected
  String _getCharTypeDeclarationSQLSnippet(int? length) {
    String sql = 'CHAR';
    if (length != null) {
      sql += '($length)';
    }
    return sql;
  }

  /// Returns the SQL snippet to declare a VARCHAR column.
  /// Throws if length is required but not provided.
  @protected
  String _getVarcharTypeDeclarationSQLSnippet(int? length) {
    if (length == null) {
      // Adapt exception to Dart
      throw ColumnLengthRequiredException('VARCHAR');
    }
    return 'VARCHAR($length)';
  }

  /// Returns the SQL snippet to declare a fixed-length BINARY column.
  @protected
  String _getBinaryTypeDeclarationSQLSnippet(int? length) {
    String sql = 'BINARY';
    if (length != null) {
      sql += '($length)';
    }
    return sql;
  }

  /// Returns the SQL snippet to declare a variable-length VARBINARY column.
  /// Throws if length is required but not provided.
  @protected
  String _getVarbinaryTypeDeclarationSQLSnippet(int? length) {
    if (length == null) {
      throw ColumnLengthRequiredException('VARBINARY');
    }
    return 'VARBINARY($length)';
  }

  /// Returns the SQL snippet to declare an ENUM column.
  /// Default implementation maps to VARCHAR. Subclasses (MySQL) should override.
  String getEnumDeclarationSQL(Map<String, dynamic> column) {
    final values = column['values'] as List<String>?; // Expect list of strings
    if (values == null || values.isEmpty) {
      throw ColumnValuesRequiredException('ENUM'); // Use custom exception
    }

    // Find max length for VARCHAR emulation
    int maxLength = 0;
    for (final value in values) {
      // Use runes for potentially multi-byte characters
      if (value.runes.length > maxLength) {
        maxLength = value.runes.length;
      }
    }
    if (maxLength == 0) maxLength = 1; // Avoid VARCHAR(0)

    // Emulate using VARCHAR
    final Map<String, dynamic> varcharColumn = {'length': maxLength};
    return getStringTypeDeclarationSQL(varcharColumn);
  }

  /// Returns the SQL snippet to declare a GUID/UUID column.
  /// Default maps to CHAR(36). Subclasses (PostgreSQL, SQL Server) override.
  String getGuidTypeDeclarationSQL(Map<String, dynamic> column) {
    final modifiedColumn = Map<String, dynamic>.from(column);
    modifiedColumn['length'] = 36;
    modifiedColumn['fixed'] = true;
    return getStringTypeDeclarationSQL(modifiedColumn);
  }

  /// Returns the SQL snippet to declare a JSON column.
  /// Default maps to CLOB/TEXT. Subclasses (PostgreSQL, MySQL) override.
  String getJsonTypeDeclarationSQL(Map<String, dynamic> column) {
    return getClobTypeDeclarationSQL(column);
  }

  /// Registers a Doctrine type mapping for a specific database type.
  /// Throws TypeNotFoundException if the Doctrine type doesn't exist.
  void registerDoctrineTypeMapping(String dbType, String doctrineType) {
    _initializeAllDoctrineTypeMappings(); // Ensure map is initialized

    // Requires Dart equivalent of Type::hasType
    /*
    if (!TypeRegistry.hasType(doctrineType)) {
      throw TypeNotFoundException(doctrineType);
    }
    */
    print(
        "Warning: Type existence check skipped for '$doctrineType' due to missing Type registry.");

    final lowerDbType = dbType.toLowerCase();
    _doctrineTypeMapping![lowerDbType] = doctrineType;
  }

  /// Gets the mapped Doctrine type for a given database type.
  /// Throws InvalidArgumentException if the mapping doesn't exist.
  String getDoctrineTypeMapping(String dbType) {
    _initializeAllDoctrineTypeMappings(); // Ensure map is initialized

    final lowerDbType = dbType.toLowerCase();
    if (!_doctrineTypeMapping!.containsKey(lowerDbType)) {
      throw InvalidArgumentException(
          'Unknown database type "$lowerDbType" requested for platform ${runtimeType}.');
    }
    return _doctrineTypeMapping![lowerDbType]!;
  }

  /// Checks if a Doctrine type mapping exists for a given database type.
  bool hasDoctrineTypeMappingFor(String dbType) {
    _initializeAllDoctrineTypeMappings(); // Ensure map is initialized
    return _doctrineTypeMapping!.containsKey(dbType.toLowerCase());
  }

  /// Returns the regular expression operator (e.g., 'REGEXP', '~').
  /// Throws NotSupportedException by default.
  String getRegexpExpression() {
    throw NotSupportedException('Regexp Expression');
  }

  /// Returns the SQL snippet for getting character length (e.g., LENGTH, LEN).
  String getLengthExpression(String string) {
    return 'LENGTH($string)';
  }

  /// Returns the SQL snippet for the modulo operator (e.g., MOD, %).
  String getModExpression(String dividend, String divisor) {
    return 'MOD($dividend, $divisor)';
  }

  /// Returns the SQL snippet to trim a string.
  String getTrimExpression(String str,
      [TrimMode mode = TrimMode.UNSPECIFIED, String? char]) {
    final tokens = <String>[];

    switch (mode) {
      case TrimMode.UNSPECIFIED:
        break;
      case TrimMode.LEADING:
        tokens.add('LEADING');
        break;
      case TrimMode.TRAILING:
        tokens.add('TRAILING');
        break;
      case TrimMode.BOTH:
        tokens.add('BOTH');
        break;
    }

    if (char != null) {
      tokens.add(char); // Assume char is already quoted if needed by caller
    }

    if (tokens.isNotEmpty) {
      tokens.add('FROM');
    }

    tokens.add(str);

    return 'TRIM(${tokens.join(' ')})';
  }

  /// Returns an SQL snippet to get a substring inside a string.
  String getSubstringExpression(String string, String start, [String? length]) {
    if (length == null) {
      return 'SUBSTRING($string FROM $start)';
    }
    return 'SUBSTRING($string FROM $start FOR $length)';
  }

  /// Returns an SQL snippet to concatenate strings (e.g., '||', CONCAT).
  String getConcatExpression(List<String> strings) {
    return strings.join(' || '); // Standard SQL, subclasses can override
  }

  // --- Date Arithmetic ---
  String getDateAddSecondsExpression(String date, String seconds) =>
      _getDateArithmeticIntervalExpression(
          date, '+', seconds, DateIntervalUnit.SECOND);
  String getDateSubSecondsExpression(String date, String seconds) =>
      _getDateArithmeticIntervalExpression(
          date, '-', seconds, DateIntervalUnit.SECOND);
  String getDateAddMinutesExpression(String date, String minutes) =>
      _getDateArithmeticIntervalExpression(
          date, '+', minutes, DateIntervalUnit.MINUTE);
  String getDateSubMinutesExpression(String date, String minutes) =>
      _getDateArithmeticIntervalExpression(
          date, '-', minutes, DateIntervalUnit.MINUTE);
  String getDateAddHourExpression(String date, String hours) =>
      _getDateArithmeticIntervalExpression(
          date, '+', hours, DateIntervalUnit.HOUR);
  String getDateSubHourExpression(String date, String hours) =>
      _getDateArithmeticIntervalExpression(
          date, '-', hours, DateIntervalUnit.HOUR);
  String getDateAddDaysExpression(String date, String days) =>
      _getDateArithmeticIntervalExpression(
          date, '+', days, DateIntervalUnit.DAY);
  String getDateSubDaysExpression(String date, String days) =>
      _getDateArithmeticIntervalExpression(
          date, '-', days, DateIntervalUnit.DAY);
  String getDateAddWeeksExpression(String date, String weeks) =>
      _getDateArithmeticIntervalExpression(
          date, '+', weeks, DateIntervalUnit.WEEK);
  String getDateSubWeeksExpression(String date, String weeks) =>
      _getDateArithmeticIntervalExpression(
          date, '-', weeks, DateIntervalUnit.WEEK);
  String getDateAddMonthExpression(String date, String months) =>
      _getDateArithmeticIntervalExpression(
          date, '+', months, DateIntervalUnit.MONTH);
  String getDateSubMonthExpression(String date, String months) =>
      _getDateArithmeticIntervalExpression(
          date, '-', months, DateIntervalUnit.MONTH);
  String getDateAddQuartersExpression(String date, String quarters) =>
      _getDateArithmeticIntervalExpression(
          date, '+', quarters, DateIntervalUnit.QUARTER);
  String getDateSubQuartersExpression(String date, String quarters) =>
      _getDateArithmeticIntervalExpression(
          date, '-', quarters, DateIntervalUnit.QUARTER);
  String getDateAddYearsExpression(String date, String years) =>
      _getDateArithmeticIntervalExpression(
          date, '+', years, DateIntervalUnit.YEAR);
  String getDateSubYearsExpression(String date, String years) =>
      _getDateArithmeticIntervalExpression(
          date, '-', years, DateIntervalUnit.YEAR);

  /// Multiplies an interval expression by a number (helper).
  @protected
  String multiplyInterval(String interval, int multiplier) {
    return '($interval * $multiplier)';
  }

  /// Returns the SQL bitwise AND comparison expression.
  String getBitAndComparisonExpression(String value1, String value2) {
    return '($value1 & $value2)';
  }

  /// Returns the SQL bitwise OR comparison expression.
  String getBitOrComparisonExpression(String value1, String value2) {
    return '($value1 | $value2)';
  }

  /// Appends platform-specific lock hints to a FROM clause.
  /// Default implementation does nothing (assumes standard `FOR UPDATE`).
  String appendLockHint(String fromClause, LockMode lockMode) {
    // Define LockMode enum
    return fromClause;
  }

  /// Returns the SQL to drop a table.
  String getDropTableSQL(String table) {
    // Assume 'table' is already quoted if necessary
    return 'DROP TABLE $table';
  }

  /// Returns the SQL to safely drop a temporary table.
  /// Defaults to standard DROP TABLE.
  String getDropTemporaryTableSQL(String table) {
    return getDropTableSQL(table);
  }

  /// Returns the SQL to drop an index from a table.
  String getDropIndexSQL(String name, String table) {
    // Assume 'name' and 'table' are already quoted if necessary
    return 'DROP INDEX $name';
  }

  /// Returns the SQL to drop a constraint.
  @protected
  String getDropConstraintSQL(String name, String table) {
    // Assume 'name' and 'table' are already quoted if necessary
    return 'ALTER TABLE $table DROP CONSTRAINT $name';
  }

  /// Returns the SQL to drop a foreign key constraint.
  /// Default uses standard ALTER TABLE...DROP CONSTRAINT.
  String getDropForeignKeySQL(String foreignKey, String table) {
    // Assume 'foreignKey' (name) and 'table' are already quoted if necessary
    return 'ALTER TABLE $table DROP FOREIGN KEY $foreignKey'; // Or DROP CONSTRAINT
  }

  /// Returns the SQL to drop a unique constraint.
  /// Default uses standard ALTER TABLE...DROP CONSTRAINT.
  String getDropUniqueConstraintSQL(String name, String tableName) {
    return getDropConstraintSQL(name, tableName);
  }

  /// Returns the SQL statement(s) to create a table.
  /// Delegates to internal helper _buildCreateTableSQL.
  // List<String> getCreateTableSQL(Table table) {
  //   return _buildCreateTableSQL(table, true);
  // }

  /// Internal helper to build CREATE TABLE statements.
  // List<String> _buildCreateTableSQL(Table table, bool createForeignKeys) {
  //   if (table.getColumns().isEmpty) {
  //     throw NoColumnsSpecifiedForTable(table.getName());
  //   }

  //   final tableName = table.getQuotedName(this);
  //   final options =
  //       Map<String, dynamic>.from(table.getOptions()); // Copy options
  //   options['uniqueConstraints'] = <UniqueConstraint>[]; // Use correct type
  //   options['indexes'] = <Index>[];
  //   options['primary'] = <String>[]; // Stores quoted column names for PK

  //   final primaryKeyIndex =
  //       table.getPrimaryKey(); // Get the primary key index object
  //   if (primaryKeyIndex != null) {
  //     options['primary'] = primaryKeyIndex.getQuotedColumns(this);
  //     options['primary_index'] =
  //         primaryKeyIndex; // Store the index object itself
  //   }

  //   // Add non-primary indexes and unique constraints to options
  //   for (final index in table.getIndexes()) {
  //     if (!index.isPrimary) {
  //       options['indexes'].add(index);
  //     }
  //   }
  //   for (final uniqueConstraint in table.getUniqueConstraints()) {
  //     options['uniqueConstraints'].add(uniqueConstraint);
  //   }

  //   if (createForeignKeys) {
  //     options['foreignKeys'] = <ForeignKeyConstraint>[];
  //     for (final fkConstraint in table.getForeignKeys()) {
  //       options['foreignKeys'].add(fkConstraint);
  //     }
  //   }

  //   // Convert Column objects to the Map format expected by getColumnDeclarationSQL
  //   final columns = <Map<String, dynamic>>[];
  //   for (final column in table.getColumns()) {
  //     final columnData = _columnToArray(column);
  //     // Mark if the column is part of the primary key
  //     if ((options['primary'] as List).contains(column.getQuotedName(this))) {
  //       columnData['primary'] = true;
  //     }
  //     columns.add(columnData);
  //   }

  //   // Call the abstract helper method to generate the core CREATE TABLE SQL
  //   final sql = _getCreateTableSQL(tableName, columns, options);

  //   // Add COMMENT statements if supported and needed
  //   if (supportsCommentOnStatement()) {
  //     final String? tableComment = options['comment'] as String?;
  //     if (tableComment != null && tableComment.isNotEmpty) {
  //       sql.add(getCommentOnTableSQL(tableName, tableComment));
  //     }
  //     for (final column in table.getColumns()) {
  //       final String? columnComment = column.getComment;
  //       if (columnComment != null && columnComment.isNotEmpty) {
  //         sql.add(getCommentOnColumnSQL(
  //             tableName, column.getQuotedName(this), columnComment));
  //       }
  //     }
  //   }

  //   return sql;
  // }

  /// Abstract helper method for the core CREATE TABLE syntax.
  /// Subclasses must implement this.
  List<String> getCreateTableSQL(String name,
      List<Map<String, dynamic>> columns, Map<String, dynamic> options);

  /// Returns SQL statements to create multiple tables, handling dependencies.
  // List<String> getCreateTablesSQL(List<Table> tables) {
  //   final sql = <String>[];
  //   // Create tables first (without FKs)
  //   for (final table in tables) {
  //     sql.addAll(_buildCreateTableSQL(table, false));
  //   }
  //   // Add foreign keys afterwards
  //   for (final table in tables) {
  //     for (final foreignKey in table.getForeignKeys()) {
  //       sql.add(getCreateForeignKeySQL(foreignKey, table.getQuotedName(this)));
  //     }
  //   }
  //   return sql;
  // }

  /// Returns SQL statements to drop multiple tables, handling dependencies.
  // List<String> getDropTablesSQL(List<Table> tables) {
  //   final sql = <String>[];
  //   // Drop foreign keys first
  //   for (final table in tables) {
  //     for (final foreignKey in table.getForeignKeys()) {
  //       sql.add(getDropForeignKeySQL(
  //           foreignKey.getQuotedName(this), table.getQuotedName(this)));
  //     }
  //   }
  //   // Drop tables afterwards
  //   for (final table in tables) {
  //     sql.add(getDropTableSQL(table.getQuotedName(this)));
  //   }
  //   return sql;
  // }

  /// Returns SQL for adding a comment on a table.
  /// Requires platform support (supportsCommentOnStatement).
  @protected
  // String getCommentOnTableSQL(String tableName, String comment) {
  //   final tableIdentifier = Identifier(tableName); // Use Identifier class
  //   return 'COMMENT ON TABLE ${tableIdentifier.getQuotedName(this)} IS ${quoteStringLiteral(comment)}';
  // }

  /// Returns SQL for adding a comment on a column.
  /// Requires platform support (supportsCommentOnStatement).
  // String getCommentOnColumnSQL(
  //     String tableName, String columnName, String comment) {
  //   final tableIdentifier = Identifier(tableName);
  //   final columnIdentifier = Identifier(columnName); // Use Identifier class
  //   return 'COMMENT ON COLUMN ${tableIdentifier.getQuotedName(this)}.${columnIdentifier.getQuotedName(this)} IS ${quoteStringLiteral(comment)}';
  // }

  /// Returns SQL for inline column comment (if supported).
  String getInlineColumnCommentSQL(String comment) {
    if (!supportsInlineColumnComments()) {
      throw NotSupportedException('Inline Column Comments');
    }
    return 'COMMENT ${quoteStringLiteral(comment)}';
  }

  /// Returns the SQL snippet for creating a temporary table.
  String getCreateTemporaryTableSnippetSQL() {
    return 'CREATE TEMPORARY TABLE';
  }

  /// Generates SQL statements to apply a schema difference.
  /// Needs SchemaDiff implementation.
  // List<String> getAlterSchemaSQL(SchemaDiff diff) {
  //   final sql = <String>[];

  //   if (supportsSchemas()) {
  //     for (final schemaName in diff.getCreatedSchemas()) {
  //       // Assuming getCreatedSchemas()
  //       sql.add(getCreateSchemaSQL(schemaName));
  //     }
  //     // TODO: Handle dropped/altered schemas if needed
  //   }

  //   if (supportsSequences()) {
  //     for (final sequence in diff.getAlteredSequences()) {
  //       // Assuming getAlteredSequences()
  //       sql.add(getAlterSequenceSQL(sequence));
  //     }
  //     for (final sequence in diff.getDroppedSequences()) {
  //       // Assuming getDroppedSequences()
  //       sql.add(getDropSequenceSQL(sequence.getQuotedName(this)));
  //     }
  //     for (final sequence in diff.getCreatedSequences()) {
  //       // Assuming getCreatedSequences()
  //       sql.add(getCreateSequenceSQL(sequence));
  //     }
  //   }

  //   // Handle table changes
  //   sql.addAll(getCreateTablesSQL(
  //       diff.getCreatedTables())); // Assuming getCreatedTables()
  //   sql.addAll(getDropTablesSQL(
  //       diff.getDroppedTables())); // Assuming getDroppedTables()

  //   for (final tableDiff in diff.getAlteredTables()) {
  //     // Assuming getAlteredTables()
  //     sql.addAll(getAlterTableSQL(tableDiff));
  //   }

  //   return sql;
  // }

  /// Returns the SQL to create a sequence.
  /// Throws NotSupportedException by default.
  String getCreateSequenceSQL(Sequence sequence) {
    throw NotSupportedException('Sequences');
  }

  /// Returns the SQL to alter a sequence.
  /// Throws NotSupportedException by default.
  String getAlterSequenceSQL(Sequence sequence) {
    throw NotSupportedException('Altering Sequences');
  }

  /// Returns the SQL snippet to drop an existing sequence.
  /// Throws NotSupportedException if platform doesn't support sequences.
  String getDropSequenceSQL(String name) {
    if (!supportsSequences()) {
      throw NotSupportedException('Sequences');
    }
    // Assume 'name' is already quoted if needed
    return 'DROP SEQUENCE $name';
  }

  /// Returns the SQL to create an index on a table.
  // String getCreateIndexSQL(Index index, String table) {
  //   // Assume 'table' is already quoted if needed
  //   final name = index.getQuotedName(this);
  //   final columns = index.getColumns();

  //   if (columns.isEmpty) {
  //     throw InvalidArgumentException(
  //         'Incomplete or invalid index definition "$name" on table "$table". Columns required.');
  //   }

  //   if (index.isPrimary) {
  //     return getCreatePrimaryKeySQL(index, table);
  //   }

  //   final query =
  //       'CREATE ${getCreateIndexSQLFlags(index)}INDEX $name ON $table';
  //   final columnList = index.getQuotedColumns(this).join(', ');
  //   final partialSql = getPartialIndexSQL(index);

  //   return '$query ($columnList)$partialSql';
  // }

  /// Returns the SQL snippet for partial index condition (if supported).
  @protected
  String getPartialIndexSQL(Index index) {
    // Use hasOption and getOption from Index class (needs implementation)
    if (supportsPartialIndexes() && index.hasOption('where')) {
      return ' WHERE ${index.getOption('where')}';
    }
    return '';
  }

  /// Returns SQL flags for index creation (e.g., UNIQUE).
  @protected
  String getCreateIndexSQLFlags(Index index) {
    return index.isUnique ? 'UNIQUE ' : '';
  }

  /// Returns the SQL to create an unnamed primary key constraint.
  // String getCreatePrimaryKeySQL(Index index, String table) {
  //   // Assume 'table' is already quoted if needed
  //   final columnList = index.getQuotedColumns(this).join(', ');
  //   return 'ALTER TABLE $table ADD PRIMARY KEY ($columnList)';
  // }

  /// Returns the SQL to create a named schema.
  /// Throws NotSupportedException if platform doesn't support schemas.
  String getCreateSchemaSQL(String schemaName) {
    if (!supportsSchemas()) {
      throw NotSupportedException('Schemas');
    }
    // Assume schemaName needs quoting
    return 'CREATE SCHEMA ${quoteIdentifier(schemaName)}';
  }

  /// Returns the SQL to create a unique constraint.
  // String getCreateUniqueConstraintSQL(
  //     UniqueConstraint constraint, String tableName) {
  //   // Assume tableName is quoted
  //   String sql = 'ALTER TABLE $tableName ADD';
  //   final constraintName = constraint.getName();
  //   if (constraintName.isNotEmpty) {
  //     sql += ' CONSTRAINT ${constraint.getQuotedName(this)}';
  //   }
  //   final columnList = constraint.getQuotedColumns(this).join(', ');
  //   sql += ' UNIQUE ($columnList)';
  //   // TODO: Handle constraint flags if applicable for the platform
  //   return sql;
  // }

  /// Returns the SQL snippet to drop a schema.
  /// Throws NotSupportedException if platform doesn't support schemas.
  String getDropSchemaSQL(String schemaName) {
    if (!supportsSchemas()) {
      throw NotSupportedException('Schemas');
    }
    // Assume schemaName needs quoting
    return 'DROP SCHEMA ${quoteIdentifier(schemaName)}';
  }

  /// Quotes an identifier (table, column name). Handles dot notation.
  String quoteIdentifier(String identifier) {
    if (identifier.contains('.')) {
      // Quote each part of a qualified name separately
      return identifier.split('.').map(quoteSingleIdentifier).join('.');
    }
    return quoteSingleIdentifier(identifier);
  }

  /// Quotes a single identifier part. Default is standard SQL double quotes.
  /// Subclasses (MySQL, SQLServer) should override.
  String quoteSingleIdentifier(String str) {
    return '"${str.replaceAll('"', '""')}"';
  }

  /// Returns the SQL to create a new foreign key constraint.
  // String getCreateForeignKeySQL(ForeignKeyConstraint foreignKey, String table) {
  //   // Assume 'table' is already quoted if needed
  //   return 'ALTER TABLE $table ADD ${getForeignKeyDeclarationSQL(foreignKey)}';
  // }

  /// Returns the SQL statements needed to rename a table.
  List<String> getRenameTableSQL(String oldName, String newName) {
    // Assume names are already quoted if necessary
    return ['ALTER TABLE $oldName RENAME TO $newName'];
  }

  /// Returns SQL required to drop fieles of FKs/Indexes before altering table.
  @protected
  // List<String> getPreAlterTableIndexForeignKeySQL(TableDiff diff) {
  //   final tableNameSQL =
  //       diff.getOldTable()!.getQuotedName(this); // Get quoted old table name
  //   final sql = <String>[];

  //   // Drop foreign keys that will be dropped or modified
  //   diff.getDroppedForeignKeys().forEach((name, foreignKey) {
  //     sql.add(
  //         getDropForeignKeySQL(foreignKey.getQuotedName(this), tableNameSQL));
  //   });
  //   diff.getModifiedForeignKeys().forEach((name, foreignKey) {
  //     // Drop the *old* constraint name
  //     final oldFk =
  //         diff.getOldTable()!.getForeignKey(name); // Get old FK object
  //     sql.add(getDropForeignKeySQL(oldFk.getQuotedName(this), tableNameSQL));
  //   });

  //   // Drop indexes that will be dropped or modified
  //   diff.getDroppedIndexes().forEach((name, index) {
  //     sql.add(getDropIndexSQL(index.getQuotedName(this), tableNameSQL));
  //   });
  //   diff.getModifiedIndexes().forEach((name, index) {
  //     // Drop the *old* index name
  //     final oldIndex =
  //         diff.getOldTable()!.getIndex(name); // Get old Index object
  //     sql.add(getDropIndexSQL(oldIndex.getQuotedName(this), tableNameSQL));
  //   });

  //   return sql;
  // }

  /// Returns SQL required to create/recreate FKs/Indexes after altering table.
  @protected
  // List<String> getPostAlterTableIndexForeignKeySQL(TableDiff diff) {
  //   final sql = <String>[];
  //   // Use the *new* table name if renamed, otherwise the old one.
  //   final tableNameSQL = diff.getNewTable()?.getQuotedName(this) ??
  //       diff.getOldTable()!.getQuotedName(this);

  //   // Add new foreign keys
  //   diff.getAddedForeignKeys().forEach((name, foreignKey) {
  //     sql.add(getCreateForeignKeySQL(foreignKey, tableNameSQL));
  //   });
  //   // Recreate modified foreign keys (using the new definition)
  //   diff.getModifiedForeignKeys().forEach((name, foreignKey) {
  //     sql.add(getCreateForeignKeySQL(foreignKey, tableNameSQL));
  //   });

  //   // Add new indexes
  //   diff.getAddedIndexes().forEach((name, index) {
  //     sql.add(getCreateIndexSQL(index, tableNameSQL));
  //   });
  //   // Recreate modified indexes (using the new definition)
  //   diff.getModifiedIndexes().forEach((name, index) {
  //     sql.add(getCreateIndexSQL(index, tableNameSQL));
  //   });

  //   // Handle renamed indexes
  //   diff.getRenamedIndexes().forEach((oldIndexName, newIndex) {
  //     // Use the platform's rename logic
  //     final oldIdentifier = Identifier(oldIndexName); // Use Identifier
  //     sql.addAll(getRenameIndexSQL(
  //         oldIdentifier.getQuotedName(this), newIndex, tableNameSQL));
  //   });

  //   return sql;
  // }

  /// Returns the SQL for renaming an index. Default is DROP and CREATE.
  @protected
  // List<String> getRenameIndexSQL(
  //     String oldIndexName, Index index, String tableName) {
  //   // Assume names/table are quoted
  //   return [
  //     getDropIndexSQL(oldIndexName, tableName),
  //     getCreateIndexSQL(index, tableName),
  //   ];
  // }

  /// Returns the SQL for renaming a column. Default is ALTER TABLE RENAME COLUMN.
  @protected
  List<String> getRenameColumnSQL(
      String tableName, String oldColumnName, String newColumnName) {
    // Assume names/table are quoted
    return [
      'ALTER TABLE $tableName RENAME COLUMN $oldColumnName TO $newColumnName'
    ];
  }

  /// Gets declaration SQL for a list of columns (for CREATE TABLE).
  // String getColumnDeclarationListSQL(List<Map<String, dynamic>> columns) {
  //   final declarations = <String>[];
  //   for (final column in columns) {
  //     final colName =
  //         column['name'] as String? ?? 'unknown_col'; // Should always have name
  //     declarations.add(getColumnDeclarationSQL(colName, column));
  //   }
  //   return declarations.join(', ');
  // }

  /// Obtains the SQL declaration for a single column.
  /// Handles 'columnDefinition' override.
  // String getColumnDeclarationSQL(String name, Map<String, dynamic> column) {
  //   // Assume 'name' is already quoted here
  //   if (column.containsKey('columnDefinition')) {
  //     return '$name ${column['columnDefinition']}';
  //   }

  //   // Need to get the Type object from the column map somehow,
  //   // or assume 'type' key holds a Type instance or type name string.
  //   final type =
  //       column['type']; // This needs resolution to a Type object or similar
  //   String typeDecl;

  //   if (type is Type) {
  //     // Assuming a Type class exists
  //     typeDecl = type.getSQLDeclaration(
  //         column, this); // getSQLDeclaration needs implementation
  //   } else if (type is String) {
  //     // Fallback: Try to map string type name to a declaration method
  //     // This part is complex without the full Type system.
  //     // Example: Use a switch or map based on type name string.
  //     typeDecl = _getSqlDeclarationForTypeName(type, column);
  //     print(
  //         "Warning: Generating SQL declaration from type name string '$type'. Consider using Type objects.");
  //   } else {
  //     throw ArgumentError(
  //         "Column 'type' must be a Type instance or a type name string.");
  //   }

  //   final charset = column['charset'] != null
  //       ? ' ${getColumnCharsetDeclarationSQL(column['charset'])}'
  //       : '';
  //   final collation = column['collation'] != null
  //       ? ' ${getColumnCollationDeclarationSQL(column['collation'])}'
  //       : '';
  //   final notnull = (column['notnull'] == true) ? ' NOT NULL' : '';
  //   final defaultValue = getDefaultValueDeclarationSQL(
  //       column); // Includes ' DEFAULT ...' or ' DEFAULT NULL'

  //   String declaration = '$typeDecl$charset$defaultValue$notnull$collation';

  //   // Append inline comment if supported
  //   if (supportsInlineColumnComments() &&
  //       column['comment'] != null &&
  //       (column['comment'] as String).isNotEmpty) {
  //     declaration += ' ${getInlineColumnCommentSQL(column['comment'])}';
  //   }

  //   return '$name $declaration';
  // }

  /// Placeholder for getting SQL declaration from a type name string.
  /// This needs significant expansion based on supported types.
  String getSqlDeclarationForTypeName(
      String typeName, Map<String, dynamic> column) {
    // This is a simplified lookup. A real implementation needs the full type mapping.
    switch (typeName.toLowerCase()) {
      case 'string':
        return getStringTypeDeclarationSQL(column);
      case 'integer':
        return getIntegerTypeDeclarationSQL(column);
      case 'bigint': // Example if typeBigInteger isn't a method
      case 'biginteger':
        return getBigIntTypeDeclarationSQL(column);
      case 'boolean':
        return getBooleanTypeDeclarationSQL(column);
      case 'date':
        return getDateTypeDeclarationSQL(column);
      case 'datetime':
        return getDateTimeTypeDeclarationSQL(column);
      case 'text':
        return getClobTypeDeclarationSQL(column); // Assuming text maps to clob
      // ... add mappings for all supported types ...
      default:
        throw InvalidArgumentException(
            "Unsupported type name string '$typeName' in column declaration.");
    }
  }

  /// Obtains the SQL declaration for a column's default value.
  String getDefaultValueDeclarationSQL(Map<String, dynamic> column) {
    if (!column.containsKey('default')) {
      // Explicitly return 'DEFAULT NULL' only if column is nullable
      return (column['notnull'] != true) ? ' DEFAULT NULL' : '';
    }

    final defaultValue = column['default'];
    final type = column['type']; // Assume type info is available

    // Handle special default values (like functions)
    // if (defaultValue is QueryExpression) {
    //   // Assuming QueryExpression exists
    //   return ' DEFAULT ${defaultValue.getValue()}';
    // }
    if (type is Type) {
      // Using hypothetical Type system
      // Let the Type object format its default value if needed
      // return ' DEFAULT ${type.getDefaultValueDeclarationSQL(defaultValue, this)}';
      print(
          "Warning: Default value formatting based on Type object not implemented.");
    }

    // Fallback based on Dart type for common cases
    if (type is String) {
      // Check based on Dart type of the *value* if type object missing
      if (defaultValue is bool)
        return ' DEFAULT ${convertBooleans(defaultValue)}';
      if (defaultValue is num)
        return ' DEFAULT $defaultValue'; // Handles int and double
      // Assume CURRENT_TIMESTAMP if value matches and column type is appropriate
      if (defaultValue is String &&
          defaultValue.toUpperCase() == 'CURRENT_TIMESTAMP' &&
          (typeNameIsDateTime(type))) {
        // Hypothetical type check
        return ' DEFAULT ${getCurrentTimestampSQL()}';
      }
      return ' DEFAULT ${quoteStringLiteral(defaultValue.toString())}';
    }
    if (defaultValue is bool)
      return ' DEFAULT ${convertBooleans(defaultValue)}';
    if (defaultValue is num) return ' DEFAULT $defaultValue';

    // Default fallback: quote as string literal
    return ' DEFAULT ${quoteStringLiteral(defaultValue.toString())}';
  }

  // Helper to check if a type name represents a date/time type (needs refinement)
  bool typeNameIsDateTime(dynamic type) {
    if (type is! String) return false; // Or handle Type objects
    final lowerType = type.toLowerCase();
    return lowerType.contains('date') || lowerType.contains('time');
  }

  /// Obtains the SQL declaration for a CHECK constraint.
  String getCheckDeclarationSQL(List<Map<String, dynamic>> definition) {
    final constraints = <String>[];
    for (final def in definition) {
      if (def.containsKey('expression')) {
        // Assuming check expression is passed
        constraints.add('CHECK (${def['expression']})');
      } else if (def.containsKey('min') || def.containsKey('max')) {
        final colName =
            def['name'] as String? ?? 'unknown_col'; // Need column name
        if (def.containsKey('min')) {
          constraints
              .add('CHECK (${quoteIdentifier(colName)} >= ${def['min']})');
        }
        if (def.containsKey('max')) {
          constraints
              .add('CHECK (${quoteIdentifier(colName)} <= ${def['max']})');
        }
      } else {
        print("Warning: Invalid CHECK constraint definition: $def");
      }
    }
    return constraints.join(', ');
  }

  /// Obtains the SQL declaration for a UNIQUE constraint.
  // String getUniqueConstraintDeclarationSQL(UniqueConstraint constraint) {
  //   final columns = constraint.getColumns();
  //   if (columns.isEmpty) {
  //     throw InvalidArgumentException(
  //         'Unique constraint definition requires "columns".');
  //   }

  //   final chunks = <String>[];
  //   final constraintName = constraint.getName();
  //   if (constraintName.isNotEmpty) {
  //     chunks.add('CONSTRAINT');
  //     chunks.add(constraint.getQuotedName(this));
  //   }
  //   chunks.add('UNIQUE');

  //   // TODO: Add platform-specific flag handling (e.g., CLUSTERED for SQL Server)
  //   // if (constraint.hasFlag('clustered')) { chunks.add('CLUSTERED'); }

  //   chunks.add('(${constraint.getQuotedColumns(this).join(', ')})');
  //   return chunks.join(' ');
  // }

  /// Obtains the SQL declaration for an INDEX.
  // String getIndexDeclarationSQL(Index index) {
  //   final columns = index.getColumns();
  //   if (columns.isEmpty) {
  //     throw InvalidArgumentException('Index definition requires "columns".');
  //   }

  //   // Combine flags (like UNIQUE) with the INDEX keyword
  //   return '${getCreateIndexSQLFlags(index)}INDEX ${index.getQuotedName(this)}'
  //       ' (${index.getQuotedColumns(this).join(', ')})'
  //       '${getPartialIndexSQL(index)}';
  // }

  /// Returns the SQL snippet for temporary table name qualification (if needed).
  String getTemporaryTableName(String tableName) {
    return tableName; // Default: no special qualification
  }

  /// Obtains the SQL declaration for a FOREIGN KEY constraint.
  // String getForeignKeyDeclarationSQL(ForeignKeyConstraint foreignKey) {
  //   final sql = getForeignKeyBaseDeclarationSQL(foreignKey);
  //   final advancedOptions = getAdvancedForeignKeyOptionsSQL(foreignKey);
  //   return '$sql$advancedOptions';
  // }

  /// Returns SQL for non-standard FK options (ON UPDATE, ON DELETE, etc.).
  String getAdvancedForeignKeyOptionsSQL(ForeignKeyConstraint foreignKey) {
    String query = '';
    // Assuming Index has hasOption/getOption like PHP version
    if (foreignKey.hasOption('onUpdate')) {
      query +=
          ' ON UPDATE ${getForeignKeyReferentialActionSQL(foreignKey.getOption('onUpdate'))}';
    }
    if (foreignKey.hasOption('onDelete')) {
      query +=
          ' ON DELETE ${getForeignKeyReferentialActionSQL(foreignKey.getOption('onDelete'))}';
    }
    // TODO: Add support for MATCH, DEFERRABLE if needed by specific platforms
    return query;
  }

  /// Returns the uppercase action if valid, otherwise throws.
  String getForeignKeyReferentialActionSQL(String action) {
    final upper = action.toUpperCase();
    const validActions = {
      'CASCADE',
      'SET NULL',
      'NO ACTION',
      'RESTRICT',
      'SET DEFAULT'
    };
    if (validActions.contains(upper)) {
      return upper;
    }
    throw InvalidArgumentException('Invalid foreign key action "$action".');
  }

  /// Obtains the base FOREIGN KEY (...) REFERENCES ... (...) SQL part.
  // String getForeignKeyBaseDeclarationSQL(ForeignKeyConstraint foreignKey) {
  //   String sql = '';
  //   final fkName = foreignKey.getName();
  //   if (fkName.isNotEmpty) {
  //     sql += 'CONSTRAINT ${foreignKey.getQuotedName(this)} ';
  //   }
  //   sql += 'FOREIGN KEY (';

  //   final localColumns = foreignKey.getLocalColumns();
  //   final foreignColumns = foreignKey.getForeignColumns();
  //   final foreignTable = foreignKey.getForeignTableName();

  //   if (localColumns.isEmpty)
  //     throw InvalidArgumentException('Foreign key requires "localColumns".');
  //   if (foreignColumns.isEmpty)
  //     throw InvalidArgumentException('Foreign key requires "foreignColumns".');
  //   if (foreignTable.isEmpty)
  //     throw InvalidArgumentException('Foreign key requires "foreignTable".');
  //   if (localColumns.length != foreignColumns.length) {
  //     throw InvalidArgumentException(
  //         'Local and foreign column count must match for foreign key.');
  //   }

  //   sql += '${foreignKey.getQuotedLocalColumns(this).join(', ')})';
  //   sql +=
  //       ' REFERENCES ${foreignKey.getQuotedForeignTableName(this)}'; // Method needed on FK
  //   sql += ' (${foreignKey.getQuotedForeignColumns(this).join(', ')})';

  //   return sql;
  // }

  /// Obtains SQL for CHARACTER SET declaration (usually empty for standard SQL).
  String getColumnCharsetDeclarationSQL(String charset) {
    return ''; // Default: No inline charset per column
  }

  /// Obtains SQL for COLLATION declaration (if supported).
  String getColumnCollationDeclarationSQL(String collation) {
    return supportsColumnCollation()
        ? 'COLLATE ${quoteSingleIdentifier(collation)}' // Quote collation name
        : '';
  }

  /// Converts Dart boolean values to database representation (literals).
  /// Default converts to 0/1 integers.
  dynamic convertBooleans(dynamic item) {
    if (item is bool) {
      return item ? 1 : 0;
    } else if (item is List) {
      // Recursively convert booleans within a list
      return item.map(convertBooleans).toList();
    }
    return item; // Return non-booleans as is
  }

  /// Converts database boolean representation back to Dart bool.
  /// Default assumes non-zero/non-null is true.
  bool? convertFromBoolean(dynamic item) {
    if (item == null) return null;
    if (item is bool) return item;
    if (item is num) return item != 0;
    if (item is String) {
      final lower = item.toLowerCase();
      return lower == 'true' || lower == '1' || lower == 'yes' || lower == 'on';
    }
    // Consider other potential truthy/falsy values if necessary
    return item !=
        null; // Fallback: Treat any non-null as potentially true? Risky.
  }

  /// Converts Dart boolean values to database representation (for prepared statements).
  /// Default uses the same logic as literal conversion.
  dynamic convertBooleansToDatabaseValue(dynamic item) {
    return convertBooleans(item);
  }

  /// Returns SQL for CURRENT_DATE function.
  String getCurrentDateSQL() => 'CURRENT_DATE';

  /// Returns SQL for CURRENT_TIME function.
  String getCurrentTimeSQL() => 'CURRENT_TIME';

  /// Returns SQL for CURRENT_TIMESTAMP function.
  String getCurrentTimestampSQL() => 'CURRENT_TIMESTAMP';

  /// Returns SQL snippet for a specific transaction isolation level.
  @protected
  String getTransactionIsolationLevelSQL(TransactionIsolationLevel level) {
    switch (level) {
      case TransactionIsolationLevel.READ_UNCOMMITTED:
        return 'READ UNCOMMITTED';
      case TransactionIsolationLevel.READ_COMMITTED:
        return 'READ COMMITTED';
      case TransactionIsolationLevel.REPEATABLE_READ:
        return 'REPEATABLE READ';
      case TransactionIsolationLevel.SERIALIZABLE:
        return 'SERIALIZABLE';
    }
  }

  /// Returns SQL to list databases. Throws NotSupportedException by default.
  String getListDatabasesSQL() {
    throw NotSupportedException('Listing Databases');
  }

  /// Returns SQL to list sequences. Throws NotSupportedException by default.
  String getListSequencesSQL(String database) {
    throw NotSupportedException('Listing Sequences');
  }

  /// Returns SQL to create a view.
  String getCreateViewSQL(String name, String sql) {
    // Assume 'name' needs quoting
    return 'CREATE VIEW ${quoteIdentifier(name)} AS $sql';
  }

  /// Returns SQL to drop a view.
  String getDropViewSQL(String name) {
    // Assume 'name' needs quoting
    return 'DROP VIEW ${quoteIdentifier(name)}';
  }

  /// Returns SQL to get the next value of a sequence.
  /// Throws NotSupportedException by default.
  String getSequenceNextValSQL(String sequence) {
    throw NotSupportedException('Sequence NextVal');
  }

  /// Returns SQL to create a database.
  String getCreateDatabaseSQL(String name) {
    // Assume 'name' needs quoting
    return 'CREATE DATABASE ${quoteIdentifier(name)}';
  }

  /// Returns SQL to drop a database.
  String getDropDatabaseSQL(String name) {
    // Assume 'name' needs quoting
    return 'DROP DATABASE ${quoteIdentifier(name)}';
  }

  /// Obtains SQL for datetime with timezone offset columns.
  /// Default delegates to getDateTimeTypeDeclarationSQL.
  String getDateTimeTzTypeDeclarationSQL(Map<String, dynamic> column) {
    return getDateTimeTypeDeclarationSQL(column);
  }

  /// Obtains SQL for floating point columns (typically float/real/double precision).
  /// Default is DOUBLE PRECISION.
  String getFloatDeclarationSQL(Map<String, dynamic> column) {
    return 'DOUBLE PRECISION';
  }

  /// Obtains SQL for smaller floating point columns (typically real/float).
  /// Default is REAL.
  String getSmallFloatDeclarationSQL(Map<String, dynamic> column) {
    return 'REAL';
  }

  /// Gets the default transaction isolation level for the platform.
  TransactionIsolationLevel getDefaultTransactionIsolationLevel() {
    return TransactionIsolationLevel.READ_COMMITTED;
  }

  // --- Feature Support Methods ---

  /// Whether the platform supports sequences. Default: false.
  bool supportsSequences() => false;

  /// Whether the platform supports identity columns (e.g., AUTO_INCREMENT, SERIAL, IDENTITY). Default: false.
  bool supportsIdentityColumns() => false;

  /// Whether the platform supports partial indexes (with WHERE clause). Default: false.
  @protected // Internal use
  bool supportsPartialIndexes() => false;

  /// Whether the platform supports indexes with column length definitions (e.g., MySQL prefix indexes). Default: false.
  bool supportsColumnLengthIndexes() => false;

  /// Whether the platform supports savepoints. Default: true.
  bool supportsSavepoints() => true;

  /// Whether the platform supports releasing savepoints explicitly. Default: true (if savepoints supported).
  bool supportsReleaseSavepoints() => supportsSavepoints();

  /// Whether the platform supports database schemas (namespaces). Default: false.
  bool supportsSchemas() => false;

  /// Whether the platform supports inline column comments (e.g., `col INT COMMENT '...'`). Default: false.
  @protected // Internal use
  bool supportsInlineColumnComments() => false;

  /// Whether the platform supports `COMMENT ON ...` syntax. Default: false.
  @protected // Internal use
  bool supportsCommentOnStatement() => false;

  /// Whether the platform supports explicit column collation. Default: false.
  @protected // Internal use
  bool supportsColumnCollation() => false;

  // --- Date/Time Format Strings ---

  /// Gets the format string (for Dart's DateFormat) for database datetime values.
  String getDateTimeFormatString() => 'yyyy-MM-dd HH:mm:ss';

  /// Gets the format string for database datetime with timezone values.
  String getDateTimeTzFormatString() =>
      'yyyy-MM-dd HH:mm:ss'; // Often needs parsing adjustment

  /// Gets the format string for database date values.
  String getDateFormatString() => 'yyyy-MM-dd';

  /// Gets the format string for database time values.
  String getTimeFormatString() => 'HH:mm:ss';

  // --- Limit/Offset ---

  /// Adds platform-specific LIMIT/OFFSET clause to a query.
  String modifyLimitQuery(String query, int? limit, [int offset = 0]) {
    if (offset < 0) {
      throw InvalidArgumentException(
          'Offset must be non-negative, $offset given.');
    }
    // Use internal method allowing subclasses to override logic easily
    return _doModifyLimitQuery(query, limit, offset);
  }

  /// Internal method for platform-specific LIMIT/OFFSET logic.
  /// Default implementation uses standard LIMIT/OFFSET.
  @protected
  String _doModifyLimitQuery(String query, int? limit, int offset) {
    String modifiedQuery = query;
    if (limit != null) {
      modifiedQuery += ' LIMIT $limit';
    }
    if (offset > 0) {
      modifiedQuery += ' OFFSET $offset';
    }
    return modifiedQuery;
  }

  // --- Miscellaneous ---

  /// Maximum length for identifiers (tables, columns, etc.). Default: 63.
  int getMaxIdentifierLength() => 63;

  /// Returns SQL for an empty INSERT statement (often for identity columns).
  /// Default uses `VALUES (null)`.
  String getEmptyIdentityInsertSQL(
      String quotedTableName, String quotedIdentifierColumnName) {
    return 'INSERT INTO $quotedTableName ($quotedIdentifierColumnName) VALUES (null)';
  }

  /// Generates a TRUNCATE TABLE statement.
  // String getTruncateTableSQL(String tableName, [bool cascade = false]) {
  //   final tableIdentifier = Identifier(tableName);
  //   // Cascade is platform-specific, ignored in default implementation
  //   if (cascade)
  //     print(
  //         "Warning: Cascade option for TRUNCATE might not be supported by this platform.");
  //   return 'TRUNCATE ${tableIdentifier.getQuotedName(this)}';
  // }

  /// Returns a dummy SELECT statement (e.g., `SELECT 1`).
  String getDummySelectSQL([String expression = '1']) {
    return 'SELECT $expression';
  }

  /// Returns SQL to create a savepoint.
  String createSavePoint(String savepoint) => 'SAVEPOINT $savepoint';

  /// Returns SQL to release a savepoint.
  String releaseSavePoint(String savepoint) => 'RELEASE SAVEPOINT $savepoint';

  /// Returns SQL to rollback to a savepoint.
  String rollbackSavePoint(String savepoint) =>
      'ROLLBACK TO SAVEPOINT $savepoint';

  /// Returns the KeywordList instance for this platform (lazy-loaded).
  KeywordList getReservedKeywordsList() {
    return _keywords ??= createReservedKeywordsList();
  }

  /// Quotes a string literal for safe use in SQL.
  /// Default escapes single quotes by doubling them.
  String quoteStringLiteral(String str) {
    return "'${str.replaceAll("'", "''")}'";
  }

  /// Escapes characters for use in a LIKE expression.
  String escapeStringForLike(String inputString, String escapeChar) {
    // Regex needs careful porting - uses preg_quote and addcslashes
    // Basic approach: escape wildcards (%) and (_) and the escape char itself
    final pattern =
        RegExp('[${RegExp.escape(getLikeWildcardCharacters() + escapeChar)}]');
    // Escape the escape character itself before using it in the replacement
    final escapedEscapeChar =
        escapeChar.replaceAllMapped(RegExp(r'([\\])'), (m) => '\\${m[1]}');
    return inputString.replaceAllMapped(
        pattern, (match) => '$escapedEscapeChar${match[0]}');
  }

  /// Returns the characters used as wildcards in LIKE expressions.
  @protected
  String getLikeWildcardCharacters() => '%_';

  /// Converts a Column object to a Map suitable for declaration methods.
  /// This might be redundant if declaration methods are refactored to accept Column.
  @protected
  // Map<String, dynamic> _columnToArray(Column column) {
  //   // Use the existing toArray method on Column
  //   final array = column.toArray();
  //   // Ensure 'name' is quoted for declaration context
  //   array['name'] = column.getQuotedName(this);
  //   // Add other platform-specific options if needed by getColumnDeclarationSQL
  //   // array['version'] = column.hasPlatformOption('version') ? column.getPlatformOption('version') : false; // Example
  //   array['comment'] = column.getComment; // Pass comment along
  //   return array;
  // }

  // SQL Parser - Placeholder, requires separate parser implementation
  /*
   @internal
   SQLParser createSQLParser() {
       return SQLParser(false); // Assuming SQLParser class exists
   }
   */

  /// Compares two Column definitions in the context of this platform.
  // bool columnsEqual(Column column1, Column column2) {
  //   // Convert columns to the array format used by getColumnDeclarationSQL
  //   final column1Array = _columnToArray(column1);
  //   final column2Array = _columnToArray(column2);

  //   // Ignore 'columnDefinition' if present, as it's not set by SchemaManager introspection
  //   column1Array.remove('columnDefinition');
  //   column2Array.remove('columnDefinition');

  //   // Compare the generated SQL declaration strings
  //   if (getColumnDeclarationSQL('', column1Array) !=
  //       getColumnDeclarationSQL('', column2Array)) {
  //     return false;
  //   }

  //   // If the platform supports inline comments, the check above is sufficient.
  //   // Otherwise, compare comments separately.
  //   if (supportsInlineColumnComments()) {
  //     return true;
  //   }

  //   return column1.getComment == column2.getComment;
  // }

  /// Returns the `UNION ALL` keyword string.
  String getUnionAllSQL() => 'UNION ALL';

  /// Returns the compatible `UNION DISTINCT` keyword string.
  String getUnionDistinctSQL() => 'UNION';

  /// Returns the union select query part, potentially surrounded by parenthesis.
  String getUnionSelectPartSQL(String subQuery) {
    // Most platforms require subqueries in UNION to be parenthesized
    return '($subQuery)';
  }

  // --- Helper for string quoting in SQL literals ---
  // (Already implemented as quoteStringLiteral)
}

// Define enums used (if not defined elsewhere)
// enum LockMode { NONE, OPTIMISTIC, PESSIMISTIC_READ, PESSIMISTIC_WRITE }
// enum TransactionIsolationLevel { READ_UNCOMMITTED, READ_COMMITTED, REPEATABLE_READ, SERIALIZABLE }

// Define necessary Exception classes (or use standard ones)
class InvalidArgumentException implements Exception {
  final String message;
  InvalidArgumentException(this.message);
  @override
  String toString() => 'InvalidArgumentException: $message';
}

class NotSupportedException implements Exception {
  final String feature;
  NotSupportedException(this.feature);
  @override
  String toString() =>
      'NotSupportedException: Feature "$feature" is not supported by this platform.';
}

// Define other Doctrine-specific exceptions as needed in doctrine/exceptions/
