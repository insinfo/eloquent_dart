import 'package:eloquent/eloquent.dart';

import '../json_expression.dart';

class QueryMySqlGrammar extends QueryGrammar {
  /// MySQL/MariaDB predicate operators for `QueryBuilder2.whereSqlOperator`.
  @override
  Set<String> get predicateOperators => const {
        '=', '<>', '!=', '<', '>', '<=', '>=', '<=>',
        'like', 'not like', 'like binary', 'not like binary',
        'rlike', 'not rlike', 'regexp', 'not regexp', 'sounds like',
      };

  /// All of the available clause operators.
  List<String> operators = [
    '=',
    '<',
    '>',
    '<=',
    '>=',
    '<>',
    '!=',
    'like',
    'not like',
    'between',
    'ilike',
    '&',
    '|',
    '#',
    '<<',
    '>>',
    '@>',
    '<@',
    '?',
    '?|',
    '?&',
    '||',
    '-',
    '-',
    '#-'
  ];

  List<String> selectComponents = [
    // CTEs (MySQL 8 / MariaDB 10.2+); they were dropped while their bindings
    // were still sent.
    'expressions',
    'aggregate',
    'columns',
    'from',
    'joins',
    'wheres',
    'groups',
    'havings',
    'orders',
    'limit',
    'offset',
    'lock',
  ];

  ///
  /// Compile a select query into SQL.
  ///
  /// @param  QueryBuilder  query
  /// @return string
  ///
  String compileSelect(QueryBuilder query) {
    if (query.unionsProp.isEmpty || query.expressionsProp.isEmpty) {
      var sql = super.compileSelect(query);
      if (query.unionsProp.isNotEmpty) {
        sql = '(' + sql + ') ' + this.compileUnions(query);
      }
      return sql;
    }

    // The WITH clause must precede the parenthesized union operands.
    final ctes = this.compileExpressions(query);
    final expressions = query.expressionsProp;
    query.expressionsProp = [];
    final String sql;
    try {
      sql = super.compileSelect(query);
    } finally {
      query.expressionsProp = expressions;
    }
    return '$ctes ($sql) ${this.compileUnions(query)}';
  }

  ///
  /// Compile a "JSON contains" statement into SQL.
  ///
  /// @param  string  $column
  /// @param  string  $value
  /// @return string
  ///
  String compileJsonContains(column, value) {
    return 'json_contains(' + this.wrap(column) + ', ' + value + ')';
  }

  ///
  /// Compile a single union statement.
  ///
  /// @param  array  $union
  /// @return string
  ///
  String compileUnion(Map union) {
    var conjunction = union['all'] ? ' union all ' : ' union ';
    return conjunction + '(' + union['query'].toSql() + ')';
  }

  ///
  /// Compile the random statement into SQL.
  ///
  /// @param  string  $seed
  /// @return string
  ///
  String compileRandom(seed) {
    return 'RAND(' + seed + ')';
  }

  ///
  /// Compile the lock into SQL.
  ///
  /// @param QueryBuilder  $query
  /// @param  bool|string  $value
  /// @return string
  ///
  String compileLock(QueryBuilder query, value) {
    if (value is QueryLock) {
      // Modifiers need the MySQL 8.0 syntax (`FOR SHARE`, not
      // `LOCK IN SHARE MODE`).
      final sql = StringBuffer(value.forUpdate ? 'for update' : 'for share');
      if (value.of.isNotEmpty) {
        sql.write(' of ${value.of.map(wrapTable).join(', ')}');
      }
      if (value.skipLocked) sql.write(' skip locked');
      if (value.noWait) sql.write(' nowait');
      return sql.toString();
    }
    if (value is! String) {
      return value ? 'for update' : 'lock in share mode';
    }
    return value;
  }

