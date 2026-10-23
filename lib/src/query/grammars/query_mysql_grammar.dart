import 'package:eloquent/eloquent.dart';

import '../json_expression.dart';

class QueryMySqlGrammar extends QueryGrammar {
  /// MySQL/MariaDB predicate operators for `QueryBuilder2.whereSqlOperator`.
  @override
  Set<String> get predicateOperators => const {
        '=',
        '<>',
        '!=',
        '<',
        '>',
        '<=',
        '>=',
        '<=>',
        'like',
        'not like',
        'like binary',
        'not like binary',
        'rlike',
        'not rlike',
        'regexp',
        'not regexp',
        'sounds like',
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

  /// Compiles a select query into SQL.
  ///
  /// With unions every operand is parenthesized:
  /// `[with ...] (select ...) union (select ...)`.
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

  /// Compiles `json_contains(column, value)`, with [value] already SQL (a
  /// placeholder).
  String compileJsonContains(column, value) {
    return 'json_contains(' + this.wrap(column) + ', ' + value + ')';
  }

  /// Compiles one union with its query parenthesized:
  /// ` union (select ...)` or ` union all (select ...)`.
  String compileUnion(Map union) {
    var conjunction = union['all'] ? ' union all ' : ' union ';
    return conjunction + '(' + union['query'].toSql() + ')';
  }

  /// Compiles the expression of a random order: `RAND(seed)`, or `RAND()`
  /// with an empty seed.
  String compileRandom(seed) {
    return 'RAND(' + seed + ')';
  }

  /// Compiles the row lock.
  ///
  /// A [QueryLock] gives `for update` or `for share`, with `of tables`,
  /// `skip locked` and `nowait`; `true` gives `for update`, `false`
  /// `lock in share mode`, and a string is used as given.
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

  /// Compiles a plain insert: MySQL has no `returning`, so the processor
  /// reads the generated id from the insert result and [sequence] is unused.
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

  /// Compiles an update: `[with ...] update table [joins] set ... [where]
  /// [order by] [limit]`.
  ///
  /// A JSON selector key (`column->path`) is set with `json_set` (see
  /// [compileJsonUpdateColumn]).
  String compileUpdate(QueryBuilder query, Map<String, dynamic> values) {
    final table = this.wrapTable(query.fromProp);

    final columns = <String>[];

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

    var joins = '';
    if (query.joinsProp.isNotEmpty) {
      joins = ' ' + this.compileJoins(query, query.joinsProp);
    }

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

  /// Compiles the assignment of a JSON selector [key] (`column->a->b`):
  /// `` `column` = json_set(`column`, "$.a.b", value) ``.
  String compileJsonUpdateColumn(key, JsonExpression value) {
    List<String> path = key.split('->');

    var field = this.wrapValue(path.removeAt(0));

    var accessor = '"\$.' + path.join('.') + '"';

    return '$field = json_set($field, $accessor, ${value.getValue()})';
  }

  /// Bindings of an UPDATE, in SQL order:
  /// `[with] update t [joins] set ... [where] [order by] [limit]`.
  ///
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

  /// Bindings of a DELETE, in SQL order:
  /// `[with] delete ... [joins] [where] [order by] [limit]`.
  ///
  /// A delete with joins has no `order by`, so its order bindings are left
  /// out.
  @override
  List<dynamic> prepareBindingsForDelete(QueryBuilder query) {
    return [
      ...query.bindings['expressions'],
      ...query.bindings['join'],
      ...query.bindings['where'],
      if (query.joinsProp.isEmpty) ...query.bindings['order'],
    ];
  }

  /// Compiles an insert of the rows selected by [sql], the compiled subquery:
  /// `insert into table (columns) [with ...] select ...`.
  String compileInsertUsing(QueryBuilder query, columns, String sql) {
    final insert =
        "insert into ${this.wrapTable(query.fromProp)} (${this.columnize(columns)}) ";
    return insert + this.compileExpressions(query) + ' ' + sql;
  }

  /// `column like ?`, or `like binary ?` when case-sensitive (Laravel).
  @override
  String whereLike(QueryBuilder query, Map<String, dynamic> where) {
    final not = where['not'] == true ? 'not ' : '';
    if (where['lower'] == true) {
      return 'lower(${this.wrap(where['column'])}) ${not}like '
          'lower(${this.parameter(where['value'])})';
    }
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

  /// Compiles `[with ...] delete from table [where] [order by] [limit]`, or
  /// with joins `[with ...] delete table from table joins [where]`.
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

  /// Quotes one identifier with backticks (`` ` `` doubled inside); `*` is
  /// kept and a JSON selector goes to [wrapJsonSelector].
  String wrapValue(value) {
    if (value == '*') {
      return value;
    }

    if (this.isJsonSelector(value)) {
      return this.wrapJsonSelector(value);
    }

    return '`' + value.replaceAll('`', '``') + '`';
  }

  /// Compiles a JSON selector `column->a->b` as `` `column`->"$.a.b" ``.
  String wrapJsonSelector(String value) {
    final path = value.split('->');
    final field = this.wrapValue(path.removeAt(0));
    return field + '->' + '"\$.' + path.join('.') + '"';
  }

  /// Whether [value] is a JSON selector (contains `->`).
  bool isJsonSelector(String value) {
    return value.contains('->');
  }
}
