import 'package:meta/meta.dart';

import '../../connection.dart';
import '../../schema/grammars/schema_grammar.dart';
import '../exceptions/doctrine_exceptions.dart';
import '../lock_mode.dart';
import '../schema/abstract_schema_manager.dart';
import '../schema/column.dart';
import '../schema/foreign_key_constraint.dart';
import '../schema/index.dart';
import '../schema/schema.dart';
import '../schema/schema_diff.dart';
import '../schema/sequence.dart';
import '../schema/table.dart';
import '../schema/table_diff.dart';
import '../schema/unique_constraint.dart';
import '../transaction_isolation_level.dart';
import 'exception/platform_exceptions.dart';
import 'keywords/keyword_list.dart';

enum TrimMode { LEADING, TRAILING, BOTH, UNSPECIFIED }

enum DateIntervalUnit { SECOND, MINUTE, HOUR, DAY, WEEK, MONTH, QUARTER, YEAR }

/// The SQL dialect of a database: DDL for the Doctrine schema objects
/// ([Table], [Index], [ForeignKeyConstraint], [Sequence], [Schema],
/// [SchemaDiff]), type declarations and portable expressions.
/// Corresponds to Doctrine\DBAL\Platforms\AbstractPlatform.
///
/// Column types and modifiers come from the dialect's [schemaGrammar], the
/// same code that compiles migrations, so both paths emit the same SQL.
/// Names passed to the DDL methods are unquoted; the platform quotes them.
abstract class AbstractPlatform {
  AbstractPlatform();

  Map<String, String>? _typeMappingOverrides;
  KeywordList? _keywords;

  // ------------------------------------------------------- dialect hooks

  /// The schema grammar of the dialect.
  SchemaGrammar get schemaGrammar;

  /// `name type modifiers` of [column] (nullability, default, comment where
  /// inline, auto increment).
  String getColumnDeclarationSQL(Column column);

  /// The SQL type of [column] (`varchar(40)`, `numeric(10, 2)`, ...).
  String getColumnTypeDeclarationSQL(Column column);

  /// The statements that turn [TableDiff.oldTable] into the new table.
  List<String> getAlterTableSQL(TableDiff diff);

  /// Database type (lower case) -> column type name of the schema objects.
  @protected
  Map<String, String> get defaultTypeMappings;

  @protected
  KeywordList createReservedKeywordsList();

  /// The schema manager (introspection) for [connection].
  AbstractSchemaManager createSchemaManager(Connection connection);

  /// Position of [substring] in [string] (from 1; 0 when absent).
  String getLocateExpression(String string, String substring, [String? start]);

  /// Days between two dates (`date1 - date2`).
  String getDateDiffExpression(String date1, String date2);

  /// `date operator interval unit`.
  @protected
  String getDateArithmeticIntervalExpression(
      String date, String operator, String interval, DateIntervalUnit unit);

  String getCurrentDatabaseExpression();

  /// SQL that lists the views of [database].
  String getListViewsSQL(String database);

  /// SQL that sets the isolation level of the session.
  String getSetTransactionIsolationSQL(TransactionIsolationLevel level);

  // ------------------------------------------------------------ features

  bool supportsSequences() => false;
  bool supportsIdentityColumns() => false;
  bool supportsPartialIndexes() => false;
  bool supportsColumnLengthIndexes() => false;
  bool supportsSavepoints() => true;
  bool supportsReleaseSavepoints() => supportsSavepoints();
  bool supportsSchemas() => false;
  bool supportsInlineColumnComments() => false;
  bool supportsCommentOnStatement() => false;
  bool supportsColumnCollation() => false;

  /// `DEFERRABLE [INITIALLY DEFERRED]` on foreign keys.
  bool supportsDeferrableConstraints() => false;

  /// `MATCH FULL | PARTIAL | SIMPLE` on foreign keys.
  bool supportsForeignKeyMatch() => false;

  /// The schema used for unqualified names (`public` on PostgreSQL).
  String? getDefaultSchemaName() => null;

  int getMaxIdentifierLength() => 63;

  // ------------------------------------------------------------- quoting