  ///
  /// Compile an insert and get ID statement into SQL.
  ///
  ///  [query]  QueryBuilder
  ///  [values] Map<String,dynamic>
  /// @param  String  $sequence
  ///  `Return` String
  ///
  @override
  String compileInsertGetId(
      QueryBuilder query, Map<String, dynamic> values, String? sequence) {
    if (sequence == null) {
      sequence = 'id';
    }

    // return this.compileInsert(query, values) +
    //     ' returning ' +
    //     this.wrap(sequence);

    return this.compileInsert(query, values);
  }

  /// MySQL uses `INSERT IGNORE` rather than `ON CONFLICT DO NOTHING`.
  @override
  String compileInsertOrIgnore(
    QueryBuilder query,
    List<Map<String, dynamic>> rows,
  ) {
    final base = this.compileInsertRows(query, rows);
    // Turn "insert into" into "insert ignore into".
    return base.replaceFirst('insert into', 'insert ignore into');
  }

  /// MySQL UPSERT via `ON DUPLICATE KEY UPDATE`. The conflict target columns
  /// are implicit (any unique/primary key), so [uniqueBy] is ignored except to
  /// decide which columns default to being updated.
  @override
  String compileUpsert(
    QueryBuilder query,
    List<Map<String, dynamic>> rows,
    List<String> uniqueBy,
    Map<String, dynamic>? update,
  ) {
    final insertSql = this.compileInsertRows(query, rows);

    final setParts = <String>[];
    if (update == null) {
      final columns = rows.first.keys.where((c) => !uniqueBy.contains(c));
      for (final column in columns) {
        final w = this.wrap(column);
        setParts.add('$w = values($w)');
      }
    } else {
      for (final entry in update.entries) {
        setParts
            .add('${this.wrap(entry.key)} = ${this.parameter(entry.value)}');
      }
    }
    if (setParts.isEmpty) {
      // No columns to update -> emulate ignore.
      return insertSql.replaceFirst('insert into', 'insert ignore into');
    }
    return '$insertSql on duplicate key update ${setParts.join(', ')}';
  }

  @override
  String upsertInsertedValue(String column) => 'values(${this.wrap(column)})';

  /// `ON CONFLICT` in MySQL terms (it emitted PostgreSQL's `on conflict`):
  /// `do update` becomes `on duplicate key update`, `do nothing` a no-op
  /// update of the first key column (only duplicate keys are skipped, unlike
  /// `insert ignore`). MySQL matches any unique key, so the conflict
  /// columns only pick that column; a named constraint and a `where` on the
  /// update have no MySQL equivalent and throw.
  @override
  String compileInsertWithClauses(
    QueryBuilder query,
    Map<String, dynamic> values,
    OnConflictClause? conflict,
    List<dynamic>? returning,
  ) {
    final buffer = StringBuffer(this.compileInsert(query, values));
    if (conflict != null) {
      if (conflict.constraint != null) {
        throw UnsupportedError(
            'MySQL cannot target a named constraint in ON DUPLICATE KEY.');
      }
      if (conflict.updateWhereRaw != null) {
        throw UnsupportedError(
            'MySQL ON DUPLICATE KEY UPDATE has no WHERE clause.');
      }
      final update = conflict.doNothing ? null : conflict.updateValues;
      if (update == null || update.isEmpty) {
        final key = this.wrap(conflict.columns.isNotEmpty
            ? conflict.columns.first
            : values.keys.first);
        buffer.write(' on duplicate key update $key = $key');
      } else {
        final parts = [
          for (final entry in update.entries)
            '${this.wrap(entry.key)} = ${this.parameter(entry.value)}'
        ];
        buffer.write(' on duplicate key update ${parts.join(', ')}');
      }
    }
    if (returning != null) {
      buffer.write(this.compileReturning(returning));
    }
    return buffer.toString();
  }

  /// MySQL does not support `RETURNING` on INSERT (MariaDB does, but this
  /// grammar targets MySQL). Reject it clearly instead of emitting bad SQL.
  @override
  String compileReturning(List<dynamic> returning) {
    if (returning.isEmpty) return '';
    throw UnsupportedError(
      'RETURNING is not supported by MySQL; use insertGetId() instead.',
    );
  }

