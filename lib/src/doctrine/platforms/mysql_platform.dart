import '../../connection.dart';
import '../../schema/blueprint.dart';
import '../../schema/grammars/schema_grammar.dart';
import '../../schema/grammars/schema_mysql_grammar.dart';
import '../schema/abstract_schema_manager.dart';
import '../schema/column.dart';
import '../schema/index.dart';
import '../schema/mysql_schema_manager.dart';
import '../schema/table.dart';
import '../schema/table_diff.dart';
import '../transaction_isolation_level.dart';
import 'abstract_platform.dart';
import 'keywords/keyword_list.dart';
import 'keywords/mariadb_keywords.dart';
import 'keywords/mysql_keywords.dart';

/// MySQL. Corresponds to Doctrine\DBAL\Platforms\MySQLPlatform.
class MySQLPlatform extends AbstractPlatform {
  final _MySqlPlatformGrammar _grammar = _MySqlPlatformGrammar();

  @override
  SchemaGrammar get schemaGrammar => _grammar;

  @override
  String getColumnDeclarationSQL(Column column) =>
      _grammar.columnDeclaration(column);

  @override
  String getColumnTypeDeclarationSQL(Column column) =>
      _grammar.columnType(column);

  @override
  List<String> getAlterTableSQL(TableDiff diff) => _grammar.tableDiff(diff);

  @override
  bool supportsIdentityColumns() => true;
  @override
  bool supportsInlineColumnComments() => true;
  @override
  bool supportsColumnCollation() => true;
  @override
  bool supportsColumnLengthIndexes() => true;

  @override
  int getMaxIdentifierLength() => 64;

  @override
  String quoteSingleIdentifier(String identifier) =>
      '`${identifier.replaceAll('`', '``')}`';

  @override
  KeywordList createReservedKeywordsList() => MySqlKeywords();

  @override
  AbstractSchemaManager createSchemaManager(Connection connection) =>
      MySqlSchemaManager(connection);

  @override
  Map<String, String> get defaultTypeMappings => const {
        'tinyint': 'boolean',
        'smallint': 'smallinteger',
        'mediumint': 'integer',
        'int': 'integer',
        'integer': 'integer',
        'bigint': 'biginteger',
        'char': 'char',
        'varchar': 'string',
        'tinytext': 'text',
        'text': 'text',
        'mediumtext': 'text',
        'longtext': 'text',
        'float': 'float',
        'double': 'double',
        'real': 'double',
        'decimal': 'decimal',
        'numeric': 'decimal',
        'date': 'date',
        'datetime': 'datetime',
        'timestamp': 'timestamp',
        'time': 'time',
        'year': 'date',
        'enum': 'enum',
        'set': 'string',
        'json': 'json',
        'binary': 'binary',
        'varbinary': 'binary',
        'tinyblob': 'binary',
        'blob': 'binary',
        'mediumblob': 'binary',
        'longblob': 'binary',
      };

  @override
  String getCommonIntegerTypeDeclarationSQL(Map<String, dynamic> column) {
    final sql = StringBuffer();
    if (column['unsigned'] == true) sql.write(' UNSIGNED');
    if (column['autoincrement'] == true || column['autoIncrement'] == true) {
      sql.write(' AUTO_INCREMENT');
    }
    return sql.toString();
  }

  @override
  String getRegexpExpression() => 'RLIKE';

  @override
  String getConcatExpression(List<String> strings) =>
      'CONCAT(${strings.join(', ')})';

  @override
  String getLocateExpression(String string, String substring,
          [String? start]) =>
      start == null
          ? 'LOCATE($substring, $string)'
          : 'LOCATE($substring, $string, $start)';

  @override
  String getDateDiffExpression(String date1, String date2) =>
      'DATEDIFF($date1, $date2)';

  @override
  String getDateArithmeticIntervalExpression(
      String date, String operator, String interval, DateIntervalUnit unit) {
    final function = operator == '+' ? 'DATE_ADD' : 'DATE_SUB';
    return '$function($date, INTERVAL $interval ${unit.name})';
  }

