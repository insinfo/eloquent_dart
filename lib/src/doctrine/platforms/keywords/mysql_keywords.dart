// File: lib/src/doctrine/platforms/keywords/mysql_keywords.dart

import 'keyword_list.dart';

/// Reserved keywords list corresponding to the MySQL database platform.
///
/// Provides the list of words reserved by MySQL (based on version 5.7 reference),
/// used to determine if an identifier needs quoting.
class MySqlKeywords extends KeywordList {
  /// {@macro keyword_list.getKeywords}
  ///
  /// Returns the list of reserved words for MySQL 5.7.
  /// Note: Newer MySQL versions might have additional keywords.
  @override
  List<String> getKeywords() {
    // Using const for an immutable list literal, which is efficient.
    // List based on https://dev.mysql.com/doc/refman/5.7/en/keywords.html
    // (and matching the provided PHP array)
    return const [
      'ACCESSIBLE', // Added in 5.7 (for optimizer hints)
      'ADD',
      'ALL',
      'ALTER',
      'ANALYZE',
      'AND',
      'AS',
      'ASC',
      'ASENSITIVE', // Cursor related
      'BEFORE',
      'BETWEEN',
      'BIGINT',
      'BINARY',
      'BLOB',
      'BOTH',
      'BY',
      'CALL',
      'CASCADE',
      'CASE',
      'CHANGE',
      'CHAR',
      'CHARACTER',
      'CHECK',
      'COLLATE',
      'COLUMN',
      'CONDITION',
      'CONSTRAINT',
      'CONTINUE',
      'CONVERT',
      'CREATE',
      'CROSS',
      'CURRENT_DATE',
      'CURRENT_TIME',
      'CURRENT_TIMESTAMP',
      'CURRENT_USER',
      'CURSOR',
      'DATABASE',
      'DATABASES',
      'DAY_HOUR',
      'DAY_MICROSECOND',
      'DAY_MINUTE',
      'DAY_SECOND',
      'DEC',
      'DECIMAL',
      'DECLARE',
      'DEFAULT',
      'DELAYED', // Primarily MyISAM, deprecated/removed later
      'DELETE',
      'DESC',
      'DESCRIBE',
      'DETERMINISTIC',
      'DISTINCT',
      'DISTINCTROW', // Alias for DISTINCT
      'DIV',
      'DOUBLE',
      'DROP',
      'DUAL',
      'EACH',
      'ELSE',
      'ELSEIF',
      'ENCLOSED',
      'ESCAPED',
      'EXISTS',
      'EXIT',
      'EXPLAIN',
      'FALSE',
      'FETCH',
      'FLOAT',
      'FLOAT4', // Alias for FLOAT
      'FLOAT8', // Alias for DOUBLE
      'FOR',
      'FORCE',
      'FOREIGN',
      'FROM',
      'FULLTEXT',
      'GENERATED', // MySQL 5.7+ Generated Columns
      'GET', // Diagnostics area
      'GRANT',
      'GROUP',
      'HAVING',
      'HIGH_PRIORITY',
      'HOUR_MICROSECOND',
      'HOUR_MINUTE',
      'HOUR_SECOND',
      'IF',
      'IGNORE',
      'IN',
      'INDEX',
      'INFILE',
      'INNER',
      'INOUT',
      'INSENSITIVE', // Cursor related
      'INSERT',
      'INT',
      'INT1', // Alias for TINYINT
      'INT2', // Alias for SMALLINT
      'INT3', // Alias for MEDIUMINT
      'INT4', // Alias for INT
      'INT8', // Alias for BIGINT
      'INTEGER',
      'INTERVAL',
      'INTO',
      'IO_AFTER_GTIDS', // Replication related
      'IO_BEFORE_GTIDS', // Replication related
      'IS',
      'ITERATE',
      'JOIN',
      'KEY', // Synonym for INDEX
      'KEYS', // Synonym for INDEXES
      'KILL',
      'LEADING',
      'LEAVE',
      'LEFT',
      'LIKE',
      'LIMIT',
      'LINEAR', // Partitioning related
      'LINES',
      'LOAD',
      'LOCALTIME',
      'LOCALTIMESTAMP',
      'LOCK',
      'LONG',
      'LONGBLOB',
      'LONGTEXT',
      'LOOP',
      'LOW_PRIORITY',
      'MASTER_BIND', // Replication related
      'MASTER_SSL_VERIFY_SERVER_CERT', // Replication related
      'MATCH',
      'MAXVALUE', // Partitioning related
      'MEDIUMBLOB',
      'MEDIUMINT',
      'MEDIUMTEXT',
      'MIDDLEINT', // Alias for MEDIUMINT
      'MINUTE_MICROSECOND',
      'MINUTE_SECOND',
      'MOD',
      'MODIFIES', // Stored Routine characteristic
      'NATURAL',
      'NO_WRITE_TO_BINLOG', // Alias for SQL_LOG_BIN=0
      'NOT',
      'NULL',
      'NUMERIC',
      'ON',
      'OPTIMIZE',
      'OPTIMIZER_COSTS', // Added in 5.7
      'OPTION',
      'OPTIONALLY',
      'OR',
      'ORDER',
      'OUT',
      'OUTER',
      'OUTFILE',
      'PARTITION', // MySQL 5.1+
      'PRECISION',
      'PRIMARY',
      'PROCEDURE',
      'PURGE',
      'RANGE',
      'READ',
      'READ_WRITE',
      'READS', // Stored Routine characteristic
      'REAL', // Alias for DOUBLE
      'REFERENCES',
      'REGEXP',
      'RELEASE',
      'RENAME',
      'REPEAT',
      'REPLACE',
      'REQUIRE',
      'RESIGNAL', // Stored Routine signal handling
      'RESTRICT',
      'RETURN',
      'REVOKE',
      'RIGHT',
      'RLIKE', // Synonym for REGEXP
      'SCHEMA', // Synonym for DATABASE
      'SCHEMAS', // Synonym for DATABASES
      'SECOND_MICROSECOND',
      'SELECT',
      'SENSITIVE', // Cursor related
      'SEPARATOR',
      'SET',
      'SHOW',
      'SIGNAL', // Stored Routine signal handling
      'SMALLINT',
      'SPATIAL',
      'SPECIFIC',
      'SQL',
      'SQL_BIG_RESULT',
      'SQL_CALC_FOUND_ROWS',
      'SQL_SMALL_RESULT',
      'SQLEXCEPTION',
      'SQLSTATE',
      'SQLWARNING',
      'SSL',
      'STARTING',
      'STORED', // Generated Columns
      'STRAIGHT_JOIN',
      'TABLE',
      'TERMINATED',
      'THEN',
      'TINYBLOB',
      'TINYINT',
      'TINYTEXT',
      'TO',
      'TRAILING',
      'TRIGGER',
      'TRUE',
      'UNDO',
      'UNION',
      'UNIQUE',
      'UNLOCK',
      'UNSIGNED',
      'UPDATE',
      'USAGE',
      'USE',
      'USING',
      'UTC_DATE',
      'UTC_TIME',
      'UTC_TIMESTAMP',
      'VALUES',
      'VARBINARY',
      'VARCHAR',
      'VARCHARACTER',
      'VARYING',
      'VIRTUAL', // Generated Columns
      'WHEN',
      'WHERE',
      'WHILE',
      'WITH',
      'WRITE',
      'XOR',
      'YEAR_MONTH',
      'ZEROFILL',
    ];
  }
}