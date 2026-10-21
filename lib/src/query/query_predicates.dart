import 'query_builder2.dart';

/// Comparison operators of [QueryBuilder2.where] and [QueryBuilder2.whereColumn].
///
/// Since Dart 3.10 the enum name can be left out at the call site:
/// `where('idade', 18, operator: .greaterThanOrEqualTo)`.
enum ComparisonOperator {
  equalTo('='),
  notEqualTo('<>'),
  greaterThan('>'),
  greaterThanOrEqualTo('>='),
  lessThan('<'),
  lessThanOrEqualTo('<=');

  const ComparisonOperator(this.sql);

  /// The SQL operator.
  final String sql;
}

/// Direction of [QueryBuilder2.orderBy].
enum SortDirection {
  ascending('asc'),
  descending('desc');

  const SortDirection(this.sql);

  final String sql;
}

/// How a condition is combined with the previous one.
enum LogicalConnector {
  and('and'),
  or('or');

  const LogicalConnector(this.sql);

  final String sql;
}

/// Join types of [QueryBuilder2.join].
enum JoinType {
  inner('inner'),
  left('left'),
  right('right');

  const JoinType(this.sql);

  final String sql;
}

/// One condition of a where/having list and how it joins the previous one.
final class WhereClause {
  const WhereClause(this.connector, this.predicate);

  final LogicalConnector connector;
  final Predicate predicate;
}

/// A condition, as built by the [QueryBuilder2] where methods. Each kind has
/// a fixed meaning: a value is always a bound value, a column always an
/// identifier, and SQL text only comes from [RawPredicate].
sealed class Predicate {
  const Predicate();
}

/// `column <operator> ?`
final class ComparisonPredicate extends Predicate {
  const ComparisonPredicate(this.column, this.operator, this.value);

  final String column;
  final ComparisonOperator operator;
  final Object value;
}

/// `column <op> ?` with a dialect operator given as text
/// ([QueryBuilder2.whereSqlOperator]); validated against the grammar.
final class SqlOperatorPredicate extends Predicate {
  const SqlOperatorPredicate(this.column, this.operator, this.value);

  final String column;
  final String operator;
  final Object? value;
}

/// `first <operator> second`, both identifiers.
final class ColumnComparisonPredicate extends Predicate {
  const ColumnComparisonPredicate(this.first, this.operator, this.second);

  final String first;
  final ComparisonOperator operator;
  final String second;
}

/// `column is [not] null`
final class NullPredicate extends Predicate {
  const NullPredicate(this.column, {required this.isNull});

  final String column;
  final bool isNull;
}

/// `column [not] in (?, ?, ...)`; an empty list is always false (`not in`:
/// always true).
final class InPredicate extends Predicate {
  const InPredicate(this.column, this.values, {this.negated = false});

  final String column;
  final List<Object> values;
  final bool negated;
}

/// `column [not] in (select ...)`
final class InSubqueryPredicate extends Predicate {
  const InSubqueryPredicate(this.column, this.subquery, {this.negated = false});

  final String column;
  final QueryBuilder2 subquery;
  final bool negated;
}

/// `column [not] between ? and ?`
final class BetweenPredicate extends Predicate {
  const BetweenPredicate(this.column, this.low, this.high,
      {this.negated = false});

  final String column;
  final Object low;
  final Object high;
  final bool negated;
}

/// `column [not] like ?` (case-insensitive unless [caseSensitive]).
final class LikePredicate extends Predicate {
  const LikePredicate(this.column, this.pattern,
      {this.caseSensitive = false,
      this.negated = false,
      this.unaccent = false,
      this.lower = false});

  final String column;
  final String pattern;
  final bool caseSensitive;
  final bool negated;

  /// `unaccent(column::text) ilike unaccent(?)` (PostgreSQL).
  final bool unaccent;

  /// `lower(column) like lower(?)` instead of `ilike` / the collation.
  final bool lower;
}

/// The part of a date/time column compared by [DatePartPredicate].
enum DatePart {
  /// `column::date` (PostgreSQL) / `date(column)` (MySQL).
  date('Date'),
  time('Time'),
  day('Day'),
  month('Month'),
  year('Year');