  @override
  String getCurrentDatabaseExpression() => 'DATABASE()';

  @override
  String getListViewsSQL(String database) =>
      'SELECT * FROM information_schema.VIEWS '
      'WHERE TABLE_SCHEMA = ${quoteStringLiteral(database)}';

  @override
  String getListDatabasesSQL() => 'SHOW DATABASES';

  @override
  String getSetTransactionIsolationSQL(TransactionIsolationLevel level) =>
      'SET SESSION TRANSACTION ISOLATION LEVEL '
      '${getTransactionIsolationLevelSQL(level)}';

  @override
  TransactionIsolationLevel getDefaultTransactionIsolationLevel() =>
      TransactionIsolationLevel.REPEATABLE_READ;

  /// `ENGINE`, `CHARSET`, `COLLATE` and `COMMENT` from the table options.
  @override
  String getCreateTableOptionsSQL(Table table) {
    final sql = StringBuffer();
    final engine = table.getOption('engine');
    if (engine != null) sql.write(' ENGINE = $engine');
    final charset = table.getOption('charset');
    if (charset != null) sql.write(' DEFAULT CHARACTER SET $charset');
    final collation =
        table.getOption('collation') ?? table.getOption('collate');
    if (collation != null) sql.write(' COLLATE $collation');
    final comment = table.getComment();
    if (comment != null && comment.isNotEmpty) {
      sql.write(' COMMENT = ${quoteStringLiteral(comment)}');
    }
    return sql.toString();
  }

  @override
  String getCreateIndexSQLFlags(Index index) {
    if (index.hasFlag('fulltext')) return 'FULLTEXT ';
    if (index.hasFlag('spatial')) return 'SPATIAL ';
    return super.getCreateIndexSQLFlags(index);
  }

  @override
  String getDropIndexSQL(String name, String table) =>
      'DROP INDEX ${quoteIdentifier(name)} ON ${quoteIdentifier(table)}';

  @override
  String getDropForeignKeySQL(String foreignKey, String table) =>
      'ALTER TABLE ${quoteIdentifier(table)} '
      'DROP FOREIGN KEY ${quoteIdentifier(foreignKey)}';

  @override
  String getDropUniqueConstraintSQL(String name, String table) =>
      getDropIndexSQL(name, table);

  @override
  List<String> getRenameTableSQL(String oldName, String newName) => [
        'RENAME TABLE ${quoteIdentifier(oldName)} '
            'TO ${quoteIdentifier(newName)}'
      ];

  @override
  List<String> getRenameIndexSQL(String oldName, Index index, String table) => [
        'ALTER TABLE ${quoteIdentifier(table)} '
            'RENAME INDEX ${quoteIdentifier(oldName)} '
            'TO ${quoteIdentifier(index.getName())}'
      ];

  @override
  String getEmptyIdentityInsertSQL(
          String quotedTableName, String quotedIdentifierColumnName) =>
      'INSERT INTO $quotedTableName () VALUES ()';

  /// MySQL stores booleans as `1`/`0`.
  @override
  dynamic convertBooleans(dynamic item) {
    if (item is List) return item.map(convertBooleans).toList();
    if (item is bool) return item ? 1 : 0;
    return item;
  }
}

/// MariaDB (MySQL syntax with its own reserved words).
class MariaDBPlatform extends MySQLPlatform {
  @override
  KeywordList createReservedKeywordsList() => MariaDbKeywords();
}

/// Exposes the column and diff helpers of the MySQL schema grammar.
class _MySqlPlatformGrammar extends SchemaMySqlGrammar {
  String columnDeclaration(Column column) =>
      getColumnDeclarationSql(column, Blueprint(''));

  String columnType(Column column) => getColumnTypeDeclarationSql(column);

  List<String> tableDiff(TableDiff diff) =>
      compileTableDiff(diff, Blueprint(getTableDiffName(diff)));
}
