import '../../connection.dart';
import '../../schema/blueprint.dart';
import '../../schema/grammars/schema_grammar.dart';
import '../../schema/grammars/schema_postgres_grammar.dart';
import '../schema/abstract_schema_manager.dart';
import '../schema/column.dart';
import '../schema/index.dart';
import '../schema/postgres_schema_manager.dart';
import '../schema/sequence.dart';
import '../schema/table.dart';
import '../schema/table_diff.dart';
import '../transaction_isolation_level.dart';
import 'abstract_platform.dart';
import 'keywords/keyword_list.dart';
import 'keywords/postgresql_keywords.dart';

/// PostgreSQL. Corresponds to Doctrine\DBAL\Platforms\PostgreSQLPlatform.
class PostgreSQLPlatform extends AbstractPlatform {
  final _PostgresPlatformGrammar _grammar = _PostgresPlatformGrammar();

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
  bool supportsSequences() => true;
  @override
  bool supportsIdentityColumns() => true;
  @override
  bool supportsPartialIndexes() => true;
  @override
  bool supportsSchemas() => true;
  @override
  bool supportsCommentOnStatement() => true;
  @override
  bool supportsColumnCollation() => true;
  @override
  bool supportsDeferrableConstraints() => true;
  @override
  bool supportsForeignKeyMatch() => true;
  @override
  String? getDefaultSchemaName() => 'public';

  @override
  KeywordList createReservedKeywordsList() => PostgreSQLKeywords();

  @override
  AbstractSchemaManager createSchemaManager(Connection connection) =>
      PostgreSQLSchemaManager(connection);

  @override
  Map<String, String> get defaultTypeMappings => const {
        'smallint': 'smallinteger',
        'int2': 'smallinteger',
        'serial2': 'smallinteger',
        'smallserial': 'smallinteger',
        'integer': 'integer',
        'int': 'integer',
        'int4': 'integer',
        'serial': 'integer',
        'serial4': 'integer',
        'bigint': 'biginteger',
        'int8': 'biginteger',
        'bigserial': 'biginteger',
        'serial8': 'biginteger',
        'boolean': 'boolean',
        'bool': 'boolean',
        'character varying': 'string',
        'varchar': 'string',
        'interval': 'string',
        'character': 'char',
        'char': 'char',
        'bpchar': 'char',
        'text': 'text',
        'numeric': 'decimal',
        'decimal': 'decimal',
        'money': 'decimal',
        'real': 'float',
        'float4': 'float',
        'double precision': 'double',
        'float8': 'double',
        'date': 'date',
        'time': 'time',
        'timetz': 'timetz',
        'timestamp': 'timestamp',
        'timestamptz': 'timestamptz',
        'bytea': 'binary',
        'uuid': 'uuid',
        'json': 'json',
        'jsonb': 'jsonb',
        'inet': 'ipaddress',
        'macaddr': 'macaddress',
      };

  @override
  String getRegexpExpression() => 'SIMILAR TO';

  @override
  String getLocateExpression(String string, String substring, [String? start]) {
    if (start == null) return 'POSITION($substring IN $string)';
    final part = getSubstringExpression(string, start);
    return 'CASE WHEN (POSITION($substring IN $part) = 0) THEN 0 '
        'ELSE (POSITION($substring IN $part) + $start - 1) END';
  }

  @override
  String getDateDiffExpression(String date1, String date2) =>
      '(DATE($date1) - DATE($date2))';

  @override
  String getDateArithmeticIntervalExpression(
      String date, String operator, String interval, DateIntervalUnit unit) {
    var amount = interval;
    var name = unit.name;
    if (unit == DateIntervalUnit.QUARTER) {
      amount = multiplyInterval(interval, 3);
      name = DateIntervalUnit.MONTH.name;
    }
    return "($date $operator ($amount || ' $name')::interval)";
  }

  @override
  String getCurrentDatabaseExpression() => 'CURRENT_DATABASE()';

  @override
  String getListViewsSQL(String database) =>
      'SELECT quote_ident(table_name) AS viewname, table_schema AS schemaname, '
      'view_definition AS definition FROM information_schema.views '
      'WHERE view_definition IS NOT NULL';

  @override
  String getListDatabasesSQL() => 'SELECT datname FROM pg_database';

  @override
  String getListSequencesSQL(String database) =>
      'SELECT sequence_name AS relname, sequence_schema AS schemaname, '
      'minimum_value AS min_value, increment AS increment_by '
      'FROM information_schema.sequences '
      "WHERE sequence_catalog = ${quoteStringLiteral(database)} "
      "AND sequence_schema NOT LIKE 'pg\\_%' "
      "AND sequence_schema <> 'information_schema'";

  @override
  String getSetTransactionIsolationSQL(TransactionIsolationLevel level) =>
      'SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL '
      '${getTransactionIsolationLevelSQL(level)}';

  @override
  String getCreateTableKeywordSQL(Table table) =>
      table.getOption('unlogged') == true
          ? 'CREATE UNLOGGED TABLE'
          : 'CREATE TABLE';

  @override
  String getCreateSequenceSQL(Sequence sequence) =>
      'CREATE SEQUENCE ${quoteIdentifier(sequence.getName())} '
      'INCREMENT BY ${sequence.getCache()} '
      'MINVALUE ${sequence.getInitialValue()} '
      'START ${sequence.getInitialValue()}';

  @override
  String getAlterSequenceSQL(Sequence sequence) =>
      'ALTER SEQUENCE ${quoteIdentifier(sequence.getName())} '
      'INCREMENT BY ${sequence.getCache()}';

  @override
  String getSequenceNextValSQL(String sequence) =>
      "SELECT NEXTVAL(${quoteStringLiteral(sequence)})";

  @override
  String getTruncateTableSQL(String table, {bool cascade = false}) =>
      'TRUNCATE ${quoteIdentifier(table)}${cascade ? ' CASCADE' : ''}';

  @override
  List<String> getRenameIndexSQL(String oldName, Index index, String table) => [
        'ALTER INDEX ${quoteIdentifier(oldName)} '
            'RENAME TO ${quoteSingleIdentifier(index.getName())}'
      ];

  @override
  String getEmptyIdentityInsertSQL(
          String quotedTableName, String quotedIdentifierColumnName) =>
      'INSERT INTO $quotedTableName ($quotedIdentifierColumnName) '
      'VALUES (DEFAULT)';
}

/// Exposes the column and diff helpers of the PostgreSQL schema grammar.
class _PostgresPlatformGrammar extends SchemaPostgresGrammar {
  String columnDeclaration(Column column) =>
      getColumnDeclarationSql(column, Blueprint(''));

  String columnType(Column column) => getColumnTypeDeclarationSql(column);

  List<String> tableDiff(TableDiff diff) =>
      compileTableDiff(diff, Blueprint(getTableDiffName(diff)));
}