  /// Quotes an identifier; each part of `schema.table` separately.
  String quoteIdentifier(String identifier) {
    if (identifier.contains('.')) {
      return identifier.split('.').map(quoteSingleIdentifier).join('.');
    }
    return quoteSingleIdentifier(identifier);
  }

  /// Quotes one identifier (`"name"`; MySQL uses backticks).
  String quoteSingleIdentifier(String identifier) =>
      '"${identifier.replaceAll('"', '""')}"';

  String quoteStringLiteral(String value) =>
      "'${value.replaceAll("'", "''")}'";

  KeywordList getReservedKeywordsList() =>
      _keywords ??= createReservedKeywordsList();

  String _quoteColumns(Iterable<String> columns) =>
      columns.map(quoteIdentifier).join(', ');

  // --------------------------------------------------------------- types

  /// The column type name for database type [dbType].
  String getDoctrineTypeMapping(String dbType) {
    final type = dbType.toLowerCase();
    final mapped = _typeMappingOverrides?[type] ?? defaultTypeMappings[type];
    if (mapped == null) {
      throw InvalidArgumentException(
          'Unknown database type "$type" requested for platform $runtimeType.');
    }
    return mapped;
  }

  bool hasDoctrineTypeMappingFor(String dbType) {
    final type = dbType.toLowerCase();
    return (_typeMappingOverrides?.containsKey(type) ?? false) ||
        defaultTypeMappings.containsKey(type);
  }

  /// Maps database type [dbType] to [type] (e.g. an extension type).
  void registerDoctrineTypeMapping(String dbType, String type) {
    (_typeMappingOverrides ??= {})[dbType.toLowerCase()] = type;
  }

  /// The SQL type for [type] with the options of [column] (`length`,
  /// `fixed`, `precision`, `scale`, `autoincrement`, `unsigned`, `values`).
  String getTypeDeclarationSQL(String type, Map<String, dynamic> column) {
    final options = Map<String, dynamic>.from(column)..remove('name');
    if (options.containsKey('autoincrement')) {
      options['autoIncrement'] = options.remove('autoincrement');
    }
    if (options.containsKey('values')) {
      options['allowed'] = options.remove('values');
    }
    return getColumnTypeDeclarationSQL(
        Column(column['name'] as String? ?? 'column', type, options: options));
  }

  String getBooleanTypeDeclarationSQL(Map<String, dynamic> column) =>
      getTypeDeclarationSQL('boolean', column);

  String getIntegerTypeDeclarationSQL(Map<String, dynamic> column) =>
      getTypeDeclarationSQL('integer', column) +
      getCommonIntegerTypeDeclarationSQL(column);

  String getBigIntTypeDeclarationSQL(Map<String, dynamic> column) =>
      getTypeDeclarationSQL('bigInteger', column) +
      getCommonIntegerTypeDeclarationSQL(column);

  String getSmallIntTypeDeclarationSQL(Map<String, dynamic> column) =>
      getTypeDeclarationSQL('smallInteger', column) +
      getCommonIntegerTypeDeclarationSQL(column);

  /// What follows an integer type (MySQL: `UNSIGNED`, `AUTO_INCREMENT`).
  String getCommonIntegerTypeDeclarationSQL(Map<String, dynamic> column) => '';

  String getStringTypeDeclarationSQL(Map<String, dynamic> column) {
    final fixed = column['fixed'] == true;
    if (!fixed && column['length'] == null) {
      throw ColumnLengthRequiredException('VARCHAR');
    }
    return getTypeDeclarationSQL(fixed ? 'char' : 'string', column);
  }

  String getAsciiStringTypeDeclarationSQL(Map<String, dynamic> column) =>
      getStringTypeDeclarationSQL(column);

  String getBinaryTypeDeclarationSQL(Map<String, dynamic> column) =>
      getTypeDeclarationSQL('binary', column);

  String getBlobTypeDeclarationSQL(Map<String, dynamic> column) =>
      getTypeDeclarationSQL('binary', column);

  String getClobTypeDeclarationSQL(Map<String, dynamic> column) =>
      getTypeDeclarationSQL('text', column);