  ///
  /// Compile an update statement into SQL.
  ///
  /// @param  QueryBuilder  $query
  /// @param  array  $values
  /// @return string
  ///
  String compileUpdate(QueryBuilder query, Map<String, dynamic> values) {
    final table = this.wrapTable(query.fromProp);

    final columns = <String>[];

    // Each one of the columns in the update statements needs to be wrapped in the
    // keyword identifiers, also a place-holder needs to be created for each of
    // the values in the list of bindings so we can make the sets statements.
    for (var entry in values.entries) {
      var key = entry.key;
      var value = entry.value;

      if (this.isJsonSelector(key)) {
        columns.add(this.compileJsonUpdateColumn(key, JsonExpression(value)));
      } else {
        columns.add(this.wrap(key) + ' = ' + this.parameter(value));
      }
    }

    final columnsStr = columns.join(', ');

    // If the query has any "join" clauses, we will setup the joins on the builder
    // and compile them so we can attach them to this update, as update queries
    // can get join statements to attach to other tables when they're needed.
    var joins = '';
    if (query.joinsProp.isNotEmpty) {
      joins = ' ' + this.compileJoins(query, query.joinsProp);
    }

    // Of course, update queries may also be constrained by where clauses so we'll
    // need to compile the where clauses and attach it to the query so only the
    // intended records are updated by the SQL statements we generate to run.
    final where = this.compileWheres(query);

    var sql = ("${this.compileExpressions(query)} update $table$joins "
            "set $columnsStr $where")
        .trim();

    if (query.ordersProp.isNotEmpty) {
      sql += ' ' + this.compileOrders(query, query.ordersProp);
    }

    if (query.limitProp != null) {
      sql += ' ' + this.compileLimit(query, query.limitProp!);
    }

    return (sql).trimRight();
  }

  ///
  /// Prepares a JSON column being updated using the JSON_SET function.
  ///
  /// @param  string  $key
  /// @param  \Illuminate\Database\JsonExpression  $value
  /// @return string
  ///
  String compileJsonUpdateColumn(key, JsonExpression value) {
    //var path = explode('->', key);
    List<String> path = key.split('->');

    //var field = this.wrapValue(array_shift(path));
    var field = this.wrapValue(path.removeAt(0));

    var accessor = '"\$.' + path.join('.') + '"';

    //return "{$field} = json_set({$field}, {$accessor}, {$value->getValue()})";
    return '$field = json_set($field, $accessor, ${value.getValue()})';
  }

  ///
  /// Prepare the bindings for an update statement.
  ///
  /// [bindings] List<dynamic> bindings
  /// [values] Map<String, dynamic>
  /// @return array
  ///
  /// SQL order: `[with] update t [joins] set ... [where] [order by] [limit]`.
  /// A boolean assigned to a JSON selector is emitted inline by
  /// [compileJsonUpdateColumn], so it has no binding.
  @override
  List<dynamic> prepareBindingsForUpdate(
      QueryBuilder query, Map<String, dynamic> values) {
    return [
      ...query.bindings['expressions'],
      ...query.bindings['join'],
      for (final entry in values.entries)
        if (!(isJsonSelector(entry.key) && entry.value is bool)) entry.value,
      ...query.bindings['where'],
      ...query.bindings['order'],
    ];
  }

  /// SQL order: `[with] delete ... [joins] [where] [order by] [limit]`.
  @override
  List<dynamic> prepareBindingsForDelete(QueryBuilder query) {
    return [
      ...query.bindings['expressions'],
      ...query.bindings['join'],
      ...query.bindings['where'],
      if (query.joinsProp.isEmpty) ...query.bindings['order'],
    ];
  }