  const DatePart(this.whereType);

  /// The QueryBuilder where type.
  final String whereType;
}

/// `<part of column> <operator> ?` (whereDate, whereYear, ...).
final class DatePartPredicate extends Predicate {
  const DatePartPredicate(this.column, this.part, this.operator, this.value);

  final String column;
  final DatePart part;
  final ComparisonOperator operator;
  final Object value;
}

/// `(c1, c2) [not] in ((?, ?), ...)`; an empty list is always false (`not
/// in`: always true).
final class TupleInPredicate extends Predicate {
  const TupleInPredicate(this.columns, this.tuples, {this.negated = false});

  final List<String> columns;
  final List<List<Object?>> tuples;
  final bool negated;
}

/// `(c1, c2) <operator> (?, ?)`
final class RowValuesPredicate extends Predicate {
  const RowValuesPredicate(this.columns, this.operator, this.values);

  final List<String> columns;
  final ComparisonOperator operator;
  final List<Object?> values;
}

/// `column = any(?)` / `column <> all(?)` with one array parameter
/// (PostgreSQL; `in (...)` elsewhere).
final class AnyArrayPredicate extends Predicate {
  const AnyArrayPredicate(this.column, this.values,
      {this.elementType, this.negated = false});

  final String column;
  final List<Object?> values;
  final String? elementType;
  final bool negated;
}

/// `column [not] between low and high`, the bounds being columns.
final class BetweenColumnsPredicate extends Predicate {
  const BetweenColumnsPredicate(this.column, this.low, this.high,
      {this.negated = false});

  final String column;
  final String low;
  final String high;
  final bool negated;
}

/// `? [not] between low and high`, the bounds being columns.
final class ValueBetweenPredicate extends Predicate {
  const ValueBetweenPredicate(this.value, this.low, this.high,
      {this.negated = false});

  final Object value;
  final String low;
  final String high;
  final bool negated;
}

/// `(column)::jsonb @> ?` (PostgreSQL) / `json_contains(column, ?)` (MySQL).
final class JsonContainsPredicate extends Predicate {
  const JsonContainsPredicate(this.column, this.value, {this.negated = false});

  final String column;
  final Object? value;
  final bool negated;
}

/// `json length of column <operator> ?`
final class JsonLengthPredicate extends Predicate {
  const JsonLengthPredicate(this.column, this.operator, this.length);

  final String column;
  final ComparisonOperator operator;
  final int length;
}

/// PostgreSQL array operators of [ArrayOperatorPredicate].
enum ArrayOperator {
  /// `@>`: the column has every element of the value.
  contains('@>'),

  /// `<@`: every element of the column is in the value.
  containedBy('<@'),

  /// `&&`: the column and the value share an element.
  overlaps('&&');

  const ArrayOperator(this.sql);

  final String sql;
}

/// `column <op> ?` with a PostgreSQL array value.
final class ArrayOperatorPredicate extends Predicate {
  const ArrayOperatorPredicate(this.column, this.operator, this.values);

  final String column;
  final ArrayOperator operator;
  final List<Object?> values;
}

/// Full-text search of [value] in [columns] (`to_tsvector(...) @@ ...` on
/// PostgreSQL, `match ... against` on MySQL).
final class FullTextPredicate extends Predicate {
  const FullTextPredicate(this.columns, this.value, this.options);

  final List<String> columns;
  final String value;

  /// `language` and `mode` (`plain`, `phrase`, `websearch`; MySQL: `boolean`,
  /// `expanded`), as in QueryBuilder.whereFullText.
  final Map<String, Object> options;
}

/// `[not] (conditions)`
final class GroupPredicate extends Predicate {
  const GroupPredicate(this.clauses, {this.negated = false});

  final List<WhereClause> clauses;
  final bool negated;
}

/// `[not] exists (select ...)`
final class ExistsPredicate extends Predicate {
  const ExistsPredicate(this.subquery, {this.negated = false});

  final QueryBuilder2 subquery;
  final bool negated;
}

/// SQL written by the caller, with its bindings.
final class RawPredicate extends Predicate {
  const RawPredicate(this.sql, this.bindings);

  final String sql;
  final List<Object?> bindings;
}