  String getJsonTypeDeclarationSQL(Map<String, dynamic> column) =>
      getTypeDeclarationSQL('json', column);

  String getGuidTypeDeclarationSQL(Map<String, dynamic> column) =>
      getTypeDeclarationSQL('uuid', column);

  String getEnumDeclarationSQL(Map<String, dynamic> column) {
    final values = column['values'];
    if (values is! List || values.isEmpty) {
      throw ColumnValuesRequiredException('ENUM');
    }
    return getTypeDeclarationSQL('enum', column);
  }

  String getDateTimeTypeDeclarationSQL(Map<String, dynamic> column) =>
      getTypeDeclarationSQL('dateTime', column);

  String getDateTimeTzTypeDeclarationSQL(Map<String, dynamic> column) =>
      getTypeDeclarationSQL('dateTimeTz', column);

  String getDateTypeDeclarationSQL(Map<String, dynamic> column) =>
      getTypeDeclarationSQL('date', column);

  String getTimeTypeDeclarationSQL(Map<String, dynamic> column) =>
      getTypeDeclarationSQL('time', column);

  String getFloatDeclarationSQL(Map<String, dynamic> column) =>
      getTypeDeclarationSQL('double', column);

  String getSmallFloatDeclarationSQL(Map<String, dynamic> column) =>
      getTypeDeclarationSQL('float', column);

  String getDecimalTypeDeclarationSQL(Map<String, dynamic> column) =>
      getTypeDeclarationSQL('decimal', column);

  // --------------------------------------------------------- expressions

  String getRegexpExpression() =>
      throw NotSupported('${runtimeType}.getRegexpExpression');

  String getLengthExpression(String string) => 'LENGTH($string)';

  String getModExpression(String dividend, String divisor) =>
      'MOD($dividend, $divisor)';

  String getTrimExpression(String str,
      [TrimMode mode = TrimMode.UNSPECIFIED, String? char]) {
    final tokens = <String>[
      if (mode != TrimMode.UNSPECIFIED) mode.name,
      if (char != null) char,
    ];
    if (tokens.isNotEmpty) tokens.add('FROM');
    tokens.add(str);
    return 'TRIM(${tokens.join(' ')})';
  }

  String getSubstringExpression(String string, String start, [String? length]) =>
      length == null
          ? 'SUBSTRING($string FROM $start)'
          : 'SUBSTRING($string FROM $start FOR $length)';

  String getConcatExpression(List<String> strings) => strings.join(' || ');

  String getDateAddSecondsExpression(String date, String seconds) =>
      getDateArithmeticIntervalExpression(
          date, '+', seconds, DateIntervalUnit.SECOND);
  String getDateSubSecondsExpression(String date, String seconds) =>
      getDateArithmeticIntervalExpression(
          date, '-', seconds, DateIntervalUnit.SECOND);
  String getDateAddMinutesExpression(String date, String minutes) =>
      getDateArithmeticIntervalExpression(
          date, '+', minutes, DateIntervalUnit.MINUTE);
  String getDateSubMinutesExpression(String date, String minutes) =>
      getDateArithmeticIntervalExpression(
          date, '-', minutes, DateIntervalUnit.MINUTE);
  String getDateAddHourExpression(String date, String hours) =>
      getDateArithmeticIntervalExpression(
          date, '+', hours, DateIntervalUnit.HOUR);
  String getDateSubHourExpression(String date, String hours) =>
      getDateArithmeticIntervalExpression(
          date, '-', hours, DateIntervalUnit.HOUR);
  String getDateAddDaysExpression(String date, String days) =>
      getDateArithmeticIntervalExpression(
          date, '+', days, DateIntervalUnit.DAY);
  String getDateSubDaysExpression(String date, String days) =>
      getDateArithmeticIntervalExpression(
          date, '-', days, DateIntervalUnit.DAY);
  String getDateAddWeeksExpression(String date, String weeks) =>
      getDateArithmeticIntervalExpression(
          date, '+', weeks, DateIntervalUnit.WEEK);
  String getDateSubWeeksExpression(String date, String weeks) =>
      getDateArithmeticIntervalExpression(
          date, '-', weeks, DateIntervalUnit.WEEK);
  String getDateAddMonthExpression(String date, String months) =>
      getDateArithmeticIntervalExpression(
          date, '+', months, DateIntervalUnit.MONTH);
  String getDateSubMonthExpression(String date, String months) =>
      getDateArithmeticIntervalExpression(
          date, '-', months, DateIntervalUnit.MONTH);
  String getDateAddQuartersExpression(String date, String quarters) =>
      getDateArithmeticIntervalExpression(
          date, '+', quarters, DateIntervalUnit.QUARTER);
  String getDateSubQuartersExpression(String date, String quarters) =>
      getDateArithmeticIntervalExpression(
          date, '-', quarters, DateIntervalUnit.QUARTER);
  String getDateAddYearsExpression(String date, String years) =>
      getDateArithmeticIntervalExpression(
          date, '+', years, DateIntervalUnit.YEAR);
  String getDateSubYearsExpression(String date, String years) =>
      getDateArithmeticIntervalExpression(
          date, '-', years, DateIntervalUnit.YEAR);

