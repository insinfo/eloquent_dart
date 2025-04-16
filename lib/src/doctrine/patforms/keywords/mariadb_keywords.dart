// File: lib/src/doctrine/platforms/keywords/mariadb_keywords.dart

import 'mysql_keywords.dart'; // Import the base class

/// Reserved keywords list corresponding to the MariaDB database platform.
///
/// MariaDB has its own set of reserved words, often a superset of MySQL's.
class MariaDbKeywords extends MySqlKeywords {
  /// {@macro keyword_list.getKeywords}
  ///
  /// Returns the list of reserved words specific to MariaDB.
  /// Overrides the list from MySQLKeywords.
  @override
  List<String> getKeywords() {
    // Using const for an immutable list literal.
    // This list is based on the provided PHP array for MariaDB.
    return const [
      'ACCESSIBLE',
      'ADD',
      'ALL',
      'ALTER',
      'ANALYZE',
      'AND',
      'AS',
      'ASC',
      'ASENSITIVE', // MySQL specific sensitivity modifier
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
      'DELAYED', // Primarily MySQL (MyISAM), often no-op/deprecated in InnoDB/MariaDB
      'DELETE',
      'DESC',
      'DESCRIBE',
      'DETERMINISTIC',
      'DISTINCT',
      'DISTINCTROW', // MySQL alias for DISTINCT
      'DIV', // Integer division operator
      'DOUBLE',
      'DROP',
      'DUAL', // Dummy table name
      'EACH',
      'ELSE',
      'ELSEIF',
      'ENCLOSED', // Used with LOAD DATA/SELECT INTO OUTFILE
      'ESCAPED', // Used with LOAD DATA/SELECT INTO OUTFILE
      'EXCEPT', // Set operator (MariaDB 10.3+)
      'EXISTS',
      'EXIT',
      'EXPLAIN',
      'FALSE',
      'FETCH',
      'FLOAT',
      'FLOAT4', // Alias for FLOAT
      'FLOAT8', // Alias for DOUBLE
      'FOR',
      'FORCE', // Index hint
      'FOREIGN',
      'FROM',
      'FULLTEXT',
      'GENERATED', // Generated columns
      'GET', // Diagnostics Area
      'GENERAL', // Slow/General Log Context
      'GRANT',
      'GROUP',
      'HAVING',
      'HIGH_PRIORITY', // INSERT/SELECT modifier (often limited effect)
      'HOUR_MICROSECOND',
      'HOUR_MINUTE',
      'HOUR_SECOND',
      'IF',
      'IGNORE', // INSERT/UPDATE/DELETE modifier
      'IGNORE_SERVER_IDS', // Replication related
      'IN',
      'INDEX',
      'INFILE',
      'INNER',
      'INOUT', // Stored Procedure parameter mode
      'INSENSITIVE', // Cursor type
      'INSERT',
      'INT',
      'INT1', // Alias for TINYINT
      'INT2', // Alias for SMALLINT
      'INT3', // Alias for MEDIUMINT
      'INT4', // Alias for INT
      'INT8', // Alias for BIGINT
      'INTEGER',
      'INTERSECT', // Set operator (MariaDB 10.3+)
      'INTERVAL',
      'INTO',
      'IO_AFTER_GTIDS', // Replication related
      'IO_BEFORE_GTIDS', // Replication related
      'IS',
      'ITERATE', // Stored Procedure loop control
      'JOIN',
      'KEY', // Synonym for INDEX
      'KEYS', // Synonym for INDEXES (often in SHOW KEYS)
      'KILL',
      'LEADING',
      'LEAVE', // Stored Procedure loop control
      'LEFT',
      'LIKE',
      'LIMIT',
      'LINEAR', // Used with HASH partitioning
      'LINES', // Used with LOAD DATA/SELECT INTO OUTFILE
      'LOAD',
      'LOCALTIME',
      'LOCALTIMESTAMP',
      'LOCK',
      'LONG',
      'LONGBLOB',
      'LONGTEXT',
      'LOOP',
      'LOW_PRIORITY', // INSERT/UPDATE/DELETE modifier
      'MASTER_BIND', // Replication related
      'MASTER_HEARTBEAT_PERIOD', // MariaDB Replication
      'MASTER_SSL_VERIFY_SERVER_CERT', // Replication related
      'MATCH', // FULLTEXT search related
      'MAXVALUE', // Used with PARTITION definitions / sequences
      'MEDIUMBLOB',
      'MEDIUMINT',
      'MEDIUMTEXT',
      'MIDDLEINT', // Alias for MEDIUMINT
      'MINUTE_MICROSECOND',
      'MINUTE_SECOND',
      'MOD', // Modulo operator
      'MODIFIES', // Stored Procedure characteristic
      'NATURAL',
      'NO_WRITE_TO_BINLOG', // Alias for SQL_LOG_BIN = 0
      'NOT',
      'NULL',
      'NUMERIC', // Alias for DECIMAL
      'OFFSET', // MariaDB 10.6+ LIMIT ... OFFSET syntax
      'ON',
      'OPTIMIZE',
      'OPTIMIZER_COSTS', // Related to optimizer hints/control
      'OPTION',
      'OPTIONALLY', // Used with ENCLOSED BY
      'OR',
      'ORDER',
      'OUT', // Stored Procedure parameter mode
      'OUTER',
      'OUTFILE',
      'OVER', // Window functions (MariaDB 10.2+)
      'PARTITION',
      'PRECISION',
      'PRIMARY',
      'PROCEDURE',
      'PURGE', // Binary log related
      'RANGE', // Partitioning / Window functions
      'READ',
      'READ_WRITE', // Transaction access mode
      'READS', // Stored Procedure characteristic
      'REAL', // Alias for DOUBLE
      'RECURSIVE', // Common Table Expressions (MariaDB 10.2+)
      'REFERENCES',
      'REGEXP', // Regular expression operator
      'RELEASE', // User-level locks (GET_LOCK)
      'RENAME',
      'REPEAT',
      'REPLACE',
      'REQUIRE', // SSL options
      'RESIGNAL', // Stored Procedure error handling
      'RESTRICT',
      'RETURN',
      'RETURNING', // MariaDB 10.5+ DML returning clause
      'REVOKE',
      'RIGHT',
      'RLIKE', // Synonym for REGEXP
      'ROWS', // Window functions (MariaDB 10.2+)
      'SCHEMA', // Synonym for DATABASE
      'SCHEMAS', // Synonym for DATABASES
      'SECOND_MICROSECOND',
      'SELECT',
      'SENSITIVE', // Cursor type
      'SEPARATOR',
      'SET',
      'SHOW',
      'SIGNAL', // Stored Procedure error handling
      'SLOW', // Slow/General Log Context
      'SMALLINT',
      'SPATIAL', // Spatial indexes
      'SPECIFIC', // Stored Procedure related
      'SQL',
      'SQL_BIG_RESULT', // SELECT hint
      'SQL_CALC_FOUND_ROWS', // SELECT hint (deprecated in MySQL 8+, check MariaDB status)
      'SQL_SMALL_RESULT', // SELECT hint
      'SQLEXCEPTION', // Stored Procedure condition
      'SQLSTATE', // Stored Procedure condition / Diagnostics Area
      'SQLWARNING', // Stored Procedure condition
      'SSL',
      'STARTING', // Used with LOAD DATA/SELECT INTO OUTFILE
      'STORED', // Generated columns
      'STRAIGHT_JOIN', // SELECT hint
      'TABLE',
      'TERMINATED', // Used with LOAD DATA/SELECT INTO OUTFILE
      'THEN',
      'TINYBLOB',
      'TINYINT',
      'TINYTEXT',
      'TO',
      'TRAILING',
      'TRIGGER',
      'TRUE',
      'UNDO', // UNDO log related / Transaction info
      'UNION',
      'UNIQUE',
      'UNLOCK',
      'UNSIGNED', // Numeric type attribute
      'UPDATE',
      'USAGE', // Privilege type
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
      'VIRTUAL', // Generated columns
      'WHEN',
      'WHERE',
      'WHILE',
      'WINDOW', // Window functions (MariaDB 10.2+)
      'WITH', // Common Table Expressions / LOCK options
      'WRITE', // Transaction access mode
      'XOR',
      'YEAR_MONTH',
      'ZEROFILL', // Numeric type attribute
    ];
  }
}