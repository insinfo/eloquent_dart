import 'dart:async';

import 'package:eloquent/eloquent.dart';
import 'package:meta/meta.dart';

/// Where-condition methods shared by [QueryBuilder2] and the [WhereBuilder]
/// of a group. Every argument has one meaning:
///
/// - `where(column, value)` compares with `=`; `operator:` changes the
///   comparison. The value is always bound (`?`), never read as an operator,
///   a column or SQL.
/// - Columns are identifiers; [whereColumn] compares two columns.
/// - SQL text only enters through [whereRaw] and [whereSqlOperator].
///
/// `null`: `where(c, null)` is `c is null`,
/// `where(c, null, operator: notEqualTo)` is `c is not null`, any other
/// operator with `null` throws [ArgumentError].
mixin WhereConditions<Self> {
  @protected
  List<WhereClause> get whereClauseList;
  @protected
  Self get whereSelf;

  Self _add(LogicalConnector connector, Predicate predicate) {
    whereClauseList.add(WhereClause(connector, predicate));
    return whereSelf;
  }

  // ------------------------------------------------------------ comparison

  /// `column = ?`, or the comparison given by [operator].
  Self where(String column, Object? value,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.and, _comparison(column, value, operator));

  /// `or column = ?`, or the comparison given by [operator].
  Self orWhere(String column, Object? value,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.or, _comparison(column, value, operator));

  Self whereEqualTo(String column, Object? value) => where(column, value);
  Self orWhereEqualTo(String column, Object? value) => orWhere(column, value);

  Self whereNotEqualTo(String column, Object? value) =>
      where(column, value, operator: CompOperator.notEqualTo);
  Self orWhereNotEqualTo(String column, Object? value) =>
      orWhere(column, value, operator: CompOperator.notEqualTo);

  Self whereGreaterThan(String column, Object value) =>
      where(column, value, operator: CompOperator.greaterThan);
  Self orWhereGreaterThan(String column, Object value) =>
      orWhere(column, value, operator: CompOperator.greaterThan);

  Self whereGreaterThanOrEqualTo(String column, Object value) =>
      where(column, value, operator: CompOperator.greaterThanOrEqualTo);
  Self orWhereGreaterThanOrEqualTo(String column, Object value) =>
      orWhere(column, value, operator: CompOperator.greaterThanOrEqualTo);

  Self whereLessThan(String column, Object value) =>
      where(column, value, operator: CompOperator.lessThan);
  Self orWhereLessThan(String column, Object value) =>
      orWhere(column, value, operator: CompOperator.lessThan);

  Self whereLessThanOrEqualTo(String column, Object value) =>
      where(column, value, operator: CompOperator.lessThanOrEqualTo);
  Self orWhereLessThanOrEqualTo(String column, Object value) =>
      orWhere(column, value, operator: CompOperator.lessThanOrEqualTo);

  /// `column <operator> ?` with a dialect operator as text, e.g.
  /// `whereSqlOperator('nome', 'ilike', 'ana%')` or PostgreSQL `'@>'`. The
  /// operator must be one the grammar knows; it is checked when the query is
  /// compiled.
  Self whereSqlOperator(String column, String operator, Object? value) =>
      _add(LogicalConnector.and, _sqlOperator(column, operator, value));
  Self orWhereSqlOperator(String column, String operator, Object? value) =>
      _add(LogicalConnector.or, _sqlOperator(column, operator, value));

  // ------------------------------------------------------------------ null

  Self whereNull(String column) =>
      _add(LogicalConnector.and, NullPredicate(_column(column), isNull: true));
  Self orWhereNull(String column) =>
      _add(LogicalConnector.or, NullPredicate(_column(column), isNull: true));
  Self whereNotNull(String column) =>
      _add(LogicalConnector.and, NullPredicate(_column(column), isNull: false));
  Self orWhereNotNull(String column) =>
      _add(LogicalConnector.or, NullPredicate(_column(column), isNull: false));

  // -------------------------------------------------------------------- in

  /// `column in (?, ...)`. An empty list matches nothing. `null` elements
  /// throw (`x in (null)` never matches): combine with [orWhereNull] in a
  /// group instead.
  Self whereIn(String column, Iterable<Object?> values) =>
      _add(LogicalConnector.and, _in(column, values, negated: false));
  Self orWhereIn(String column, Iterable<Object?> values) =>
      _add(LogicalConnector.or, _in(column, values, negated: false));

  /// `column not in (?, ...)`. An empty list matches everything.
  Self whereNotIn(String column, Iterable<Object?> values) =>
      _add(LogicalConnector.and, _in(column, values, negated: true));
  Self orWhereNotIn(String column, Iterable<Object?> values) =>
      _add(LogicalConnector.or, _in(column, values, negated: true));

  /// `column in (select ...)`.
  Self whereInSubquery(String column, QueryBuilder2 subquery) => _add(
      LogicalConnector.and,
      InSubqueryPredicate(_column(column), subquery.clone()));
  Self orWhereInSubquery(String column, QueryBuilder2 subquery) => _add(
      LogicalConnector.or,
      InSubqueryPredicate(_column(column), subquery.clone()));
  Self whereNotInSubquery(String column, QueryBuilder2 subquery) => _add(
      LogicalConnector.and,
      InSubqueryPredicate(_column(column), subquery.clone(), negated: true));
  Self orWhereNotInSubquery(String column, QueryBuilder2 subquery) => _add(
      LogicalConnector.or,
      InSubqueryPredicate(_column(column), subquery.clone(), negated: true));

  // --------------------------------------------------------------- between

  /// `column between low and high` (both limits included).
  Self whereBetween(String column, Object low, Object high) =>
      _add(LogicalConnector.and, _between(column, low, high, negated: false));
  Self orWhereBetween(String column, Object low, Object high) =>
      _add(LogicalConnector.or, _between(column, low, high, negated: false));
  Self whereNotBetween(String column, Object low, Object high) =>
      _add(LogicalConnector.and, _between(column, low, high, negated: true));
  Self orWhereNotBetween(String column, Object low, Object high) =>
      _add(LogicalConnector.or, _between(column, low, high, negated: true));

  // ------------------------------------------------------------------ like

  /// `column like ?`, case-insensitive unless [caseSensitive] (PostgreSQL
  /// `ilike`; MySQL follows the collation, `like binary` when sensitive).
  /// `%` and `_` in [pattern] are wildcards.
  /// [unaccent] (PostgreSQL, extension `unaccent`) compares
  /// `unaccent(column::text) ilike unaccent(?)`; [lower] compares
  /// `lower(column) like lower(?)` (the form an expression index on
  /// `lower(...)` can serve; see QueryBuilder.whereLike).
  Self whereLike(String column, String pattern,
          {bool caseSensitive = false,
          bool unaccent = false,
          bool lower = false}) =>
      _add(LogicalConnector.and,
          _like(column, pattern, caseSensitive, unaccent, lower, false));
  Self orWhereLike(String column, String pattern,
          {bool caseSensitive = false,
          bool unaccent = false,
          bool lower = false}) =>
      _add(LogicalConnector.or,
          _like(column, pattern, caseSensitive, unaccent, lower, false));
  Self whereNotLike(String column, String pattern,
          {bool caseSensitive = false,
          bool unaccent = false,
          bool lower = false}) =>
      _add(LogicalConnector.and,
          _like(column, pattern, caseSensitive, unaccent, lower, true));
  Self orWhereNotLike(String column, String pattern,
          {bool caseSensitive = false,
          bool unaccent = false,
          bool lower = false}) =>
      _add(LogicalConnector.or,
          _like(column, pattern, caseSensitive, unaccent, lower, true));

  static LikePredicate _like(String column, String pattern, bool caseSensitive,
      bool unaccent, bool lower, bool negated) {
    if (lower && caseSensitive) {
      throw ArgumentError('lower: true is case-insensitive; it cannot be '
          'combined with caseSensitive: true.');
    }
    return LikePredicate(_column(column), pattern,
        caseSensitive: caseSensitive,
        negated: negated,
        unaccent: unaccent,
        lower: lower);
  }

  /// Text search of [term] in [columns] (see QueryBuilder.whereSearch):
  /// `(col1 ilike ? or col2 ilike ?)`, the term matched literally (`%` and
  /// `_` escaped) as given by [match]; [unaccent] ignores accents
  /// (PostgreSQL); [everyWord] requires each word of the term in some column.
  /// A null or blank [term] adds nothing.
  Self whereSearch(List<String> columns, String? term,
      {SearchMatch match = SearchMatch.contains,
      bool unaccent = false,
      bool lower = false,
      bool caseSensitive = false,
      bool everyWord = false}) {
    final predicate = _search(
        columns, term, match, unaccent, lower, caseSensitive, everyWord);
    return predicate == null
        ? whereSelf
        : _add(LogicalConnector.and, predicate);
  }

  Self orWhereSearch(List<String> columns, String? term,
      {SearchMatch match = SearchMatch.contains,
      bool unaccent = false,
      bool lower = false,
      bool caseSensitive = false,
      bool everyWord = false}) {
    final predicate = _search(
        columns, term, match, unaccent, lower, caseSensitive, everyWord);
    return predicate == null ? whereSelf : _add(LogicalConnector.or, predicate);
  }

  /// `(col1 like ? or col2 like ? ...)` with [pattern] as given (`%` and `_`
  /// are wildcards).
  Self whereAnyLike(List<String> columns, String pattern,
          {bool caseSensitive = false,
          bool unaccent = false,
          bool lower = false}) =>
      _add(LogicalConnector.and,
          _likeGroup(columns, pattern, caseSensitive, unaccent, lower));
  Self orWhereAnyLike(List<String> columns, String pattern,
          {bool caseSensitive = false,
          bool unaccent = false,
          bool lower = false}) =>
      _add(LogicalConnector.or,
          _likeGroup(columns, pattern, caseSensitive, unaccent, lower));

  static Predicate? _search(
      List<String> columns,
      String? term,
      SearchMatch match,
      bool unaccent,
      bool lower,
      bool caseSensitive,
      bool everyWord) {
    final text = term?.trim() ?? '';
    if (text.isEmpty) return null;
    final words = everyWord ? text.split(RegExp(r'\s+')) : [text];
    final groups = [
      for (final word in words)
        _likeGroup(columns, QueryBuilder.likePattern(word, match),
            caseSensitive, unaccent, lower)
    ];
    if (groups.length == 1) return groups.first;
    return GroupPredicate(List.unmodifiable([
      for (final group in groups) WhereClause(LogicalConnector.and, group)
    ]));
  }

  static GroupPredicate _likeGroup(List<String> columns, String pattern,
      bool caseSensitive, bool unaccent, bool lower) {
    if (columns.isEmpty) {
      throw ArgumentError.value(columns, 'columns', 'Must not be empty.');
    }
    return GroupPredicate(List.unmodifiable([
      for (final column in columns)
        WhereClause(LogicalConnector.or,
            _like(column, pattern, caseSensitive, unaccent, lower, false))
    ]));
  }

  // ---------------------------------------------------- any / all / none

  /// `(c1 = ? or c2 = ? ...)`: some column matches (or the comparison given
  /// by [operator]).
  Self whereAny(List<String> columns, Object? value,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.and,
          _columnsGroup(columns, value, operator, LogicalConnector.or));
  Self orWhereAny(List<String> columns, Object? value,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.or,
          _columnsGroup(columns, value, operator, LogicalConnector.or));

  /// `(c1 = ? and c2 = ? ...)`: every column matches.
  Self whereAll(List<String> columns, Object? value,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.and,
          _columnsGroup(columns, value, operator, LogicalConnector.and));
  Self orWhereAll(List<String> columns, Object? value,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.or,
          _columnsGroup(columns, value, operator, LogicalConnector.and));

  /// `not (c1 = ? or c2 = ? ...)`: no column matches.
  Self whereNone(List<String> columns, Object? value,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(
          LogicalConnector.and,
          _columnsGroup(columns, value, operator, LogicalConnector.or,
              negated: true));
  Self orWhereNone(List<String> columns, Object? value,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(
          LogicalConnector.or,
          _columnsGroup(columns, value, operator, LogicalConnector.or,
              negated: true));

  static Predicate _columnsGroup(List<String> columns, Object? value,
      CompOperator operator, LogicalConnector inner,
      {bool negated = false}) {
    if (columns.isEmpty) {
      throw ArgumentError.value(columns, 'columns', 'Must not be empty.');
    }
    return GroupPredicate(
        List.unmodifiable([
          for (final column in columns)
            WhereClause(inner, _comparison(column, value, operator))
        ]),
        negated: negated);
  }

  // ----------------------------------------------------------------- dates

  /// `column::date = ?` (PostgreSQL) / `date(column) = ?` (MySQL); [value] a
  /// DateTime or a `yyyy-MM-dd` string.
  Self whereDate(String column, Object value,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.and,
          _datePart(column, DatePart.date, operator, value));
  Self orWhereDate(String column, Object value,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.or,
          _datePart(column, DatePart.date, operator, value));

  /// The time of day of [column]; [value] like `'08:30:00'`.
  Self whereTime(String column, Object value,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.and,
          _datePart(column, DatePart.time, operator, value));
  Self orWhereTime(String column, Object value,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.or,
          _datePart(column, DatePart.time, operator, value));

  Self whereDay(String column, int value,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.and,
          _datePart(column, DatePart.day, operator, value));
  Self orWhereDay(String column, int value,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.or,
          _datePart(column, DatePart.day, operator, value));

  Self whereMonth(String column, int value,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.and,
          _datePart(column, DatePart.month, operator, value));
  Self orWhereMonth(String column, int value,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.or,
          _datePart(column, DatePart.month, operator, value));

  Self whereYear(String column, int value,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.and,
          _datePart(column, DatePart.year, operator, value));
  Self orWhereYear(String column, int value,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.or,
          _datePart(column, DatePart.year, operator, value));

  static Predicate _datePart(
          String column, DatePart part, CompOperator operator, Object value) =>
      DatePartPredicate(
          _column(column), part, operator, _value(value, 'value'));

  // ------------------------------------------------ tuples, rows, arrays

  /// `(c1, c2) in ((?, ?), ...)`: a composite key among [tuples], e.g.
  /// `whereInTuple(['cod_processo', 'ano_exercicio'], [[10, '2024']])`.
  Self whereInTuple(List<String> columns, Iterable<List<Object?>> tuples) =>
      _add(LogicalConnector.and, _tuple(columns, tuples, negated: false));
  Self orWhereInTuple(List<String> columns, Iterable<List<Object?>> tuples) =>
      _add(LogicalConnector.or, _tuple(columns, tuples, negated: false));
  Self whereNotInTuple(List<String> columns, Iterable<List<Object?>> tuples) =>
      _add(LogicalConnector.and, _tuple(columns, tuples, negated: true));
  Self orWhereNotInTuple(
          List<String> columns, Iterable<List<Object?>> tuples) =>
      _add(LogicalConnector.or, _tuple(columns, tuples, negated: true));

  /// `(c1, c2) <operator> (?, ?)`, e.g. keyset pagination on a composite
  /// key: `whereRowValues(['ano', 'numero'], [2024, 150], operator: .greaterThan)`.
  Self whereRowValues(List<String> columns, List<Object?> values,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.and, _rowValues(columns, values, operator));
  Self orWhereRowValues(List<String> columns, List<Object?> values,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.or, _rowValues(columns, values, operator));

  /// `column = any(?)`: [values] in one array parameter (PostgreSQL; `in
  /// (...)` on MySQL). [elementType] casts it (`?::uuid[]`).
  Self whereAnyArray(String column, Iterable<Object?> values,
          {String? elementType}) =>
      _add(LogicalConnector.and,
          _anyArray(column, values, elementType, negated: false));
  Self orWhereAnyArray(String column, Iterable<Object?> values,
          {String? elementType}) =>
      _add(LogicalConnector.or,
          _anyArray(column, values, elementType, negated: false));

  /// `column <> all(?)` (PostgreSQL; `not in (...)` on MySQL).
  Self whereNotAnyArray(String column, Iterable<Object?> values,
          {String? elementType}) =>
      _add(LogicalConnector.and,
          _anyArray(column, values, elementType, negated: true));
  Self orWhereNotAnyArray(String column, Iterable<Object?> values,
          {String? elementType}) =>
      _add(LogicalConnector.or,
          _anyArray(column, values, elementType, negated: true));

  /// PostgreSQL array column operators: [ArrayOperator.contains] (`@>`),
  /// [ArrayOperator.containedBy] (`<@`), [ArrayOperator.overlaps] (`&&`).
  Self whereArray(
          String column, ArrayOperator operator, Iterable<Object?> values) =>
      _add(
          LogicalConnector.and,
          ArrayOperatorPredicate(
              _column(column), operator, List.unmodifiable(values)));
  Self orWhereArray(
          String column, ArrayOperator operator, Iterable<Object?> values) =>
      _add(
          LogicalConnector.or,
          ArrayOperatorPredicate(
              _column(column), operator, List.unmodifiable(values)));

  Self whereArrayContains(String column, Iterable<Object?> values) =>
      whereArray(column, ArrayOperator.contains, values);
  Self whereArrayContainedBy(String column, Iterable<Object?> values) =>
      whereArray(column, ArrayOperator.containedBy, values);
  Self whereArrayOverlaps(String column, Iterable<Object?> values) =>
      whereArray(column, ArrayOperator.overlaps, values);

  static Predicate _tuple(List<String> columns, Iterable<List<Object?>> tuples,
      {required bool negated}) {
    if (columns.isEmpty) {
      throw ArgumentError.value(columns, 'columns', 'Must not be empty.');
    }
    columns.forEach(_column);
    final rows = <List<Object?>>[];
    for (final tuple in tuples) {
      if (tuple.length != columns.length) {
        throw ArgumentError.value(tuple, 'tuples',
            'Expected ${columns.length} values, one per column.');
      }
      rows.add(List.unmodifiable(
          [for (final v in tuple) v == null ? null : _value(v, 'tuples')]));
    }
    return TupleInPredicate(List.unmodifiable(columns), List.unmodifiable(rows),
        negated: negated);
  }

  static Predicate _rowValues(
      List<String> columns, List<Object?> values, CompOperator operator) {
    if (columns.isEmpty || columns.length != values.length) {
      throw ArgumentError(
          'whereRowValues needs as many values as columns (${columns.length}).');
    }
    columns.forEach(_column);
    return RowValuesPredicate(
        List.unmodifiable(columns),
        operator,
        List.unmodifiable(
            [for (final v in values) v == null ? null : _value(v, 'values')]));
  }

  static Predicate _anyArray(
      String column, Iterable<Object?> values, String? elementType,
      {required bool negated}) {
    _column(column);
    return AnyArrayPredicate(
        column,
        List.unmodifiable(
            [for (final v in values) v == null ? null : _value(v, 'values')]),
        elementType: elementType,
        negated: negated);
  }

  // --------------------------------------------- between columns / value

  /// `column between low and high`, both bounds columns.
  Self whereBetweenColumns(String column, String low, String high) => _add(
      LogicalConnector.and,
      BetweenColumnsPredicate(_column(column), _column(low), _column(high)));
  Self orWhereBetweenColumns(String column, String low, String high) => _add(
      LogicalConnector.or,
      BetweenColumnsPredicate(_column(column), _column(low), _column(high)));
  Self whereNotBetweenColumns(String column, String low, String high) => _add(
      LogicalConnector.and,
      BetweenColumnsPredicate(_column(column), _column(low), _column(high),
          negated: true));
  Self orWhereNotBetweenColumns(String column, String low, String high) => _add(
      LogicalConnector.or,
      BetweenColumnsPredicate(_column(column), _column(low), _column(high),
          negated: true));

  /// `? between low and high`: [value] inside the range of two columns, e.g.
  /// `whereValueBetween(hoje, 'data_inicio', 'data_fim')`.
  Self whereValueBetween(Object value, String low, String high) => _add(
      LogicalConnector.and,
      ValueBetweenPredicate(
          _value(value, 'value'), _column(low), _column(high)));
  Self orWhereValueBetween(Object value, String low, String high) => _add(
      LogicalConnector.or,
      ValueBetweenPredicate(
          _value(value, 'value'), _column(low), _column(high)));
  Self whereValueNotBetween(Object value, String low, String high) => _add(
      LogicalConnector.and,
      ValueBetweenPredicate(_value(value, 'value'), _column(low), _column(high),
          negated: true));
  Self orWhereValueNotBetween(Object value, String low, String high) => _add(
      LogicalConnector.or,
      ValueBetweenPredicate(_value(value, 'value'), _column(low), _column(high),
          negated: true));

  // ------------------------------------------------------ JSON, full text

  /// `(column)::jsonb @> ?` (PostgreSQL) / `json_contains(column, ?)`
  /// (MySQL); [value] is encoded as JSON.
  Self whereJsonContains(String column, Object? value) =>
      _add(LogicalConnector.and, JsonContainsPredicate(_column(column), value));
  Self orWhereJsonContains(String column, Object? value) =>
      _add(LogicalConnector.or, JsonContainsPredicate(_column(column), value));
  Self whereJsonDoesntContain(String column, Object? value) => _add(
      LogicalConnector.and,
      JsonContainsPredicate(_column(column), value, negated: true));
  Self orWhereJsonDoesntContain(String column, Object? value) => _add(
      LogicalConnector.or,
      JsonContainsPredicate(_column(column), value, negated: true));

  /// The length of the JSON array in [column] compared with [length].
  Self whereJsonLength(String column, int length,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.and,
          JsonLengthPredicate(_column(column), operator, length));
  Self orWhereJsonLength(String column, int length,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.or,
          JsonLengthPredicate(_column(column), operator, length));

  /// Full-text search: `to_tsvector(language, col) @@ plainto_tsquery(...)`
  /// on PostgreSQL ([mode]: `plain`, `phrase`, `websearch`), `match ...
  /// against` on MySQL ([mode] `boolean`).
  Self whereFullText(List<String> columns, String value,
          {String? language, String? mode}) =>
      _add(LogicalConnector.and, _fullText(columns, value, language, mode));
  Self orWhereFullText(List<String> columns, String value,
          {String? language, String? mode}) =>
      _add(LogicalConnector.or, _fullText(columns, value, language, mode));

  static Predicate _fullText(
      List<String> columns, String value, String? language, String? mode) {
    if (columns.isEmpty) {
      throw ArgumentError.value(columns, 'columns', 'Must not be empty.');
    }
    columns.forEach(_column);
    return FullTextPredicate(List.unmodifiable(columns), value, {
      if (language != null) 'language': language,
      if (mode != null) 'mode': mode,
    });
  }

  // ---------------------------------------------------------------- column

  /// `first = second` (two columns), or the comparison given by [operator].
  Self whereColumn(String first, String second,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.and,
          ColumnComparisonPredicate(_column(first), operator, _column(second)));
  Self orWhereColumn(String first, String second,
          {CompOperator operator = CompOperator.equalTo}) =>
      _add(LogicalConnector.or,
          ColumnComparisonPredicate(_column(first), operator, _column(second)));

  // ----------------------------------------------------------------- group

  /// `and (...)`: the conditions added by [build] in parentheses. An empty
  /// group adds nothing.
  Self whereGroup(void Function(WhereBuilder group) build) =>
      _group(LogicalConnector.and, build, negated: false);
  Self orWhereGroup(void Function(WhereBuilder group) build) =>
      _group(LogicalConnector.or, build, negated: false);

  /// `and not (...)`.
  Self whereNotGroup(void Function(WhereBuilder group) build) =>
      _group(LogicalConnector.and, build, negated: true);
  Self orWhereNotGroup(void Function(WhereBuilder group) build) =>
      _group(LogicalConnector.or, build, negated: true);

  Self _group(LogicalConnector connector, void Function(WhereBuilder) build,
      {required bool negated}) {
    final group = WhereBuilder();
    build(group);
    if (group.whereClauseList.isEmpty) return whereSelf;
    return _add(
        connector,
        GroupPredicate(List.unmodifiable(group.whereClauseList),
            negated: negated));
  }

  // ---------------------------------------------------------------- exists

  /// `exists (select ...)`; the subquery is copied when added.
  Self whereExists(QueryBuilder2 subquery) =>
      _add(LogicalConnector.and, ExistsPredicate(subquery.clone()));
  Self orWhereExists(QueryBuilder2 subquery) =>
      _add(LogicalConnector.or, ExistsPredicate(subquery.clone()));
  Self whereNotExists(QueryBuilder2 subquery) => _add(
      LogicalConnector.and, ExistsPredicate(subquery.clone(), negated: true));
  Self orWhereNotExists(QueryBuilder2 subquery) => _add(
      LogicalConnector.or, ExistsPredicate(subquery.clone(), negated: true));

  // ------------------------------------------------------------------- raw

  /// SQL written by the caller; `?` placeholders take [bindings].
  Self whereRaw(String sql, [List<Object?> bindings = const []]) => _add(
      LogicalConnector.and, RawPredicate(sql, List.unmodifiable(bindings)));
  Self orWhereRaw(String sql, [List<Object?> bindings = const []]) =>
      _add(LogicalConnector.or, RawPredicate(sql, List.unmodifiable(bindings)));

  // ------------------------------------------------------------ validation

  static String _column(String column) {
    if (column.trim().isEmpty) {
      throw ArgumentError.value(column, 'column', 'Must not be empty.');
    }
    return column;
  }

  static Object _value(Object value, String name) {
    if (value is QueryBuilder2 ||
        value is QueryBuilder ||
        value is QueryExpression ||
        value is Function) {
      throw ArgumentError.value(
          value,
          name,
          'Not a value. Use whereInSubquery/whereExists for subqueries, '
          'whereGroup for callbacks and whereRaw for SQL.');
    }
    return value;
  }

  static Predicate _comparison(
      String column, Object? value, CompOperator operator) {
    _column(column);
    if (value == null) {
      switch (operator) {
        case CompOperator.equalTo:
          return NullPredicate(column, isNull: true);
        case CompOperator.notEqualTo:
          return NullPredicate(column, isNull: false);
        default:
          throw ArgumentError.value(
              null,
              'value',
              'Only equalTo (is null) and notEqualTo (is not null) accept '
                  'null; "${operator.name}" with null matches nothing.');
      }
    }
    return ComparisonPredicate(column, operator, _value(value, 'value'));
  }

  static Predicate _sqlOperator(String column, String operator, Object? value) {
    _column(column);
    if (operator.trim().isEmpty) {
      throw ArgumentError.value(operator, 'operator', 'Must not be empty.');
    }
    return SqlOperatorPredicate(
        column, operator.trim(), value == null ? null : _value(value, 'value'));
  }

  static Predicate _in(String column, Iterable<Object?> values,
      {required bool negated}) {
    _column(column);
    final list = <Object>[];
    for (final value in values) {
      if (value == null) {
        throw ArgumentError.value(
            values,
            'values',
            'null never matches in IN; use whereNull/orWhereNull in a '
                'group.');
      }
      list.add(_value(value, 'values'));
    }
    return InPredicate(column, List.unmodifiable(list), negated: negated);
  }

  static Predicate _between(String column, Object low, Object high,
      {required bool negated}) {
    return BetweenPredicate(
        _column(column), _value(low, 'low'), _value(high, 'high'),
        negated: negated);
  }
}

/// The conditions of a [WhereConditions.whereGroup]: only where methods.
final class WhereBuilder with WhereConditions<WhereBuilder> {
  @override
  final List<WhereClause> whereClauseList = [];

  @override
  WhereBuilder get whereSelf => this;

  /// The conditions added so far.
  List<WhereClause> get clauses => List.unmodifiable(whereClauseList);
}

/// The `on` conditions of [QueryBuilder2.joinOn].
final class JoinBuilder {
  final List<_JoinCondition> _conditions = [];

  /// `on first = second` (two columns).
  JoinBuilder on(String first, String second,
      {CompOperator operator = CompOperator.equalTo}) {
    _conditions
        .add(_JoinColumns(LogicalConnector.and, first, operator, second));
    return this;
  }

  JoinBuilder orOn(String first, String second,
      {CompOperator operator = CompOperator.equalTo}) {
    _conditions.add(_JoinColumns(LogicalConnector.or, first, operator, second));
    return this;
  }

  /// `and column = ?` (a bound value).
  JoinBuilder where(String column, Object value,
      {CompOperator operator = CompOperator.equalTo}) {
    _conditions.add(_JoinValue(LogicalConnector.and, column, operator,
        WhereConditions._value(value, 'value')));
    return this;
  }

  JoinBuilder orWhere(String column, Object value,
      {CompOperator operator = CompOperator.equalTo}) {
    _conditions.add(_JoinValue(LogicalConnector.or, column, operator,
        WhereConditions._value(value, 'value')));
    return this;
  }

  JoinBuilder whereNull(String column) {
    _conditions.add(_JoinNull(LogicalConnector.and, column, isNull: true));
    return this;
  }

  JoinBuilder whereNotNull(String column) {
    _conditions.add(_JoinNull(LogicalConnector.and, column, isNull: false));
    return this;
  }

  JoinBuilder whereIn(String column, Iterable<Object> values) {
    _conditions.add(_JoinIn(column, List.unmodifiable(values), negated: false));
    return this;
  }

  JoinBuilder whereNotIn(String column, Iterable<Object> values) {
    _conditions.add(_JoinIn(column, List.unmodifiable(values), negated: true));
    return this;
  }

  void _applyTo(JoinClause join) {
    for (final condition in _conditions) {
      switch (condition) {
        case _JoinColumns(
            :final connector,
            :final first,
            :final operator,
            :final second
          ):
          join.on(first, operator.sql, second, connector.sql);
        case _JoinValue(
            :final connector,
            :final column,
            :final operator,
            :final value
          ):
          join.where(column, operator.sql, value, connector.sql);
        case _JoinNull(:final connector, :final column, :final isNull):
          isNull
              ? join.whereNull(column, connector.sql)
              : join.whereNotNull(column, connector.sql);
        case _JoinIn(:final column, :final values, :final negated):
          negated
              ? join.whereNotIn(column, values)
              : join.whereIn(column, values);
      }
    }
  }
}

sealed class _JoinCondition {
  const _JoinCondition();
}

final class _JoinColumns extends _JoinCondition {
  const _JoinColumns(this.connector, this.first, this.operator, this.second);
  final LogicalConnector connector;
  final String first;
  final CompOperator operator;
  final String second;
}

final class _JoinValue extends _JoinCondition {
  const _JoinValue(this.connector, this.column, this.operator, this.value);
  final LogicalConnector connector;
  final String column;
  final CompOperator operator;
  final Object value;
}

final class _JoinNull extends _JoinCondition {
  const _JoinNull(this.connector, this.column, {required this.isNull});
  final LogicalConnector connector;
  final String column;
  final bool isNull;
}

final class _JoinIn extends _JoinCondition {
  const _JoinIn(this.column, this.values, {required this.negated});
  final String column;
  final List<Object> values;
  final bool negated;
}

sealed class _Join {
  const _Join(this.table);
  final String table;
}

final class _SimpleJoin extends _Join {
  const _SimpleJoin(
      super.table, this.type, this.first, this.operator, this.second);
  final JoinType type;
  final String first;
  final CompOperator operator;
  final String second;
}

final class _BuiltJoin extends _Join {
  const _BuiltJoin(super.table, this.type, this.builder);
  final JoinType type;
  final JoinBuilder builder;
}

final class _CrossJoin extends _Join {
  const _CrossJoin(super.table);
}

/// `join (select ...) as alias on first = second`.
final class _SubJoin extends _Join {
  const _SubJoin(this.query, super.alias, this.type, this.first, this.operator,
      this.second);
  final QueryBuilder2 query;
  final JoinType type;
  final String first;
  final CompOperator operator;
  final String second;
}

/// `join lateral (select ...) as alias on ...` (`on true` without
/// conditions).
final class _LateralJoin extends _Join {
  const _LateralJoin(this.query, super.alias, this.type, this.builder);
  final QueryBuilder2 query;
  final JoinType type;
  final JoinBuilder? builder;
}

sealed class _SelectItem {
  const _SelectItem();
}

final class _SelectColumn extends _SelectItem {
  const _SelectColumn(this.column);
  final String column;
}

final class _SelectRaw extends _SelectItem {
  const _SelectRaw(this.sql, this.bindings);
  final String sql;
  final List<Object?> bindings;
}

final class _SelectSubquery extends _SelectItem {
  const _SelectSubquery(this.query, this.alias);
  final QueryBuilder2 query;
  final String alias;
}

sealed class _OrderItem {
  const _OrderItem();
}

final class _OrderColumn extends _OrderItem {
  const _OrderColumn(this.column, this.direction);
  final String column;
  final SortDirection direction;
}

final class _OrderRaw extends _OrderItem {
  const _OrderRaw(this.sql, this.bindings);
  final String sql;
  final List<Object?> bindings;
}

final class _OrderRandom extends _OrderItem {
  const _OrderRandom();
}

/// The `on conflict` action of [QueryBuilder2.insert] and
/// [QueryBuilder2.insertReturning] (MySQL: `on duplicate key update`).
///
/// ```dart
/// // Atomic sequence: insert the year or increment it.
/// final rows = await db.table2('sequencias').insertReturning(
///   {'ano': 2026, 'ultimo': 1},
///   onConflict: OnConflict.doUpdate(
///       columns: ['ano'], set: {'ultimo': db.raw('sequencias.ultimo + 1')}),
///   returning: ['ultimo'],
/// );
/// ```
final class OnConflict {
  /// `on conflict [(columns) | on constraint name] do nothing`.
  const OnConflict.doNothing({this.columns = const [], this.constraint})
      : set = null,
        whereRaw = null;

  /// `on conflict (columns) do update set ... [where whereRaw]`. Values in
  /// [set] are bound; a `db.raw(...)` value is SQL (e.g. `t.n + 1`).
  const OnConflict.doUpdate(
      {this.columns = const [],
      this.constraint,
      required Map<String, Object?> this.set,
      this.whereRaw});

  /// The unique columns of the conflict target.
  final List<String> columns;

  /// A named constraint as the conflict target (PostgreSQL).
  final String? constraint;

  /// The update; `null` means `do nothing`.
  final Map<String, Object?>? set;

  /// SQL appended as `where ...` to the update (PostgreSQL).
  final String? whereRaw;

  OnConflictClause _toClause() {
    if (columns.isNotEmpty && constraint != null) {
      throw ArgumentError(
          'OnConflict takes columns or a constraint, not both.');
    }
    final update = set;
    if (update != null) {
      if (update.isEmpty) {
        throw ArgumentError(
            'OnConflict.doUpdate needs at least one column in set.');
      }
      if (columns.isEmpty && constraint == null) {
        throw ArgumentError(
            'OnConflict.doUpdate needs the conflict columns or a constraint.');
      }
    }
    return OnConflictClause(
      columns: columns,
      constraint: constraint,
      doNothing: update == null,
      updateValues: update,
      updateWhereRaw: whereRaw,
    );
  }
}

/// A page of [QueryBuilder2.paginate], with the total row count.
final class PageResult {
  const PageResult(
      {required this.items,
      required this.total,
      required this.perPage,
      required this.currentPage});

  final List<Map<String, dynamic>> items;
  final int total;
  final int perPage;
  final int currentPage;

  int get lastPage => total == 0 ? 1 : (total + perPage - 1) ~/ perPage;
  bool get hasMorePages => currentPage < lastPage;

  /// Position of the first item (from 1), or `null` for an empty page.
  int? get from => items.isEmpty ? null : (currentPage - 1) * perPage + 1;
  int? get to =>
      items.isEmpty ? null : (currentPage - 1) * perPage + items.length;

  /// Laravel's JSON shape: `data`, `total`, `per_page`, `current_page`,
  /// `last_page`, `from`, `to`.
  Map<String, dynamic> toMap() => {
        'data': items,
        'total': total,
        'per_page': perPage,
        'current_page': currentPage,
        'last_page': lastPage,
        'from': from,
        'to': to,
      };
}

/// A page of [QueryBuilder2.simplePaginate] (no count query).
final class SimplePageResult {
  const SimplePageResult(
      {required this.items,
      required this.perPage,
      required this.currentPage,
      required this.hasMorePages});

  final List<Map<String, dynamic>> items;
  final int perPage;
  final int currentPage;
  final bool hasMorePages;

  Map<String, dynamic> toMap() => {
        'data': items,
        'per_page': perPage,
        'current_page': currentPage,
        'has_more_pages': hasMorePages,
      };
}

final class _Cte {
  const _Cte(this.name, this.query, this.columns,
      {required this.recursive, required this.materialized});
  final String name;
  final QueryBuilder2 query;
  final List<String>? columns;
  final bool recursive;
  final bool materialized;
}

final class _Union {
  const _Union(this.query, {required this.all});
  final QueryBuilder2 query;
  final bool all;
}

final class _Lock {
  const _Lock(
      {required this.forUpdate,
      required this.skipLocked,
      required this.noWait,
      this.of});
  final bool forUpdate;
  final bool skipLocked;
  final bool noWait;
  final List<String>? of;
}

/// Query builder with a Dart 3 API: named parameters with a fixed meaning,
/// enums for operators and directions, typed callbacks and typed results.
///
/// ```dart
/// final usuarios = await db
///     .table2('usuarios')
///     .select(['id', 'nome'])
///     .where('ativo', true)
///     .whereGreaterThanOrEqualTo('idade', 18)
///     .whereIn('perfil', ['administrador', 'operador'])
///     .whereNull('excluido_em')
///     .whereGroup((w) => w
///         .where('cidade', 'Rio das Ostras')
///         .orWhere('cidade', 'Macaé'))
///     .orderBy('nome')
///     .limit(50)
///     .get();
/// ```
///
/// It is compiled by the same grammars as [QueryBuilder] (PostgreSQL and
/// MySQL dialects, locks, `toRawSql`). For anything it does not cover yet,
/// [toQueryBuilder] returns an equivalent [QueryBuilder].
final class QueryBuilder2 with WhereConditions<QueryBuilder2> {
  QueryBuilder2(Connection connection, [String? table])
      : this.using(connection.query, table);

  /// A builder that lowers to the [QueryBuilder]s made by [newBaseQuery]
  /// (tests use it with a fake connection and a chosen grammar).
  QueryBuilder2.using(QueryBuilder Function() newBaseQuery, [String? table])
      : _newBaseQuery = newBaseQuery {
    if (table != null) from(table);
  }

  final QueryBuilder Function() _newBaseQuery;

  String? _table;
  QueryBuilder2? _fromSubquery;
  String? _fromAlias;
  final List<_SelectItem> _columns = [];
  bool _distinct = false;
  final List<_Join> _joins = [];
  @override
  final List<WhereClause> whereClauseList = [];
  final List<String> _groups = [];
  final List<_SelectRaw> _rawGroups = [];
  final List<WhereClause> _havings = [];
  final List<_OrderItem> _orders = [];
  int? _limit;
  int? _offset;
  _Lock? _lock;
  final List<_Cte> _ctes = [];
  final List<_Union> _unions = [];
  List<String>? _distinctOn;
  final List<AfterQueryCallback> _afterQuery = [];

  @override
  QueryBuilder2 get whereSelf => this;

  /// Adds a condition built elsewhere (a [WhereBuilder], a model query).
  QueryBuilder2 addWhereClause(WhereClause clause) {
    whereClauseList.add(clause);
    return this;
  }

  /// The where conditions, in order.
  List<WhereClause> get wheres => List.unmodifiable(whereClauseList);

  /// A builder on the same connection, e.g. for a subquery.
  QueryBuilder2 newQuery([String? table]) =>
      QueryBuilder2.using(_newBaseQuery, table);

  // ------------------------------------------------------------------ from

  /// `from table [as alias]`.
  QueryBuilder2 from(String table, {String? alias}) {
    _table = WhereConditions._column(table);
    _fromAlias = alias;
    _fromSubquery = null;
    return this;
  }

  /// `from (select ...) as alias`.
  QueryBuilder2 fromSubquery(QueryBuilder2 subquery, String alias) {
    _fromSubquery = subquery.clone();
    _fromAlias = alias;
    _table = null;
    return this;
  }

  // ---------------------------------------------------------------- select

  /// Replaces the selected columns (`'tabela.coluna'`, `'coluna as alias'`).
  QueryBuilder2 select(List<String> columns) {
    _columns
      ..clear()
      ..addAll(columns.map((c) => _SelectColumn(WhereConditions._column(c))));
    return this;
  }

  QueryBuilder2 addSelect(List<String> columns) {
    _columns
        .addAll(columns.map((c) => _SelectColumn(WhereConditions._column(c))));
    return this;
  }

  /// A selected SQL expression, e.g. `selectRaw('count(*) as total')`.
  QueryBuilder2 selectRaw(String sql, [List<Object?> bindings = const []]) {
    _columns.add(_SelectRaw(sql, List.unmodifiable(bindings)));
    return this;
  }

  /// `(select ...) as alias` in the select list.
  QueryBuilder2 selectSubquery(QueryBuilder2 subquery, String alias) {
    _columns.add(_SelectSubquery(subquery.clone(), alias));
    return this;
  }

  QueryBuilder2 distinct() {
    _distinct = true;
    return this;
  }

  /// `select distinct on (columns) ...` (PostgreSQL): the first row of each
  /// group of [columns], by the order of the query (which must start with
  /// the same columns).
  QueryBuilder2 distinctOn(List<String> columns) {
    if (columns.isEmpty) {
      throw ArgumentError.value(columns, 'columns', 'Must not be empty.');
    }
    _distinctOn = List.unmodifiable(columns.map(WhereConditions._column));
    return this;
  }

  // ----------------------------------------------------------------- joins

  /// `inner join table on first = second`.
  QueryBuilder2 join(String table, String first, String second,
      {CompOperator operator = CompOperator.equalTo,
      JoinType type = JoinType.inner}) {
    _joins.add(_SimpleJoin(
        WhereConditions._column(table),
        type,
        WhereConditions._column(first),
        operator,
        WhereConditions._column(second)));
    return this;
  }

  QueryBuilder2 leftJoin(String table, String first, String second,
          {CompOperator operator = CompOperator.equalTo}) =>
      join(table, first, second, operator: operator, type: JoinType.left);

  QueryBuilder2 rightJoin(String table, String first, String second,
          {CompOperator operator = CompOperator.equalTo}) =>
      join(table, first, second, operator: operator, type: JoinType.right);

  /// A join with several `on`/`where` conditions.
  QueryBuilder2 joinOn(String table, void Function(JoinBuilder join) build,
      {JoinType type = JoinType.inner}) {
    final builder = JoinBuilder();
    build(builder);
    if (builder._conditions.isEmpty) {
      throw ArgumentError('joinOn("$table") needs at least one condition.');
    }
    _joins.add(_BuiltJoin(WhereConditions._column(table), type, builder));
    return this;
  }

  QueryBuilder2 leftJoinOn(
          String table, void Function(JoinBuilder join) build) =>
      joinOn(table, build, type: JoinType.left);

  QueryBuilder2 crossJoin(String table) {
    _joins.add(_CrossJoin(WhereConditions._column(table)));
    return this;
  }

  /// `join (select ...) as alias on first = second`.
  QueryBuilder2 joinSub(
      QueryBuilder2 subquery, String alias, String first, String second,
      {CompOperator operator = CompOperator.equalTo,
      JoinType type = JoinType.inner}) {
    _joins.add(_SubJoin(
        subquery.clone(),
        WhereConditions._column(alias),
        type,
        WhereConditions._column(first),
        operator,
        WhereConditions._column(second)));
    return this;
  }

  QueryBuilder2 leftJoinSub(
          QueryBuilder2 subquery, String alias, String first, String second,
          {CompOperator operator = CompOperator.equalTo}) =>
      joinSub(subquery, alias, first, second,
          operator: operator, type: JoinType.left);

  /// `join lateral (select ...) as alias on ...` (PostgreSQL): the subquery
  /// can reference the columns of the tables before it, e.g. the last
  /// movement of each process. Without [on] the condition is `on true`.
  ///
  /// ```dart
  /// db.table2('processo as p').leftJoinLateral(
  ///     db.table2('andamento as a')
  ///         .whereColumn('a.cod_processo', 'p.cod_processo')
  ///         .orderByDescending('a.cod_andamento')
  ///         .limit(1),
  ///     'ultimo');
  /// ```
  QueryBuilder2 joinLateral(QueryBuilder2 subquery, String alias,
      {void Function(JoinBuilder join)? on, JoinType type = JoinType.inner}) {
    if (type == JoinType.right) {
      throw ArgumentError.value(
          type, 'type', 'LATERAL joins are inner or left.');
    }
    JoinBuilder? builder;
    if (on != null) {
      builder = JoinBuilder();
      on(builder);
    }
    _joins.add(_LateralJoin(
        subquery.clone(), WhereConditions._column(alias), type, builder));
    return this;
  }

  QueryBuilder2 leftJoinLateral(QueryBuilder2 subquery, String alias,
          {void Function(JoinBuilder join)? on}) =>
      joinLateral(subquery, alias, on: on, type: JoinType.left);

  // ------------------------------------------------- group, having, order

  QueryBuilder2 groupBy(List<String> columns) {
    _groups.addAll(columns.map(WhereConditions._column));
    return this;
  }

  QueryBuilder2 groupByRaw(String sql, [List<Object?> bindings = const []]) {
    _rawGroups.add(_SelectRaw(sql, List.unmodifiable(bindings)));
    return this;
  }

  /// `having column = ?`, or the comparison given by [operator]. [column] is
  /// an identifier (a grouped column; MySQL also accepts a select alias).
  /// Aggregates go through [havingRaw]: `havingRaw('sum(total) > ?', [1000])`
  /// (PostgreSQL does not accept select aliases in HAVING).
  QueryBuilder2 having(String column, Object value,
      {CompOperator operator = CompOperator.equalTo}) {
    _havings.add(WhereClause(
        LogicalConnector.and,
        ComparisonPredicate(
            column, operator, WhereConditions._value(value, 'value'))));
    return this;
  }

  QueryBuilder2 orHaving(String column, Object value,
      {CompOperator operator = CompOperator.equalTo}) {
    _havings.add(WhereClause(
        LogicalConnector.or,
        ComparisonPredicate(
            column, operator, WhereConditions._value(value, 'value'))));
    return this;
  }

  QueryBuilder2 havingBetween(String column, Object low, Object high) {
    _havings.add(
        WhereClause(LogicalConnector.and, BetweenPredicate(column, low, high)));
    return this;
  }

  QueryBuilder2 havingRaw(String sql, [List<Object?> bindings = const []]) {
    _havings.add(WhereClause(
        LogicalConnector.and, RawPredicate(sql, List.unmodifiable(bindings))));
    return this;
  }

  QueryBuilder2 orHavingRaw(String sql, [List<Object?> bindings = const []]) {
    _havings.add(WhereClause(
        LogicalConnector.or, RawPredicate(sql, List.unmodifiable(bindings))));
    return this;
  }

  QueryBuilder2 orderBy(String column,
      {SortDirection direction = SortDirection.ascending}) {
    _orders.add(_OrderColumn(WhereConditions._column(column), direction));
    return this;
  }

  QueryBuilder2 orderByDescending(String column) =>
      orderBy(column, direction: SortDirection.descending);

  QueryBuilder2 orderByRaw(String sql, [List<Object?> bindings = const []]) {
    _orders.add(_OrderRaw(sql, List.unmodifiable(bindings)));
    return this;
  }

  /// Removes every order.
  QueryBuilder2 reorder() {
    _orders.clear();
    return this;
  }

  /// `order by column desc` (default `created_at`).
  QueryBuilder2 latest([String column = 'created_at']) =>
      orderBy(column, direction: SortDirection.descending);

  /// `order by column asc` (default `created_at`).
  QueryBuilder2 oldest([String column = 'created_at']) => orderBy(column);

  /// `order by random()` (PostgreSQL) / `rand()` (MySQL).
  QueryBuilder2 inRandomOrder() {
    _orders.add(const _OrderRandom());
    return this;
  }

  /// Orders by a column chosen by the client without putting its text in the
  /// SQL (see QueryBuilder.orderByInput): [field] is looked up in [allowed]
  /// (`{'nome': 'c.nom_cgm'}`; a value can also be a list of columns); a
  /// null, blank or unknown [field] orders by [fallback] (a column or a list),
  /// or adds no order without one. [direction] `desc`/`descending` (any case)
  /// is descending, anything else ascending.
  QueryBuilder2 orderByInput(String? field, String? direction,
      {required Map<String, Object> allowed,
      Object? fallback,
      SortDirection fallbackDirection = SortDirection.ascending}) {
    final key = field?.trim();
    final target = key == null || key.isEmpty ? null : allowed[key];
    if (target == null) {
      if (fallback == null) return this;
      return _orderByTargets(fallback, fallbackDirection, 'fallback');
    }
    return _orderByTargets(
        target,
        QueryBuilder.inputDirection(direction) == SqlSort.desc
            ? SortDirection.descending
            : SortDirection.ascending,
        'allowed');
  }

  QueryBuilder2 _orderByTargets(
      Object target, SortDirection direction, String name) {
    final targets = target is List ? target : [target];
    if (targets.isEmpty ||
        targets.any((t) => t is! String || t.trim().isEmpty)) {
      throw ArgumentError.value(
          target, name, 'Expected a column or a list of columns.');
    }
    for (final column in targets) {
      orderBy(column as String, direction: direction);
    }
    return this;
  }

  // --------------------------------------------------------- limit, lock

  QueryBuilder2 limit(int count) {
    if (count < 0) throw ArgumentError.value(count, 'count', 'Must be >= 0.');
    _limit = count;
    return this;
  }

  QueryBuilder2 offset(int count) {
    if (count < 0) throw ArgumentError.value(count, 'count', 'Must be >= 0.');
    _offset = count;
    return this;
  }

  /// Page [page] (from 1) of [perPage] rows.
  QueryBuilder2 forPage(int page, int perPage) {
    if (page < 1) throw ArgumentError.value(page, 'page', 'Must be >= 1.');
    return offset((page - 1) * perPage).limit(perPage);
  }

  /// `for update [of ...] [skip locked | nowait]`.
  QueryBuilder2 lockForUpdate(
      {bool skipLocked = false, bool noWait = false, List<String>? of}) {
    _lock =
        _Lock(forUpdate: true, skipLocked: skipLocked, noWait: noWait, of: of);
    return this;
  }

  /// `for share` (PostgreSQL) / `lock in share mode` (MySQL).
  QueryBuilder2 sharedLock(
      {bool skipLocked = false, bool noWait = false, List<String>? of}) {
    _lock =
        _Lock(forUpdate: false, skipLocked: skipLocked, noWait: noWait, of: of);
    return this;
  }

  // ------------------------------------------------------ unions, CTEs

  /// `union select ...` (duplicates removed). With unions, [orderBy],
  /// [limit] and [offset] of this builder apply to the combined result; a
  /// part with its own order or limit is wrapped as
  /// `select * from (part) as union_part`.
  QueryBuilder2 union(QueryBuilder2 other) {
    _unions.add(_Union(other.clone(), all: false));
    return this;
  }

  /// `union all select ...` (duplicates kept).
  QueryBuilder2 unionAll(QueryBuilder2 other) {
    _unions.add(_Union(other.clone(), all: true));
    return this;
  }

  /// `with name [(columns)] as [materialized] (query) select ...`.
  /// [materialized] is PostgreSQL only.
  QueryBuilder2 withExpression(String name, QueryBuilder2 query,
      {List<String>? columns, bool materialized = false}) {
    _ctes.add(_Cte(WhereConditions._column(name), query.clone(), columns,
        recursive: false, materialized: materialized));
    return this;
  }

  /// `with recursive name [(columns)] as (anchor union all step)`; build the
  /// query with [unionAll], referencing [name] as a table in the step.
  QueryBuilder2 withRecursiveExpression(String name, QueryBuilder2 query,
      {List<String>? columns}) {
    _ctes.add(_Cte(WhereConditions._column(name), query.clone(), columns,
        recursive: true, materialized: false));
    return this;
  }

  bool get _hasWindow =>
      _orders.isNotEmpty || _limit != null || _offset != null;

  // --------------------------------------------------------- conditional

  /// Runs [callback] on the rows of [get] (and [first], [paginate],
  /// [chunk]...) after the query; it may change them in place or return new
  /// ones (`null` keeps them). Not run for aggregates such as [count].
  QueryBuilder2 afterQuery(AfterQueryCallback callback) {
    _afterQuery.add(callback);
    return this;
  }

  /// Applies [then] when [condition] is true, otherwise [otherwise].
  QueryBuilder2 when(bool condition, void Function(QueryBuilder2 query) then,
      [void Function(QueryBuilder2 query)? otherwise]) {
    if (condition) {
      then(this);
    } else {
      otherwise?.call(this);
    }
    return this;
  }

  /// Applies [then] with [value] when it is not null, e.g. optional filters:
  /// `.whenNotNull(filtro.situacao, (q, s) => q.where('situacao', s))`.
  QueryBuilder2 whenNotNull<T extends Object>(
      T? value, void Function(QueryBuilder2 query, T value) then) {
    if (value != null) then(this, value);
    return this;
  }

  // ------------------------------------------------------------ inspect

  /// The SQL with `?` placeholders.
  String toSql() => toQueryBuilder().toSql();

  /// The bindings, in placeholder order.
  List<Object?> getBindings() =>
      List<Object?>.of(toQueryBuilder().getBindings());

  /// The SQL with the bindings inlined, for logs only.
  String toRawSql() => toQueryBuilder().toRawSql();

  /// An independent copy.
  QueryBuilder2 clone() {
    final copy = QueryBuilder2.using(_newBaseQuery)
      .._table = _table
      .._fromSubquery = _fromSubquery
      .._fromAlias = _fromAlias
      .._distinct = _distinct
      .._limit = _limit
      .._offset = _offset
      .._lock = _lock
      .._distinctOn = _distinctOn;
    copy._afterQuery.addAll(_afterQuery);
    copy._ctes.addAll(_ctes);
    copy._unions.addAll(_unions);
    copy._columns.addAll(_columns);
    copy._joins.addAll(_joins);
    copy.whereClauseList.addAll(whereClauseList);
    copy._groups.addAll(_groups);
    copy._rawGroups.addAll(_rawGroups);
    copy._havings.addAll(_havings);
    copy._orders.addAll(_orders);
    return copy;
  }

  // ------------------------------------------------------------- execute

  /// The rows.
  Future<List<Map<String, dynamic>>> get({Duration? timeout}) =>
      toQueryBuilder().get(const ['*'], timeout?.inSeconds);

  /// The first row, or `null`.
  Future<Map<String, dynamic>?> first({Duration? timeout}) =>
      toQueryBuilder().first(const ['*'], timeout?.inSeconds);

  /// The first row; throws [RecordsNotFoundException] when there is none.
  Future<Map<String, dynamic>> firstOrFail({Duration? timeout}) async {
    final row = await first(timeout: timeout);
    if (row == null) throw RecordsNotFoundException();
    return row;
  }

  /// The rows one by one from a server-side cursor (dpgsql; other drivers
  /// throw [UnsupportedError]); memory stays about constant.
  Stream<Map<String, dynamic>> cursor({int? fetchSize}) =>
      toQueryBuilder().cursor(fetchSize);

  /// The rows in pages of [size] (LIMIT/OFFSET); [callback] returns `false`
  /// to stop. Order the query (and prefer [chunkById] on large tables).
  Future<bool> chunk(
          int size,
          FutureOr<bool> Function(List<Map<String, dynamic>> rows, int page)
              callback) =>
      toQueryBuilder().chunk(size, callback);

  /// The rows in pages of [size] by keyset pagination on [column] (`where
  /// column > last order by column`); [alias] is the key in the rows when it
  /// differs. [callback] returns `false` to stop.
  Future<bool> chunkById(int size,
      FutureOr<bool> Function(List<Map<String, dynamic>> rows) callback,
      {String column = 'id', String? alias, bool descending = false}) {
    final query = toQueryBuilder();
    return descending
        ? query.chunkByIdDesc(size, callback, column: column, alias: alias)
        : query.chunkById(size, callback, column: column, alias: alias);
  }

  /// Rows of `EXPLAIN` ([analyze]: `EXPLAIN ANALYZE`, which runs the query).
  Future<List<Map<String, dynamic>>> explain({bool analyze = false}) =>
      toQueryBuilder().explain(analyze: analyze);

  /// Keyset pagination on the orders of the query (see
  /// QueryBuilder.cursorPaginate): order by unique columns, selected in the
  /// result; pass the [CursorPage.nextCursor]/[CursorPage.previousCursor] of
  /// the previous page as [cursor].
  Future<CursorPage> cursorPaginate({int perPage = 15, String? cursor}) =>
      toQueryBuilder().cursorPaginate(perPage: perPage, cursor: cursor);

  /// [paginate] in one query with `count(*) over ()` (opt-in; see
  /// QueryBuilder.paginateWithWindowCount: not always faster than the
  /// separate count).
  Future<PageResult> paginateWithWindowCount(
      {required int page, int perPage = 15}) async {
    _checkPage(page, perPage);
    final result = await toQueryBuilder()
        .paginateWithWindowCount(page: page, perPage: perPage);
    return PageResult(
        items: result.items(),
        total: result.total(),
        perPage: perPage,
        currentPage: page);
  }

  /// The only row; throws [RecordsNotFoundException] or
  /// [MultipleRecordsFoundException].
  Future<Map<String, dynamic>> sole() => toQueryBuilder().sole();

  /// [column] of the first row, or `null`.
  Future<T?> value<T>(String column) async =>
      await toQueryBuilder().value(column) as T?;

  /// [column] of every row.
  Future<List<T>> pluck<T>(String column) async {
    final rows = await (clone()..select([column])).get();
    final key = _resultKey(column);
    return [for (final row in rows) row[key] as T];
  }

  Future<int> count([String column = '*']) => toQueryBuilder().count(column);

  Future<bool> exists() => toQueryBuilder().exists();

  Future<bool> doesntExist() async => !await exists();

  Future<num?> sum(String column) => toQueryBuilder().sum(column);
  Future<num?> avg(String column) => toQueryBuilder().avg(column);
  Future<num?> min(String column) => toQueryBuilder().min(column);
  Future<num?> max(String column) => toQueryBuilder().max(column);

  /// The total rows (one count query) and page [page] (from 1).
  Future<PageResult> paginate({required int page, int perPage = 15}) async {
    _checkPage(page, perPage);
    final total = await toQueryBuilder().getCountForPagination();
    final items = total == 0
        ? <Map<String, dynamic>>[]
        : await clone().forPage(page, perPage).get();
    return PageResult(
        items: items, total: total, perPage: perPage, currentPage: page);
  }

  /// Page [page] without a count query (reads one extra row to know whether
  /// there is a next page).
  Future<SimplePageResult> simplePaginate(
      {required int page, int perPage = 15}) async {
    _checkPage(page, perPage);
    final rows = await (clone()
          ..offset((page - 1) * perPage)
          ..limit(perPage + 1))
        .get();
    final more = rows.length > perPage;
    return SimplePageResult(
        items: more ? rows.sublist(0, perPage) : rows,
        perPage: perPage,
        currentPage: page,
        hasMorePages: more);
  }

  static void _checkPage(int page, int perPage) {
    if (page < 1) throw ArgumentError.value(page, 'page', 'Must be >= 1.');
    if (perPage < 1) {
      throw ArgumentError.value(perPage, 'perPage', 'Must be >= 1.');
    }
  }

  /// Inserts one row; returns the rows inserted (0 when [onConflict] skipped
  /// it).
  Future<int> insert(Map<String, Object?> values,
      {OnConflict? onConflict, Duration? timeout}) async {
    final query = toQueryBuilder();
    if (onConflict != null) query.onConflictProp = onConflict._toClause();
    final result = await query.insert(values, timeout) as PDOResults;
    return result.rowsAffected;
  }

  /// Inserts one row and returns the [returning] columns of the inserted (or
  /// conflict-updated) row (PostgreSQL; MySQL throws [UnsupportedError]).
  Future<List<Map<String, dynamic>>> insertReturning(
      Map<String, Object?> values,
      {List<String> returning = const ['*'],
      OnConflict? onConflict}) async {
    final query = toQueryBuilder()..returningProp = List.of(returning);
    if (onConflict != null) query.onConflictProp = onConflict._toClause();
    final result = await query.insert(values) as PDOResults;
    return result.rows;
  }

  /// Inserts several rows in one statement; every row must have the same
  /// columns. Returns the rows inserted.
  Future<int> insertMany(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return 0;
    final query = toQueryBuilder();
    final columns = _checkRows(rows);
    final sql = query.grammar.compileInsertRows(query, rows);
    return query.connection.affectingStatement(sql, [
      for (final row in rows)
        for (final c in columns) row[c]
    ]);
  }

  /// Inserts the rows, skipping those that violate a unique key
  /// (`on conflict do nothing` / `insert ignore`). Returns the rows inserted.
  Future<int> insertOrIgnore(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return 0;
    _checkRows(rows);
    return toQueryBuilder().insertOrIgnore(rows);
  }

  /// Inserts the rows; a row that conflicts on [uniqueBy] updates the
  /// [update] columns (default: every column not in [uniqueBy]) with the
  /// values it tried to insert. Returns the affected rows.
  Future<int> upsert(List<Map<String, Object?>> rows,
      {required List<String> uniqueBy, List<String>? update}) async {
    if (rows.isEmpty) return 0;
    if (uniqueBy.isEmpty) {
      throw ArgumentError.value(uniqueBy, 'uniqueBy', 'Must not be empty.');
    }
    final columns = _checkRows(rows);
    final query = toQueryBuilder();
    Map<String, dynamic>? set;
    if (update != null) {
      set = {};
      for (final column in update) {
        if (!columns.contains(column)) {
          throw ArgumentError.value(
              column, 'update', 'Not a column of the rows.');
        }
        set[column] =
            QueryExpression(query.grammar.upsertInsertedValue(column));
      }
    }
    return query.upsert(rows, uniqueBy, set);
  }

  /// Updates the matching rows and returns their [returning] columns
  /// (PostgreSQL; MySQL throws [UnsupportedError]).
  Future<List<Map<String, dynamic>>> updateReturning(
      Map<String, Object?> values,
      {List<String> returning = const ['*']}) {
    final query = toQueryBuilder();
    final grammar = query.grammar;
    final sql = grammar.compileUpdate(query, values) +
        grammar.compileReturning(returning);
    final bindings = grammar.prepareBindingsForUpdate(query, values);
    return query.connection.select(sql, query.cleanBindings(bindings), false);
  }

  /// Deletes the matching rows and returns their [returning] columns
  /// (PostgreSQL; MySQL throws [UnsupportedError]).
  Future<List<Map<String, dynamic>>> deleteReturning(
      {List<String> returning = const ['*']}) {
    final query = toQueryBuilder();
    final grammar = query.grammar;
    final sql =
        grammar.compileDelete(query) + grammar.compileReturning(returning);
    final bindings = grammar.prepareBindingsForDelete(query);
    return query.connection.select(sql, query.cleanBindings(bindings), false);
  }

  /// The columns of [rows]; throws when the rows differ or contain raw SQL.
  static List<String> _checkRows(List<Map<String, Object?>> rows) {
    final columns = rows.first.keys.toList();
    if (columns.isEmpty) {
      throw ArgumentError.value(rows, 'rows', 'A row has no columns.');
    }
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length != columns.length || !columns.every(row.containsKey)) {
        throw ArgumentError.value(rows, 'rows',
            'Row $i has columns ${row.keys.toList()}, expected $columns.');
      }
      for (final value in row.values) {
        if (value is QueryExpression) {
          throw ArgumentError.value(value, 'rows',
              'Raw SQL is not supported in multi-row inserts; use insert().');
        }
      }
    }
    return columns;
  }

  /// Inserts and returns the generated [sequence] column.
  Future<T?> insertGetId<T>(Map<String, Object?> values,
          {String sequence = 'id'}) async =>
      await toQueryBuilder().insertGetId(values, sequence) as T?;

  /// Updates the matching rows; returns how many.
  Future<int> update(Map<String, Object?> values, {Duration? timeout}) =>
      toQueryBuilder().update(values, timeout);

  /// Bulk insert: COPY when the driver supports it, multi-row INSERTs
  /// otherwise (see QueryBuilder.copyInto). Returns the rows inserted.
  Future<int> copyInto(Iterable<Map<String, Object?>> rows,
          {List<String>? columns, int batchSize = 1000}) =>
      toQueryBuilder().copyInto(rows, columns: columns, batchSize: batchSize);

  /// Bulk insert with one array parameter per column (`unnest`, PostgreSQL;
  /// see QueryBuilder.insertUnnest). [types] are the PostgreSQL types.
  Future<int> insertUnnest(Iterable<Map<String, Object?>> rows,
          {required Map<String, String> types}) =>
      toQueryBuilder().insertUnnest(rows, types: types);

  /// The next number of [column] in the rows of this query, under a lock
  /// that lasts until the transaction ends (see QueryBuilder.nextValue).
  Future<int> nextValue(String column, {int start = 1, bool lock = true}) =>
      toQueryBuilder().nextValue(column, start: start, lock: lock);

  /// Inserts [attributes] + [values], or returns the row of [attributes]
  /// when a unique index refuses the insert (see QueryBuilder.createOrFirst).
  Future<Map<String, dynamic>> createOrFirst(Map<String, Object?> attributes,
          [Map<String, Object?> values = const {}]) =>
      toQueryBuilder().createOrFirst(attributes, values);

  /// The row of [attributes], or [createOrFirst] when there is none.
  Future<Map<String, dynamic>> firstOrCreate(Map<String, Object?> attributes,
          [Map<String, Object?> values = const {}]) =>
      toQueryBuilder().firstOrCreate(attributes, values);

  /// PostgreSQL `LOCK TABLE` of this table until the transaction ends (see
  /// QueryBuilder.lockTable).
  Future<void> lockTable(TableLockMode mode,
          {bool noWait = false, Duration? timeout}) =>
      toQueryBuilder().lockTable(mode, noWait: noWait, timeout: timeout);

  /// Laravel's updateFrom: the inner joins become `update ... from ...`
  /// (PostgreSQL); the same SQL as [update] here.
  Future<int> updateFrom(Map<String, Object?> values, {Duration? timeout}) =>
      update(values, timeout: timeout);

  /// `insert into table (columns) select ...`; returns the rows inserted.
  Future<int> insertUsing(List<String> columns, QueryBuilder2 select) async {
    if (columns.isEmpty) {
      throw ArgumentError.value(columns, 'columns', 'Must not be empty.');
    }
    final result = await toQueryBuilder()
        .insertUsing(List<String>.of(columns), select.toQueryBuilder());
    return result is PDOResults ? result.rowsAffected : 0;
  }

  /// Deletes the matching rows; returns how many.
  Future<int> delete({Duration? timeout}) =>
      toQueryBuilder().delete(null, timeout);

  Future<int> increment(String column, [num amount = 1]) =>
      toQueryBuilder().increment(column, amount);

  Future<int> decrement(String column, [num amount = 1]) =>
      toQueryBuilder().decrement(column, amount);

  /// Streams every row by keyset pagination on [column].
  Stream<Map<String, dynamic>> lazyById(
          {int chunkSize = 1000, String column = 'id'}) =>
      toQueryBuilder().lazyById(chunkSize, column);

  // ------------------------------------------------------------ lowering

  /// An equivalent [QueryBuilder] (a new one on every call), compiled by the
  /// same grammar. Use it for features this builder does not expose yet.
  QueryBuilder toQueryBuilder() {
    final query = _newBaseQuery();

    for (final cte in _ctes) {
      query.withExpression(cte.name, cte.query.toQueryBuilder(), cte.columns,
          cte.recursive, cte.materialized);
    }

    final fromSubquery = _fromSubquery;
    if (fromSubquery != null) {
      query.fromSub(fromSubquery.toQueryBuilder(), _fromAlias!);
    } else if (_table != null) {
      query.from(_table, _fromAlias);
    }

    for (final item in _columns) {
      switch (item) {
        case _SelectColumn(:final column):
          query.addSelect(column);
        case _SelectRaw(:final sql, :final bindings):
          query.selectRaw(sql, bindings);
        case _SelectSubquery(query: final subquery, :final alias):
          query.selectSub(subquery.toQueryBuilder(), alias);
      }
    }
    if (_distinct) query.distinct();
    final distinctOn = _distinctOn;
    if (distinctOn != null) query.distinctOn(List<String>.of(distinctOn));
    query.afterQueryCallbacks.addAll(_afterQuery);

    for (final join in _joins) {
      switch (join) {
        case _SimpleJoin(
            :final table,
            :final type,
            :final first,
            :final operator,
            :final second
          ):
          query.join(table, first, operator.sql, second, type.sql);
        case _BuiltJoin(:final table, :final type, :final builder):
          query.join(table, (JoinClause clause) => builder._applyTo(clause),
              null, null, type.sql);
        case _CrossJoin(:final table):
          query.crossJoin(table);
        case _SubJoin(
            query: final subquery,
            table: final alias,
            :final type,
            :final first,
            :final operator,
            :final second
          ):
          query.joinSub(subquery.toQueryBuilder(), alias, first, operator.sql,
              second, type.sql);
        case _LateralJoin(
            query: final subquery,
            table: final alias,
            :final type,
            :final builder
          ):
          void on(JoinClause clause) => builder?._applyTo(clause);
          type == JoinType.left
              ? query.leftJoinLateral(subquery.toQueryBuilder(), alias, on)
              : query.joinLateral(subquery.toQueryBuilder(), alias, on);
      }
    }

    _applyWheres(query, whereClauseList);

    if (_groups.isNotEmpty) query.groupBy(List<String>.of(_groups));
    for (final raw in _rawGroups) {
      query.groupByRaw(raw.sql, raw.bindings);
    }
    _applyHavings(query, _havings);

    // Unions come before the orders and limits: the QueryBuilder then
    // applies those to the combined result.
    for (final union in _unions) {
      final part = union.query._hasWindow || union.query._lock != null
          ? newQuery().fromSubquery(union.query, 'union_part')
          : union.query;
      query.union(part.toQueryBuilder(), union.all);
    }

    for (final order in _orders) {
      switch (order) {
        case _OrderColumn(:final column, :final direction):
          query.orderBy(column, direction.sql);
        case _OrderRaw(:final sql, :final bindings):
          query.orderByRaw(sql, bindings);
        case _OrderRandom():
          query.inRandomOrder();
      }
    }

    if (_offset != null) query.offset(_offset!);
    if (_limit != null) query.limit(_limit!);

    final lock = _lock;
    if (lock != null) {
      if (lock.forUpdate) {
        query.lockForUpdate(
            skipLocked: lock.skipLocked, noWait: lock.noWait, of: lock.of);
      } else {
        query.sharedLock(
            skipLocked: lock.skipLocked, noWait: lock.noWait, of: lock.of);
      }
    }
    return query;
  }

  static void _applyWheres(QueryBuilder query, List<WhereClause> clauses) {
    for (final clause in clauses) {
      final boolean = clause.connector.sql;
      switch (clause.predicate) {
        case ComparisonPredicate(:final column, :final operator, :final value):
          _basic(query, column, operator.sql, value, boolean);
        case SqlOperatorPredicate(:final column, :final operator, :final value):
          _basic(query, column, _checkSqlOperator(query, operator), value,
              boolean);
        case ColumnComparisonPredicate(
            :final first,
            :final operator,
            :final second
          ):
          query.whereColumn(first, operator.sql, second, boolean);
        case NullPredicate(:final column, :final isNull):
          query.whereNull(column, boolean, !isNull);
        case InPredicate(:final column, :final values, :final negated):
          query.whereIn(column, List<Object>.of(values), boolean, negated);
        case InSubqueryPredicate(
            :final column,
            :final subquery,
            :final negated
          ):
          query.whereInExistingQuery(
              column, subquery.toQueryBuilder(), boolean, negated);
        case BetweenPredicate(
            :final column,
            :final low,
            :final high,
            :final negated
          ):
          query.whereBetween(column, [low, high], boolean, negated);
        case LikePredicate(
            :final column,
            :final pattern,
            :final caseSensitive,
            :final negated,
            :final unaccent,
            :final lower
          ):
          query.whereLike(column, pattern,
              caseSensitive: caseSensitive,
              unaccent: unaccent,
              lower: lower,
              boolean: boolean,
              not: negated);
        case DatePartPredicate(
            :final column,
            :final part,
            :final operator,
            :final value
          ):
          query.addDateBasedWhere(
              part.whereType, column, operator.sql, value, boolean);
        case TupleInPredicate(:final columns, :final tuples, :final negated):
          query.whereInTuple(columns, tuples, boolean, negated);
        case RowValuesPredicate(:final columns, :final operator, :final values):
          query.whereRowValues(columns, operator.sql, values, boolean);
        case AnyArrayPredicate(
            :final column,
            :final values,
            :final elementType,
            :final negated
          ):
          query.whereAnyArray(column, values,
              elementType: elementType, boolean: boolean, not: negated);
        case BetweenColumnsPredicate(
            :final column,
            :final low,
            :final high,
            :final negated
          ):
          query.whereBetweenColumns(column, [low, high], boolean, negated);
        case ValueBetweenPredicate(
            :final value,
            :final low,
            :final high,
            :final negated
          ):
          query.whereValueBetween(value, [low, high], boolean, negated);
        case JsonContainsPredicate(:final column, :final value, :final negated):
          query.whereJsonContains(column, value, boolean, negated);
        case JsonLengthPredicate(:final column, :final operator, :final length):
          query.whereJsonLength(column, operator.sql, length, boolean);
        case ArrayOperatorPredicate(
            :final column,
            :final operator,
            :final values
          ):
          query.wheresProp.add({
            'type': 'ArrayOp',
            'column': column,
            'operator': operator.sql,
            'value': List<Object?>.of(values),
            'boolean': boolean,
          });
          query.addBinding([List<Object?>.of(values)], 'where');
        case FullTextPredicate(:final columns, :final value, :final options):
          query.whereFullText(List<String>.of(columns), value,
              Map<String, dynamic>.of(options), boolean);
        case GroupPredicate(clauses: final inner, :final negated):
          query.whereNested(
              (QueryBuilder nested) => _applyWheres(nested, inner),
              negated ? '$boolean not' : boolean);
        case ExistsPredicate(:final subquery, :final negated):
          final sub = subquery.toQueryBuilder();
          query.wheresProp.add({
            'type': negated ? SqlWhereType.notExists : SqlWhereType.exists,
            'operator': null,
            'query': sub,
            'boolean': boolean,
          });
          query.addBinding(sub.getBindings(), 'where');
        case RawPredicate(:final sql, :final bindings):
          query.whereRaw(sql, List<Object?>.of(bindings), boolean);
      }
    }
  }

  static String _checkSqlOperator(QueryBuilder query, String operator) {
    final normalized = operator.toLowerCase().split(RegExp(r'\s+')).join(' ');
    if (normalized.contains('?')) {
      throw ArgumentError.value(
          operator,
          'operator',
          '"?" is the bind placeholder; for JSON keys use '
              "whereRaw('jsonb_exists(column, ?)', [key]).");
    }
    if (!query.grammar.predicateOperators.contains(normalized)) {
      throw ArgumentError.value(
          operator, 'operator', 'Not a predicate operator of this grammar.');
    }
    return normalized;
  }

  /// `column operator ?` written directly: the value is one binding and is
  /// never read as an operator, a subquery or a null check.
  static void _basic(QueryBuilder query, String column, String operator,
      Object? value, String boolean) {
    query.wheresProp.add({
      'type': SqlWhereType.basic,
      'column': column,
      'operator': operator,
      'value': value,
      'boolean': boolean,
    });
    query.addBinding([value], 'where');
  }

  static void _applyHavings(QueryBuilder query, List<WhereClause> clauses) {
    for (final clause in clauses) {
      final boolean = clause.connector.sql;
      switch (clause.predicate) {
        case ComparisonPredicate(:final column, :final operator, :final value):
          query.having(column, operator.sql, value, boolean);
        case BetweenPredicate(
            :final column,
            :final low,
            :final high,
            :final negated
          ):
          query.havingBetween(column, [low, high], boolean, negated);
        case RawPredicate(:final sql, :final bindings):
          query.havingRaw(sql, List<Object?>.of(bindings), boolean);
        default:
          throw StateError('Unsupported having: ${clause.predicate}');
      }
    }
  }

  /// The key of [column] in a result row (`t.c as a` -> `a`, `t.c` -> `c`).
  static String _resultKey(String column) {
    final alias = RegExp(r'\s+as\s+', caseSensitive: false);
    final parts = column.split(alias);
    final name = parts.last.trim();
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1) : name;
  }
}