  @protected
  String multiplyInterval(String interval, int multiplier) =>
      '($interval * $multiplier)';

  String getBitAndComparisonExpression(String value1, String value2) =>
      '($value1 & $value2)';

  String getBitOrComparisonExpression(String value1, String value2) =>
      '($value1 | $value2)';

  String getCurrentDateSQL() => 'CURRENT_DATE';
  String getCurrentTimeSQL() => 'CURRENT_TIME';
  String getCurrentTimestampSQL() => 'CURRENT_TIMESTAMP';

  /// Lock hints inside FROM (SQL Server); the other platforms use
  /// `FOR UPDATE`/`FOR SHARE` at the end of the query.
  String appendLockHint(String fromClause, LockMode lockMode) => fromClause;

  // -------------------------------------------------------- create table

  /// CREATE TABLE plus its indexes, comments and foreign keys.
  List<String> getCreateTableSQL(Table table) =>
      _buildCreateTableSQL(table, createForeignKeys: true);

  /// Creates [tables] first and adds their foreign keys afterwards, so
  /// tables can reference each other in any order.
  List<String> getCreateTablesSQL(List<Table> tables) {
    final sql = <String>[
      for (final table in tables)
        ..._buildCreateTableSQL(table, createForeignKeys: false),
    ];
    for (final table in tables) {
      for (final foreignKey in table.getForeignKeys()) {
        sql.add(getCreateForeignKeySQL(foreignKey, table.getName()));
      }
    }
    return sql;
  }

  /// Drops the foreign keys of [tables] first, then the tables.
  List<String> getDropTablesSQL(List<Table> tables) => [
        for (final table in tables)
          for (final foreignKey in table.getForeignKeys())
            getDropForeignKeySQL(foreignKey.getName(), table.getName()),
        for (final table in tables) getDropTableSQL(table.getName()),
      ];

  List<String> _buildCreateTableSQL(Table table,
      {required bool createForeignKeys}) {
    if (table.getColumns().isEmpty) {
      throw NoColumnsSpecifiedForTable(table.getName());
    }
    final tableName = table.getName();
    final definitions = <String>[
      for (final column in table.getColumns()) getColumnDeclarationSQL(column),
    ];
    final primaryKey = table.getPrimaryKey();
    if (primaryKey != null) {
      definitions.add('PRIMARY KEY (${_quoteColumns(primaryKey.getColumns())})');
    }
    for (final constraint in table.getUniqueConstraints()) {
      definitions.add(getUniqueConstraintDeclarationSQL(constraint));
    }

    final sql = <String>[
      '${getCreateTableKeywordSQL(table)} ${quoteIdentifier(tableName)} '
          '(${definitions.join(', ')})${getCreateTableOptionsSQL(table)}',
      for (final index in table.getIndexes())
        if (!index.isPrimary) getCreateIndexSQL(index, tableName),
    ];

    if (supportsCommentOnStatement()) {
      final comment = table.getComment();
      if (comment != null && comment.isNotEmpty) {
        sql.add(getCommentOnTableSQL(tableName, comment));
      }
      for (final column in table.getColumns()) {
        final columnComment = column.comment;
        if (columnComment != null && columnComment.isNotEmpty) {
          sql.add(getCommentOnColumnSQL(
              tableName, column.getName(), columnComment));
        }
      }
    }

    if (createForeignKeys) {
      for (final foreignKey in table.getForeignKeys()) {
        sql.add(getCreateForeignKeySQL(foreignKey, tableName));
      }
    }
    return sql;
  }

