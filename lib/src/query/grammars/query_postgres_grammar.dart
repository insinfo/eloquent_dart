import 'dart:typed_data';
import 'package:eloquent/eloquent.dart';

class QueryPostgresGrammar extends QueryGrammar {
  /// Keeps fractional seconds when there are any: `timestamp` stores
  /// microseconds, and `yyyy-MM-dd HH:mm:ss` alone dropped them
  /// (10:20:30.123 was stored as 10:20:30). MySQL keeps whole seconds: its
  /// `DATETIME` (fsp 0) would round a fraction instead of truncating it.
  @override
  String formatDateTime(DateTime value) {
    final text = super.formatDateTime(value);
    final micros = value.millisecond * 1000 + value.microsecond;
    if (micros == 0) return text;
    return '$text.${micros.toString().padLeft(6, '0')}';
  }

  /// PostgreSQL predicate operators for `QueryBuilder2.whereSqlOperator`.
  /// `?`, `?|` and `?&` (JSON keys) are not here: `?` is the placeholder.
  @override
  Set<String> get predicateOperators => const {
        // comparison
        '=', '<>', '!=', '<', '>', '<=', '>=',
        'is distinct from', 'is not distinct from',
        // text
        'like', 'not like', 'ilike', 'not ilike',
        '~~', '!~~', '~~*', '!~~*',
        'similar to', 'not similar to',
        // regular expressions
        '~', '~*', '!~', '!~*',
        // arrays, ranges, JSON containment
        '@>', '<@', '&&',
        // full-text search
        '@@',
        // inet containment, range position
        '<<', '>>', '<<=', '>>=', '-|-', '&<', '&>',
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
    'not ilike',
    '~',
    '&',
    '|',
    '#',
    '<<',
    '>>',
    '<<=',
    '>>=',
    '&&',
    '@>',
    '<@',
    '?',
    '?|',
    '?&',
    '||',
    '-',
    '-',
    '#-',
    'is distinct from',
    'is not distinct from',
  ];

  /// Compiles `column::date <operator> ?`.
  String whereDate(QueryBuilder query, dynamic where) {
    var value = this.parameter(where['value']);
    return this.wrap(where['column']) +
        '::date ' +
        where['operator'] +
        ' ' +
        value;
  }

  /// Compiles `column::time <operator> ?` (`extract(time from ...)` is not
  /// valid PostgreSQL).
  @override
  String whereTime(QueryBuilder query, dynamic where) {
    return '${this.wrap(where['column'])}::time ${where['operator']} '
        '${this.parameter(where['value'])}';
  }

  /// Compiles `extract(type from column) <operator> ?`, with [type] a field
  /// such as `day`, `month` or `year`.
  String dateBasedWhere(type, QueryBuilder query, dynamic where) {
    var value = this.parameter(where['value']);
    return 'extract(' +
        type +
        ' from ' +
        this.wrap(where['column']) +
        ') ' +
        where['operator'] +
        ' ' +
        value;
  }

  /// Compiles `(column)::jsonb @> value`, with [value] already SQL (a
  /// placeholder). The `->>` of a JSON selector becomes `->`, so the path
  /// yields JSON instead of text.
  String compileJsonContains(dynamic column, dynamic value) {
    final newCol = this.wrap(column).replaceAll('->>', '->');
    return '(' + newCol + ')::jsonb @> ' + value;
  }

  /// `[not] ("column")::jsonb @> ?`, used by `whereJsonContains`.
  @override
  String whereJsonContains(QueryBuilder query, Map<String, dynamic> where) {
    final not = where['not'] == true ? 'not ' : '';
    return not +
        compileJsonContains(where['column'], parameter(where['value']));
  }

  /// `jsonb_array_length(("column")::jsonb) <operator> ?`.
  @override
  String whereJsonLength(QueryBuilder query, Map<String, dynamic> where) {
    final col = this.wrap(where['column']).replaceAll('->>', '->');
    final operator = where['operator'];
    return 'jsonb_array_length(($col)::jsonb) $operator ${parameter(where['value'])}';
  }

