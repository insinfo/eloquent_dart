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
  const InSubqueryPredicate(this.column, this.subquery,
      {this.negated = false});

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
      {this.caseSensitive = false, this.negated = false});

  final String column;
  final String pattern;
  final bool caseSensitive;
  final bool negated;
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