  /// `CREATE TABLE` (PostgreSQL: `CREATE UNLOGGED TABLE` when the table has
  /// the `unlogged` option).
  @protected
  String getCreateTableKeywordSQL(Table table) => 'CREATE TABLE';

  /// What follows the column list (MySQL: engine, charset, comment).
  @protected
  String getCreateTableOptionsSQL(Table table) => '';

  String getCreateTemporaryTableSnippetSQL() => 'CREATE TEMPORARY TABLE';

  String getTemporaryTableName(String tableName) => tableName;

  String getCommentOnTableSQL(String tableName, String comment) =>
      'COMMENT ON TABLE ${quoteIdentifier(tableName)} IS '
      '${quoteStringLiteral(comment)}';

  String getCommentOnColumnSQL(
          String tableName, String columnName, String comment) =>
      'COMMENT ON COLUMN ${quoteIdentifier(tableName)}.'
      '${quoteSingleIdentifier(columnName)} IS ${quoteStringLiteral(comment)}';

  String getInlineColumnCommentSQL(String comment) {
    if (!supportsInlineColumnComments()) {
      throw NotSupported('${runtimeType}.getInlineColumnCommentSQL');
    }
    return 'COMMENT ${quoteStringLiteral(comment)}';
  }

  // -------------------------------------------- indexes and constraints

  String getCreateIndexSQL(Index index, String table) {
    final columns = index.getColumns();
    if (columns.isEmpty) {
      throw InvalidArgumentException(
          'Index "${index.getName()}" on "$table" has no columns.');
    }
    if (index.isPrimary) return getCreatePrimaryKeySQL(index, table);
    return 'CREATE ${getCreateIndexSQLFlags(index)}INDEX '
        '${quoteIdentifier(index.getName())} ON ${quoteIdentifier(table)} '
        '(${_quoteColumns(columns)})${getPartialIndexSQL(index)}';
  }

  /// `UNIQUE ` (MySQL also `FULLTEXT `/`SPATIAL ` from the index flags).
  @protected
  String getCreateIndexSQLFlags(Index index) => index.isUnique ? 'UNIQUE ' : '';

  /// ` WHERE ...` of a partial index (when supported).
  @protected
  String getPartialIndexSQL(Index index) =>
      supportsPartialIndexes() && index.hasOption('where')
          ? ' WHERE ${index.getOption('where')}'
          : '';

  String getCreatePrimaryKeySQL(Index index, String table) =>
      'ALTER TABLE ${quoteIdentifier(table)} '
      'ADD PRIMARY KEY (${_quoteColumns(index.getColumns())})';

  /// `CONSTRAINT name UNIQUE (columns)`.
  String getUniqueConstraintDeclarationSQL(UniqueConstraint constraint) {
    final columns = constraint.getColumns();
    if (columns.isEmpty) {
      throw InvalidArgumentException(
          'Unique constraint "${constraint.getName()}" has no columns.');
    }
    return 'CONSTRAINT ${quoteIdentifier(constraint.getName())} '
        'UNIQUE (${_quoteColumns(columns)})';
  }

  String getCreateUniqueConstraintSQL(
          UniqueConstraint constraint, String table) =>
      'ALTER TABLE ${quoteIdentifier(table)} '
      'ADD ${getUniqueConstraintDeclarationSQL(constraint)}';

  String getCreateForeignKeySQL(ForeignKeyConstraint foreignKey, String table) =>
      'ALTER TABLE ${quoteIdentifier(table)} '
      'ADD ${getForeignKeyDeclarationSQL(foreignKey)}';

  String getForeignKeyDeclarationSQL(ForeignKeyConstraint foreignKey) =>
      getForeignKeyBaseDeclarationSQL(foreignKey) +
      getAdvancedForeignKeyOptionsSQL(foreignKey);