  /// `(to_tsvector(lang, col) || ...) @@ <tsquery>(lang, ?)`.
  @override
  String whereFullText(QueryBuilder query, Map<String, dynamic> where) {
    final options = (where['options'] as Map?) ?? const {};
    final language = (options['language'] ?? 'english').toString();
    // The language is inlined in the SQL: only a text-search configuration
    // name (optionally schema-qualified) is accepted.
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?$')
        .hasMatch(language)) {
      throw ArgumentError.value(
          language, 'language', 'Invalid text search configuration name.');
    }
    final mode = (options['mode'] ?? 'plain').toString();

    final columns = (where['columns'] as List)
        .map((c) => "to_tsvector('$language', ${this.wrap(c)})")
        .join(' || ');

    final tsquery = mode == 'phrase'
        ? 'phraseto_tsquery'
        : mode == 'websearch'
            ? 'websearch_to_tsquery'
            : 'plainto_tsquery';

    return "($columns) @@ $tsquery('$language', ${parameter(where['value'])})";
  }

  /// `"column" <op> ?` for PostgreSQL array operators `@>`, `<@`, `&&`.
  @override
  String whereArrayOp(QueryBuilder query, Map<String, dynamic> where) {
    return '${this.wrap(where['column'])} ${where['operator']} '
        '${parameter(where['value'])}';
  }

  /// Compiles the row lock.
  ///
  /// A [QueryLock] gives `for update` or `for share`, with `of tables`,
  /// `skip locked` and `nowait`; `true` gives `for update`, `false`
  /// `for share`, and a string is used as given.
  String compileLock(QueryBuilder query, dynamic value) {
    if (value is QueryLock) {
      final sql = StringBuffer(value.forUpdate ? 'for update' : 'for share');
      if (value.of.isNotEmpty) {
        sql.write(' of ${value.of.map(wrapTable).join(', ')}');
      }
      if (value.skipLocked) sql.write(' skip locked');
      if (value.noWait) sql.write(' nowait');
      return sql.toString();
    }
    if (value is! String) {
      return value ? 'for update' : 'for share';
    }
    return value;
  }

  /// `lock table "schema"."table" in <mode> mode [nowait]`.
  @override
  String compileLockTable(QueryBuilder query, TableLockMode mode,
      {bool noWait = false}) {
    final table = query.fromProp;
    if (table is! String ||
        table.trim().isEmpty ||
        table.toLowerCase().contains(' as ')) {
      throw ArgumentError.value(table, 'table',
          'lockTable() needs a table name without an alias or subquery.');
    }
    return 'lock table ${wrapTable(table)} in ${mode.sql} mode'
        '${noWait ? ' nowait' : ''}';
  }

  /// Compiles a single-row insert; with no [values],
  /// `insert into table DEFAULT VALUES`.
  String compileInsert(QueryBuilder query, Map<String, dynamic> values) {
    final table = this.wrapTable(query.fromProp);
    return values.isEmpty
        ? "insert into $table DEFAULT VALUES"
        : super.compileInsert(query, values);
  }

  /// Compiles an insert that returns the generated id:
  /// `insert ... returning "id"`, with [sequence] the id column (`id` when
  /// null).
  @override
  String compileInsertGetId(
      QueryBuilder query, Map<String, dynamic> values, String? sequence) {
    if (sequence == null) {
      sequence = 'id';
    }

    return this.compileInsert(query, values) +
        ' returning ' +
        this.wrap(sequence);
  }

  /// Compiles `[with ...] update table set ... [from joins] [where]`.
  ///
  /// Joins become `from` plus their conditions in the where, and only inner
  /// and cross joins are accepted. A limit restricts the rows by `ctid`
  /// instead (and cannot be combined with joins).
  String compileUpdate(QueryBuilder query, dynamic values) {
    var table = this.wrapTable(query.fromProp);
    final ctes = this.compileExpressions(query);

    var columns = this.compileUpdateColumns(values);

    // PostgreSQL has no UPDATE ... LIMIT: restrict the target rows by ctid.
    if (query.limitProp != null) {
      _assertNoJoinsWithLimit(query, 'update');
      return '$ctes update $table set $columns where ctid in '
              '(${_compileCtidSubquery(query, table)})'
          .trim();
    }

    _assertJoinsBecomeFrom(query, 'update');
    var from = this.compileUpdateFrom(query) ?? '';
    var where = this.compileUpdateWheres(query);
    return '$ctes update $table set $columns$from $where'.trim();
  }

  /// PostgreSQL has no per-query recursion limit for recursive CTEs.
  @override
  String compileRecursionLimit(QueryBuilder query) {
    if (query.recursionLimitProp == null) return '';
    throw UnsupportedError(
        'recursionLimit() is not supported on PostgreSQL; add a depth column '
        'to the recursive CTE and filter it (where depth < n).');
  }

  /// `"column"::text ilike ?` (`like` when case-sensitive), as in Laravel;
  /// with `unaccent`, `unaccent("column"::text) ilike unaccent(?)`; with
  /// `lower`, `lower(...) like lower(...)`.
  @override
  String whereLike(QueryBuilder query, Map<String, dynamic> where) {
    final not = where['not'] == true ? 'not ' : '';
    final lower = where['lower'] == true;
    final operator = lower || where['caseSensitive'] == true ? 'like' : 'ilike';
    var column = '${this.wrap(where['column'])}::text';
    var value = this.parameter(where['value']);
    if (where['unaccent'] == true) {
      column = '$unaccentFunction($column)';
      value = '$unaccentFunction($value)';
    }
    if (lower) {
      column = 'lower($column)';
      value = 'lower($value)';
    }
    return '$column $not$operator $value';
  }

  /// The function of `unaccent: true` in whereLike/whereSearch: `unaccent`
  /// (extension `unaccent`), or e.g. an IMMUTABLE wrapper such as
  /// `public.f_unaccent` that an expression index can use.
  String get unaccentFunction => _unaccentFunction;
  set unaccentFunction(String name) {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?$')
        .hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'Not a function name.');
    }
    _unaccentFunction = name;
  }

  String _unaccentFunction = 'unaccent';

  @override
  bool get supportsArrayBindings => true;

  @override
  bool get supportsReturning => true;

  /// `"column" = any(?)` / `"column" <> all(?)`, `?::type[]` with an
  /// element type; an empty list is `0 = 1` / `1 = 1`.
  @override
  String whereAnyArray(QueryBuilder query, Map<String, dynamic> where) {
    final not = where['not'] == true;
    if ((where['value'] as List).isEmpty) return not ? '1 = 1' : '0 = 1';
    final type = where['elementType'] as String?;
    final parameter = type == null ? '?' : '?::$type[]';
    return not
        ? '${this.wrap(where['column'])} <> all($parameter)'
        : '${this.wrap(where['column'])} = any($parameter)';
  }

  @override
  String escapeRawBool(bool value) => value ? 'true' : 'false';

  @override
  String escapeRawBinary(Uint8List value) =>
      "'\\x${value.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}'::bytea";

  @override
  String escapeRawValue(dynamic value) {
    // Lists are sent as PostgreSQL arrays by the drivers.
    if (value is List && value is! Uint8List) {
      final items = value.map((item) {
        if (item == null) return 'NULL';
        final text =
            item.toString().replaceAll('\\', '\\\\').replaceAll('"', '\\"');
        return '"$text"';
      }).join(',');
      return this.quoteRawString('{$items}');
    }
    return super.escapeRawValue(value);
  }

  /// Compiles a delete statement. Joins become `USING` (PostgreSQL has no
  /// `DELETE ... JOIN`) and a limit restricts the rows by `ctid`.
  String compileDelete(QueryBuilder query) {
    final table = this.wrapTable(query.fromProp);
    final ctes = this.compileExpressions(query);

    if (query.limitProp != null) {
      _assertNoJoinsWithLimit(query, 'delete');
      return '$ctes delete from $table where ctid in '
              '(${_compileCtidSubquery(query, table)})'
          .trim();
    }

    if (query.joinsProp.isNotEmpty) {
      _assertJoinsBecomeFrom(query, 'delete');
      final using =
          query.joinsProp.map((join) => wrapTable(join.table)).join(', ');
      final where = this.compileUpdateWheres(query);
      return '$ctes delete from $table using $using $where'.trim();
    }

    final where = this.compileWheres(query);
    return '$ctes delete from $table $where'.trim();
  }

  /// `select ctid from <table> [where] [order by] limit n`.
  String _compileCtidSubquery(QueryBuilder query, String table) {
    final parts = <String>['select ctid from $table'];
    final where = this.compileWheres(query);
    if (where.isNotEmpty) parts.add(where);
    if (query.ordersProp.isNotEmpty) {
      parts.add(this.compileOrders(query, query.ordersProp));
    }
    parts.add(this.compileLimit(query, query.limitProp!));
    return parts.join(' ');
  }

  void _assertNoJoinsWithLimit(QueryBuilder query, String statement) {
    if (query.joinsProp.isNotEmpty) {
      throw UnsupportedError(
          'PostgreSQL $statement with both joins and limit is not supported.');
    }
  }

  /// Joins of an UPDATE/DELETE become `FROM`/`USING` plus their conditions in
  /// the WHERE, which only matches inner (and cross) join semantics.
  void _assertJoinsBecomeFrom(QueryBuilder query, String statement) {
    for (final join in query.joinsProp) {
      final type = join.type.toLowerCase();
      if (type != SqlJoin.inner && type != 'cross') {
        throw UnsupportedError(
            'PostgreSQL $statement supports only inner joins; got a '
            '"${join.type}" join on ${join.table}.');
      }
    }
  }

  /// Bindings of an UPDATE in SQL order:
  /// `[with] update t set ... [from joins] where <wheres> <join conditions>`,
  /// or with a limit `... where ctid in (select ... where ... order by ...)`.
  @override
  List<dynamic> prepareBindingsForUpdate(
      QueryBuilder query, Map<String, dynamic> values) {
    return [
      ...query.bindings['expressions'],
      ...values.values,
      ...query.bindings['where'],
      if (query.limitProp != null) ...query.bindings['order'],
      ...query.bindings['join'],
    ];
  }

  /// Bindings of a DELETE in SQL order:
  /// `[with] delete from t [using joins] where <wheres> <join conditions>`.
  @override
  List<dynamic> prepareBindingsForDelete(QueryBuilder query) {
    return [
      ...query.bindings['expressions'],
      ...query.bindings['where'],
      if (query.limitProp != null) ...query.bindings['order'],
      ...query.bindings['join'],
    ];
  }

  /// Compiles the `set` list of an update: `"column" = ?, ...`.
  String compileUpdateColumns(Map<String, dynamic> values) {
    final columns = <String>[];

    for (var items in values.entries) {
      final key = items.key;
      final value = items.value;
      columns.add(this.wrap(key) + ' = ' + this.parameter(value));
    }
    return columns.join(', ');
  }

  /// Compiles ` from table, ...` with the joined tables of an update, or an
  /// empty string without joins.
  String? compileUpdateFrom(QueryBuilder query) {
    if (!Utils.isset(query.joinsProp)) {
      return '';
    }

    var froms = <String>[];

    // PostgreSQL lists the joined tables of an update in its `from`, unlike
    // MySQL's `update t join ...`.
    for (var join in query.joinsProp) {
      froms.add(wrapTable(join.table));
    }

    if (froms.length > 0) {
      return ' from ' + froms.join(', ');
    }

    return null;
  }

  /// Compiles the where of an update or delete with joins: the query's where
  /// clauses followed by the join conditions.
  String compileUpdateWheres(QueryBuilder query) {
    var baseWhere = this.compileWheres(query);

    if (!Utils.isset(query.joinsProp)) {
      return baseWhere;
    }

    // Without where clauses the join conditions are the whole where, so the
    // first one loses its boolean.
    var joinWhere = this.compileUpdateJoinWheres(query);

    if (Utils.trim(baseWhere) == '') {
      return 'where ' + this.removeLeadingBoolean(joinWhere);
    }

    return baseWhere + ' ' + joinWhere;
  }

  /// Compiles the conditions of every join, each with its boolean, for the
  /// where of an update or delete.
  String compileUpdateJoinWheres(QueryBuilder query) {
    var joinWheres = <String>[];

    for (var join in query.joinsProp) {
      for (var clause in join.clauses) {
        joinWheres.add(this.compileJoinConstraint(clause));
      }
    }

    return Utils.implode(' ', joinWheres);
  }

  /// Compiles `truncate table restart identity`, as a map from each statement
  /// to its bindings.
  Map<String, dynamic> compileTruncate(QueryBuilder query) {
    return {
      'truncate ' + this.wrapTable(query.fromProp) + ' restart identity': []
    };
  }

  String wrapValue(String value) {
    if (value == '*') {
      return value;
    }
    if (value.contains('->')) {
      return wrapJsonSelector(value);
    }
    return '"' + value.replaceAll('"', '""') + '"';
  }

  /// Compile the select columns, honoring `distinct on (...)`.
  @override
  String? compileColumns(QueryBuilder query, dynamic columns) {
    if (query.aggregateProp != null) {
      return null;
    }

    String select;
    final distinctOn = query.distinctOnProp;
    if (distinctOn != null && distinctOn.isNotEmpty) {
      select = 'select distinct on (${distinctOn.map(this.wrap).join(', ')}) ';
    } else if (query.distinctProp) {
      select = 'select distinct ';
    } else {
      select = 'select ';
    }

    return select + this.columnize(columns);
  }

  /// Compiles a JSON selector `column->a->b` as `"column"->'a'->>'b'`: the
  /// last key is read as text (`->>`).
  String wrapJsonSelector(String value) {
    List<String> path = value.split('->');

    String field = wrapValue(path.removeAt(0));

    List<String> wrappedPath = wrapJsonPathAttributes(path);

    String attribute = wrappedPath.removeLast();

    if (wrappedPath.isNotEmpty) {
      return '$field->${wrappedPath.join("->")}->>$attribute';
    }

    return '$field->>$attribute';
  }

  /// Quotes each key of a JSON path as a string literal: `'key'`.
  List<String> wrapJsonPathAttributes(List<String> path) {
    return path.map((attribute) => "'$attribute'").toList();
  }

  /// Compiles the joins: `<type> join [LATERAL] table on ...`, or
  /// `cross join table` for a cross join without conditions. A lateral join
  /// without conditions gets `on TRUE`.
  String compileJoins(QueryBuilder query, List<JoinClause> joins) {
    final sql = <String>[];

    for (var join in joins) {
      final table = this.wrapTable(join.table);
      final type = join.type.toLowerCase();

      final lateral = join.isLateral ? ' LATERAL' : '';

      // A cross join without conditions has no `on`.
      if (type == 'cross' && (join.clauses.isEmpty)) {
        sql.add("cross join $table");
        continue;
      }

      final clauses = <String>[];

      // for (var clause in join.clauses) {
      //   clauses.add(this.compileJoinConstraint(clause));
      // }
      for (var clause in join.clauses) {
        // Raw conditions (JoinClause.onRaw) are written as given.
        if (clause['type'] == 'raw') {
          clauses.add('${clause['boolean']} ${clause['sql']}');
        } else {
          clauses.add(this.compileJoinConstraint(clause));
        }
      }

      var clausesString = '';
      if (clauses.isNotEmpty) {
        // The first condition takes no leading `and`/`or`.
        clauses[0] = this.removeLeadingBoolean(clauses[0]);
        clausesString = clauses.join(' ');
      } else if (join.isLateral) {
        // A lateral join needs a join condition; `on TRUE` keeps every row.
        clausesString = 'TRUE'; // Compila para ON TRUE
      }

      // `type join [LATERAL] table [on conditions]`.
      final onClause = clausesString.isNotEmpty ? ' on $clausesString' : '';
      sql.add("$type join$lateral $table$onClause");
    }

    return sql.join(' '); // Junta todos os joins com espaço
  }
}
