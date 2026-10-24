import 'package:eloquent/eloquent.dart';

/// The `on`/`where` conditions of one join of [QueryBuilder].
///
/// Unlike Laravel 5.3+, it does not extend the query builder, so a join
/// cannot nest arbitrary where groups; [QueryBuilder2.joinOn] with
/// [JoinBuilder] is the typed alternative.
class JoinClause {
  /// The type of join, e.g. `inner`, `left` or `cross`.
  String type;

  /// The joined table: a name or a [QueryExpression].
  dynamic table;

  /// The conditions of the join, as maps read by the grammar.
  List<Map<String, dynamic>> clauses = [];

  /// The values bound by the conditions of the join.
  List bindingsLocal = [];

  /// Whether the join is `join lateral` (PostgreSQL).
  bool isLateral; // <-- Adicionado

  /// Adds the condition `on TRUE`, e.g. for a lateral join.
  JoinClause onTrue([String boolean = SqlBool.and]) {
    return this.on(QueryExpression('TRUE'), null, null, boolean, false);
  }

  /// Creates a join of [type] on [table].
  JoinClause(this.type, this.table,
      [QueryBuilder? parentQuery, this.isLateral = false]) {
    // Unlike Laravel's, this join does not extend the query builder, so
    // [parentQuery] is not used.
  }

  /// Adds an `on` condition comparing the column [first] with [second].
  ///
  /// Conditions chain:
  ///
  /// ```dart
  /// join.on('contacts.user_id', '=', 'users.id')
  ///     .on('contacts.info_id', '=', 'info.id');
  /// ```
  ///
  /// produces:
  ///
  /// ```sql
  /// on "contacts"."user_id" = "users"."id"
  ///   and "contacts"."info_id" = "info"."id"
  /// ```
  ///
  /// When [first] is a function, it receives a new [JoinClause] whose
  /// conditions become a nested group (see [nest]). With [where], [second]
  /// is a bound value instead of a column.
  JoinClause on(dynamic first,
      [String? operator,
      dynamic second,
      String boolean = SqlBool.and,
      bool where = false]) {
    if (first is Function) {
      return this.nest(first, boolean);
    }

    if (where) {
      final isIn =
          operator == SqlOperator.inList || operator == SqlOperator.notInList;
      if (isIn && second is Iterable) {
        // `in (?, ?, ...)`: one binding per value (a raw value is inlined by
        // the grammar); the grammar compiles the placeholders from the list.
        second = List.of(second);
        this.bindingsLocal.addAll(
            (second as List).where((value) => value is! QueryExpression));
      } else {
        // The usual case: one placeholder, one binding.
        this.bindingsLocal.add(second);
      }
    }

    var nested = false;

    this.clauses.add({
      'first': first,
      'operator': operator,
      'second': second,
      'boolean': boolean,
      'where': where,
      'nested': nested
    });

    return this;
  }

  /// Adds an `or on` condition; see [on].
  JoinClause orOn(dynamic first, [String? operator, dynamic second]) {
    return this.on(first, operator, second, SqlBool.or);
  }

  /// Adds a condition comparing the column [first] with the bound value
  /// [second]: `first <operator> ?`.
  JoinClause where(dynamic first,
      [String? operator, dynamic second, String boolean = SqlBool.and]) {
    return this.on(first, operator, second, boolean, true);
  }

  /// Adds `or first <operator> ?`; see [where].
  JoinClause orWhere(dynamic first, [String? operator, dynamic second]) {
    return this.on(first, operator, second, SqlBool.or, true);
  }

  /// Adds the condition `column is null`.
  JoinClause whereNull(String column, [String boolean = SqlBool.and]) {
    return this.on(column, SqlOperator.isOperator, QueryExpression('null'),
        boolean, false);
  }

  /// Adds the condition `or column is null`.
  JoinClause orWhereNull(String column) {
    return this.whereNull(column, SqlBool.or);
  }

  /// Adds the condition `column is not null`.
  JoinClause whereNotNull(String column, [String boolean = SqlBool.and]) {
    return this.on(column, SqlOperator.isOperator, QueryExpression('not null'),
        boolean, false);
  }

  /// Adds the condition `or column is not null`.
  JoinClause orWhereNotNull(String column) {
    return this.whereNotNull(column, SqlBool.or);
  }

  /// Adds the condition `column in (?, ...)`, binding [values].
  JoinClause whereIn(String column, List values) {
    return this.on(column, SqlOperator.inList, values, SqlBool.and, true);
  }

  /// Adds the condition `column not in (?, ...)`, binding [values].
  JoinClause whereNotIn(String column, List values) {
    return this.on(column, SqlOperator.notInList, values, SqlBool.and, true);
  }

  /// Adds the condition `or column in (?, ...)`, binding [values].
  JoinClause orWhereIn(String column, List values) {
    return this.on(column, SqlOperator.inList, values, SqlBool.or, true);
  }

  /// Adds the condition `or column not in (?, ...)`, binding [values].
  JoinClause orWhereNotIn(String column, List values) {
    return this.on(column, SqlOperator.notInList, values, SqlBool.or, true);
  }

  /// Adds a nested group of conditions, `and (...)`: [callback] receives a
  /// new [JoinClause] whose conditions form the group. An empty group adds
  /// nothing.
  JoinClause nest(Function callback, [String boolean = SqlBool.and]) {
    final join = JoinClause(this.type, this.table);

    callback(join);

    if (Utils.count(join.clauses) != 0) {
      var nested = true;

      this.clauses.add({
        'nested': nested,
        'join': join,
        'boolean': boolean,
      });
      this.bindingsLocal =
          Utils.array_merge(this.bindingsLocal, join.bindingsLocal);
    }

    return this;
  }

  /// Adds a raw SQL condition, written as given, with its [bindings].
  JoinClause onRaw(
    String sql, [
    String boolean = SqlBool.and,
    List bindings = const [],
  ]) {
    this.clauses.add({
      'type': 'raw',
      'sql': sql,
      'boolean': boolean,
    });

    this.bindingsLocal = Utils.array_merge(this.bindingsLocal, bindings);
    return this;
  }

  JoinClause clone() {
    final newJoin = JoinClause(this.type, this.table, null, this.isLateral);
    newJoin.bindingsLocal = [...this.bindingsLocal];
    newJoin.clauses = this.clauses.map((clauseMap) {
      final newMap = Map<String, dynamic>.from(clauseMap);
      if (newMap.containsKey('join') && newMap['join'] is JoinClause) {
        newMap['join'] = (newMap['join'] as JoinClause).clone();
      }
      return newMap;
    }).toList();
    return newJoin;
  }
}