  /**
     * Compile an insert statement using a subquery into SQL.
     *
     * @param \Illuminate\Database\Query\Builder $query
     * @param array $columns
     * @param string $sql
     * @return string
     */
  String compileInsertUsing(QueryBuilder query, columns, String sql) {
    final insert =
        "insert into ${this.wrapTable(query.fromProp)} (${this.columnize(columns)}) ";
    return insert + this.compileExpressions(query) + ' ' + sql;
  }

  ///
  /// Compile a delete statement into SQL.
  ///
  /// @param  QueryBuilder $query
  /// @return string
  ///
  /// `column like ?`, or `like binary ?` when case-sensitive (Laravel).
  @override
  String whereLike(QueryBuilder query, Map<String, dynamic> where) {
    final not = where['not'] == true ? 'not ' : '';
    final operator = where['caseSensitive'] == true ? 'like binary' : 'like';
    return '${this.wrap(where['column'])} $not$operator '
        '${this.parameter(where['value'])}';
  }

  /// `match (columns) against (? in natural language mode)`; the option
  /// `mode: 'boolean'` uses boolean mode and `expanded: true` adds
  /// `with query expansion` (natural language mode only).
  @override
  String whereFullText(QueryBuilder query, Map<String, dynamic> where) {
    final options = (where['options'] as Map?) ?? const {};
    final columns = this.columnize(where['columns'] as List);
    final boolean = options['mode'] == 'boolean';
    final mode = boolean ? ' in boolean mode' : ' in natural language mode';
    final expanded =
        options['expanded'] == true && !boolean ? ' with query expansion' : '';
    return 'match ($columns) against '
        '(${this.parameter(where['value'])}$mode$expanded)';
  }

  /// MySQL string literals also treat the backslash as an escape.
  @override
  String quoteRawString(String value) =>
      "'${value.replaceAll('\\', '\\\\').replaceAll("'", "''")}'";

  /// MySQL/MariaDB limit recursion with a session variable, not in the query.
  @override
  String compileRecursionLimit(QueryBuilder query) {
    if (query.recursionLimitProp == null) return '';
    throw UnsupportedError(
        'recursionLimit() is not supported on MySQL/MariaDB; set the session '
        'variable cte_max_recursion_depth (MySQL) or max_recursive_iterations '
        '(MariaDB), or filter a depth column.');
  }

  String compileDelete(QueryBuilder query) {
    final table = this.wrapTable(query.fromProp);
    final ctes = this.compileExpressions(query);

    final where = query.wheresProp.isNotEmpty ? this.compileWheres(query) : '';

    if (query.joinsProp.isNotEmpty) {
      final joins = ' ' + this.compileJoins(query, query.joinsProp);
      return "$ctes delete $table from $table$joins $where".trim();
    } else {
      var sql = "$ctes delete from $table $where".trim();

      if (query.ordersProp.isNotEmpty) {
        sql += ' ' + this.compileOrders(query, query.ordersProp);
      }

      if (query.limitProp != null) {
        sql += ' ' + this.compileLimit(query, query.limitProp!);
      }
      return sql;
    }
  }

  ///
  /// Wrap a single string in keyword identifiers.
  ///
  /// @param  string  $value
  /// @return string
  ///
  String wrapValue(value) {
    if (value == '*') {
      return value;
    }

    if (this.isJsonSelector(value)) {
      return this.wrapJsonSelector(value);
    }

    // return '`'.str_replace('`', '``', $value).'`';
    return '`' + value.replaceAll('`', '``') + '`';
  }

  ///
  /// Wrap the given JSON selector.
  ///
  /// @param  string  $value
  /// @return string
  ///
  String wrapJsonSelector(String value) {
    final path = value.split('->');
    final field = this.wrapValue(path.removeAt(0));
    return field + '->' + '"\$.' + path.join('.') + '"';
  }

  ///
  /// Determine if the given string is a JSON selector.
  ///
  /// @param  string  $value
  /// @return bool
  ///
  bool isJsonSelector(String value) {
    return value.contains('->');
    //Str::contains($value, '->');
  }
}