  /// `CONSTRAINT name FOREIGN KEY (local) REFERENCES table (foreign)`.
  String getForeignKeyBaseDeclarationSQL(ForeignKeyConstraint foreignKey) {
    final local = foreignKey.getLocalColumns();
    final foreign = foreignKey.getForeignColumns();
    if (local.isEmpty || foreign.isEmpty) {
      throw InvalidArgumentException(
          'Foreign key "${foreignKey.getName()}" needs local and foreign columns.');
    }
    return 'CONSTRAINT ${quoteIdentifier(foreignKey.getName())} '
        'FOREIGN KEY (${_quoteColumns(local)}) '
        'REFERENCES ${quoteIdentifier(foreignKey.getForeignTableName())} '
        '(${_quoteColumns(foreign)})';
  }

  /// ` MATCH ...`, ` ON UPDATE ...`, ` ON DELETE ...` and
  /// ` DEFERRABLE [INITIALLY DEFERRED]` from the foreign key options
  /// (`match`, `onUpdate`, `onDelete`, `deferrable`, `deferred`); the ones
  /// the platform does not support are left out.
  String getAdvancedForeignKeyOptionsSQL(ForeignKeyConstraint foreignKey) {
    final sql = StringBuffer();
    if (supportsForeignKeyMatch() && foreignKey.hasOption('match')) {
      final match = foreignKey.getOption('match').toString().toUpperCase();
      if (!const {'FULL', 'PARTIAL', 'SIMPLE'}.contains(match)) {
        throw InvalidArgumentException('Invalid foreign key MATCH "$match".');
      }
      if (match != 'SIMPLE') sql.write(' MATCH $match');
    }
    final onUpdate = foreignKey.getOnUpdate();
    if (onUpdate != null && onUpdate.toUpperCase() != 'NO ACTION') {
      sql.write(' ON UPDATE ${getForeignKeyReferentialActionSQL(onUpdate)}');
    }
    final onDelete = foreignKey.getOnDelete();
    if (onDelete != null && onDelete.toUpperCase() != 'NO ACTION') {
      sql.write(' ON DELETE ${getForeignKeyReferentialActionSQL(onDelete)}');
    }
    if (supportsDeferrableConstraints() &&
        foreignKey.getOption('deferrable') == true) {
      sql.write(' DEFERRABLE');
      if (foreignKey.getOption('deferred') == true) {
        sql.write(' INITIALLY DEFERRED');
      }
    }
    return sql.toString();
  }

  String getForeignKeyReferentialActionSQL(String action) {
    final upper = action.toUpperCase();
    const valid = {'CASCADE', 'SET NULL', 'NO ACTION', 'RESTRICT', 'SET DEFAULT'};
    if (!valid.contains(upper)) {
      throw InvalidArgumentException('Invalid foreign key action "$action".');
    }
    return upper;
  }

  // ---------------------------------------------------------------- drop

  String getDropTableSQL(String table) => 'DROP TABLE ${quoteIdentifier(table)}';

  String getDropTemporaryTableSQL(String table) => getDropTableSQL(table);

  String getDropIndexSQL(String name, String table) =>
      'DROP INDEX ${quoteIdentifier(name)}';

  @protected
  String getDropConstraintSQL(String name, String table) =>
      'ALTER TABLE ${quoteIdentifier(table)} '
      'DROP CONSTRAINT ${quoteIdentifier(name)}';

  String getDropForeignKeySQL(String foreignKey, String table) =>
      getDropConstraintSQL(foreignKey, table);

  String getDropUniqueConstraintSQL(String name, String table) =>
      getDropConstraintSQL(name, table);

  String getTruncateTableSQL(String table, {bool cascade = false}) =>
      'TRUNCATE ${quoteIdentifier(table)}';

  // -------------------------------------------------------------- rename

  List<String> getRenameTableSQL(String oldName, String newName) => [
        'ALTER TABLE ${quoteIdentifier(oldName)} '
            'RENAME TO ${quoteSingleIdentifier(newName)}'
      ];

