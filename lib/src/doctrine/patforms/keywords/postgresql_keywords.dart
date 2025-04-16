// File: lib/src/doctrine/platforms/keywords/postgresql_keywords.dart

import 'keyword_list.dart';

/// Reserved keywords list corresponding to the PostgreSQL database platform.
///
/// Provides the list of words reserved by PostgreSQL, used to determine
/// if an identifier needs quoting.
class PostgreSQLKeywords extends KeywordList {
  /// {@macro keyword_list.getKeywords}
  ///
  /// Returns the list of reserved words for PostgreSQL.
  /// Based on the list provided in the PHP Doctrine DBAL counterpart.
  @override
  List<String> getKeywords() {
    // Using const for an immutable list literal, which is efficient.
    return const [
      'ALL',
      'ANALYSE', // Note: PostgreSQL also accepts ANALYZE
      'ANALYZE',
      'AND',
      'ANY',
      'ARRAY',
      'AS',
      'ASC',
      'ASYMMETRIC',
      'AUTHORIZATION',
      'BINARY',
      'BOTH',
      'CASE',
      'CAST',
      'CHECK',
      'COLLATE',
      'COLLATION',
      'COLUMN',
      'CONCURRENTLY',
      'CONSTRAINT',
      'CREATE',
      'CROSS',
      'CURRENT_CATALOG',
      'CURRENT_DATE',
      'CURRENT_ROLE',
      'CURRENT_SCHEMA',
      'CURRENT_TIME',
      'CURRENT_TIMESTAMP',
      'CURRENT_USER',
      'DEFAULT',
      'DEFERRABLE',
      'DESC',
      'DISTINCT',
      'DO',
      'ELSE',
      'END',
      'EXCEPT',
      'FALSE',
      'FETCH',
      'FOR',
      'FOREIGN',
      'FREEZE', // Often used with ANALYZE
      'FROM',
      'FULL',
      'GRANT',
      'GROUP',
      'HAVING',
      'ILIKE', // PostgreSQL specific case-insensitive LIKE
      'IN',
      'INITIALLY',
      'INNER',
      'INTERSECT',
      'INTO',
      'IS',
      'ISNULL', // Not standard SQL, PostgreSQL prefers IS NULL
      'JOIN',
      'LATERAL',
      'LEADING',
      'LEFT',
      'LIKE',
      'LIMIT',
      'LOCALTIME',
      'LOCALTIMESTAMP',
      'NATURAL',
      'NOT',
      'NOTNULL', // Not standard SQL, PostgreSQL prefers IS NOT NULL
      'NULL',
      'OFFSET',
      'ON',
      'ONLY',
      'OR',
      'ORDER',
      'OUTER',
      'OVERLAPS', // PostgreSQL specific date/time operator
      'PLACING', // Used with OVERLAY
      'PRIMARY',
      'REFERENCES',
      'RETURNING', // PostgreSQL specific clause
      'RIGHT',
      'SELECT',
      'SESSION_USER',
      'SIMILAR', // Used with SIMILAR TO operator
      'SOME', // Alias for ANY
      'SYMMETRIC',
      'TABLE',
      'THEN',
      'TO',
      'TRAILING',
      'TRUE',
      'UNION',
      'UNIQUE',
      'USER',
      'USING',
      'VARIADIC', // Used with function arguments
      'VERBOSE', // Often used with ANALYZE or EXPLAIN
      'WHEN',
      'WHERE',
      'WINDOW',
      'WITH',
    ];
  }
}