  List<String> getRenameColumnSQL(
          String table, String oldColumnName, String newColumnName) =>
      [
        'ALTER TABLE ${quoteIdentifier(table)} '
            'RENAME COLUMN ${quoteSingleIdentifier(oldColumnName)} '
            'TO ${quoteSingleIdentifier(newColumnName)}'
      ];

  /// Renames an index (default: drop and create it again).
  List<String> getRenameIndexSQL(String oldName, Index index, String table) =>
      [getDropIndexSQL(oldName, table), getCreateIndexSQL(index, table)];

  // ----------------------------------------------- sequences and schemas

  String getCreateSequenceSQL(Sequence sequence) =>
      throw NotSupported('${runtimeType}.getCreateSequenceSQL');

  String getAlterSequenceSQL(Sequence sequence) =>
      throw NotSupported('${runtimeType}.getAlterSequenceSQL');

  String getDropSequenceSQL(String name) {
    if (!supportsSequences()) {
      throw NotSupported('${runtimeType}.getDropSequenceSQL');
    }
    return 'DROP SEQUENCE ${quoteIdentifier(name)}';
  }

  String getSequenceNextValSQL(String sequence) =>
      throw NotSupported('${runtimeType}.getSequenceNextValSQL');

  String getListSequencesSQL(String database) =>
      throw NotSupported('${runtimeType}.getListSequencesSQL');

  String getCreateSchemaSQL(String schemaName) {
    if (!supportsSchemas()) {
      throw NotSupported('${runtimeType}.getCreateSchemaSQL');
    }
    return 'CREATE SCHEMA ${quoteSingleIdentifier(schemaName)}';
  }

  String getDropSchemaSQL(String schemaName) {
    if (!supportsSchemas()) {
      throw NotSupported('${runtimeType}.getDropSchemaSQL');
    }
    return 'DROP SCHEMA ${quoteSingleIdentifier(schemaName)}';
  }

  /// Everything [schema] needs: its namespaces, sequences (except the ones
  /// backing an auto-increment column), tables and foreign keys.
  List<String> getCreateSchemaObjectsSQL(Schema schema) {
    final defaultNamespace = getDefaultSchemaName();
    return [
      if (supportsSchemas())
        for (final namespace in schema.getNamespaces())
          if (defaultNamespace == null ||
              namespace.toLowerCase() != defaultNamespace.toLowerCase())
            getCreateSchemaSQL(namespace),
      if (supportsSequences())
        for (final sequence in schema.getSequences())
          if (!schema.getTables().any(sequence.isAutoIncrementsFor))
            getCreateSequenceSQL(sequence),
      ...getCreateTablesSQL(schema.getTables()),
    ];
  }

  /// Drops the foreign keys, tables and sequences of [schema].
  List<String> getDropSchemaObjectsSQL(Schema schema) => [
        ...getDropTablesSQL(schema.getTables()),
        if (supportsSequences())
          for (final sequence in schema.getSequences())
            if (!schema.getTables().any(sequence.isAutoIncrementsFor))
              getDropSequenceSQL(sequence.getName()),
      ];

  /// The statements that apply [diff]: new namespaces and sequences, new
  /// tables, altered tables, dropped tables, sequences and namespaces.
  List<String> getAlterSchemaSQL(SchemaDiff diff) => [
        if (supportsSchemas())
          for (final namespace in diff.getCreatedSchemas())
            getCreateSchemaSQL(namespace),
        if (supportsSequences()) ...[
          for (final sequence in diff.getCreatedSequences())
            getCreateSequenceSQL(sequence),
          for (final sequence in diff.getAlteredSequences())
            getAlterSequenceSQL(sequence),
        ],
        ...getCreateTablesSQL(diff.getCreatedTables()),
        for (final tableDiff in diff.getAlteredTables())
          ...getAlterTableSQL(tableDiff),
        ...getDropTablesSQL(diff.getDroppedTables()),
        if (supportsSequences())
          for (final sequence in diff.getDroppedSequences())
            getDropSequenceSQL(sequence.getName()),
        if (supportsSchemas())
          for (final namespace in diff.getDroppedSchemas())
            getDropSchemaSQL(namespace),
      ];

  // ------------------------------------------------- views and databases

  String getCreateViewSQL(String name, String sql) =>
      'CREATE VIEW ${quoteIdentifier(name)} AS $sql';

  String getDropViewSQL(String name) => 'DROP VIEW ${quoteIdentifier(name)}';

  String getCreateDatabaseSQL(String name) =>
      'CREATE DATABASE ${quoteSingleIdentifier(name)}';

  String getDropDatabaseSQL(String name) =>
      'DROP DATABASE ${quoteSingleIdentifier(name)}';

  String getListDatabasesSQL() =>
      throw NotSupported('${runtimeType}.getListDatabasesSQL');

  // -------------------------------------------------------- transactions

  String getTransactionIsolationLevelSQL(TransactionIsolationLevel level) =>
      switch (level) {
        TransactionIsolationLevel.READ_UNCOMMITTED => 'READ UNCOMMITTED',
        TransactionIsolationLevel.READ_COMMITTED => 'READ COMMITTED',
        TransactionIsolationLevel.REPEATABLE_READ => 'REPEATABLE READ',
        TransactionIsolationLevel.SERIALIZABLE => 'SERIALIZABLE',
      };

  TransactionIsolationLevel getDefaultTransactionIsolationLevel() =>
      TransactionIsolationLevel.READ_COMMITTED;

  String createSavePoint(String savepoint) => 'SAVEPOINT $savepoint';
  String releaseSavePoint(String savepoint) => 'RELEASE SAVEPOINT $savepoint';
  String rollbackSavePoint(String savepoint) =>
      'ROLLBACK TO SAVEPOINT $savepoint';

  // --------------------------------------------------------------- misc

  /// Adds LIMIT/OFFSET to [query].
  String modifyLimitQuery(String query, int? limit, [int offset = 0]) {
    if (offset < 0) {
      throw InvalidArgumentException(
          'Offset must be a positive integer or zero, $offset given.');
    }
    return doModifyLimitQuery(query, limit, offset);
  }

  @protected
  String doModifyLimitQuery(String query, int? limit, int offset) {
    var sql = query;
    if (limit != null) sql += ' LIMIT $limit';
    if (offset > 0) sql += ' OFFSET $offset';
    return sql;
  }

  String getDummySelectSQL([String expression = '1']) => 'SELECT $expression';

  /// `INSERT INTO table (identity) VALUES (DEFAULT)`.
  String getEmptyIdentityInsertSQL(
          String quotedTableName, String quotedIdentifierColumnName) =>
      'INSERT INTO $quotedTableName ($quotedIdentifierColumnName) '
      'VALUES (DEFAULT)';

  /// Escapes the LIKE wildcards (and [escapeChar]) in [inputString].
  String escapeStringForLike(String inputString, String escapeChar) {
    final special = RegExp(
        '[${RegExp.escape(getLikeWildcardCharacters() + escapeChar)}]');
    return inputString.replaceAllMapped(
        special, (match) => '$escapeChar${match.group(0)}');
  }

  @protected
  String getLikeWildcardCharacters() => '%_';

  /// Booleans as the database expects them (true/false; MySQL 1/0).
  dynamic convertBooleans(dynamic item) {
    if (item is List) return item.map(convertBooleans).toList();
    return item;
  }

  dynamic convertBooleansToDatabaseValue(dynamic item) => convertBooleans(item);

  bool? convertFromBoolean(dynamic item) {
    if (item == null) return null;
    if (item is bool) return item;
    if (item is num) return item != 0;
    final text = item.toString().toLowerCase();
    return text == 't' || text == 'true' || text == '1' || text == 'y';
  }

  String getDateTimeFormatString() => 'yyyy-MM-dd HH:mm:ss';
  String getDateTimeTzFormatString() => 'yyyy-MM-dd HH:mm:ss';
  String getDateFormatString() => 'yyyy-MM-dd';
  String getTimeFormatString() => 'HH:mm:ss';

  String getUnionAllSQL() => 'UNION ALL';
  String getUnionDistinctSQL() => 'UNION';
  String getUnionSelectPartSQL(String subQuery) => subQuery;
}
