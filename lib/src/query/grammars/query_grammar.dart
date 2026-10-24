import 'dart:typed_data';
import 'dart:convert';
import 'package:eloquent/eloquent.dart';

class QueryGrammar extends BaseGrammar {
  /// The grammar specific operators.
  List<String> operators = [];

  /// Operators accepted by `QueryBuilder2.whereSqlOperator`: the ones that
  /// compare a column with one value and yield a boolean. Arithmetic and
  /// other non-predicate operators are not listed.
  Set<String> get predicateOperators => const {
        '=', '<>', '!=', '<', '>', '<=', '>=', 'like', 'not like', //
      };

  List<String> getOperators() {
    return operators;
  }

  late final Map<String, Function> _methodMap;

  QueryGrammar() {
    _methodMap = {
      'compilecolumns': (args) => compileColumns(args[0], args[1]),
      'compilefrom': (args) => compileFrom(args[0], args[1]),
      'compilewheres': (args) => compileWheres(args[0]),
      'compilelimit': (args) => compileLimit(args[0], args[1]),
      'compileoffset': (args) => compileOffset(args[0], args[1]),
      'compilegroups': (args) => compileGroups(args[0], args[1]),
      'compilehaving': (args) => compileHaving(args[0]),
      'compileorders': (args) => compileOrders(args[0], args[1]),
      'compileaggregate': (args) => compileAggregate(args[0], args[1]),
      'compilejoins': (args) => compileJoins(args[0], args[1]),
      'wherenested': (args) => whereNested(args[0], args[1]),
      'wheresub': (args) => whereSub(args[0], args[1]),
      'wherebasic': (args) => whereBasic(args[0], args[1]),
      'wherebetween': (args) => whereBetween(args[0], args[1]),
      'whereexists': (args) => whereExists(args[0], args[1]),
      'wherenotexists': (args) => whereNotExists(args[0], args[1]),
      'wherein': (args) => whereIn(args[0], args[1]),
      'wherenotin': (args) => whereNotIn(args[0], args[1]),
      'whereinsub': (args) => whereInSub(args[0], args[1]),
      'wherenotinsub': (args) => whereNotInSub(args[0], args[1]),
      'wherenull': (args) => whereNull(args[0], args[1]),
      'wherenotnull': (args) => whereNotNull(args[0], args[1]),
      'wheredate': (args) => whereDate(args[0], args[1]),
      'wheretime': (args) => whereTime(args[0], args[1]),
      'whereday': (args) => whereDay(args[0], args[1]),
      'wheremonth': (args) => whereMonth(args[0], args[1]),
      'whereyear': (args) => whereYear(args[0], args[1]),
      'whereraw': (args) => whereRaw(args[0], args[1]),
      'wherecolumn': (args) => whereColumn(args[0], args[1]),
      'compilehavings': (args) => compileHavings(args[0], args[1]),
      'compileunion': (args) => compileUnion(args[0]),
      'compileunions': (args) => compileUnions(args[0]),
      'compilelock': (args) => compileLock(args[0], args[1]),
      'compileexpressions': (args) => compileExpressions(args[0]),
      'compilerecursionlimit': (args) => compileRecursionLimit(args[0]),
      'compileinsertUsing': (args) =>
          compileInsertUsing(args[0], args[1], args[2]),
    };
  }

  dynamic callMethod(String methodName, List<dynamic> positionalArguments,
      [Map<Symbol, dynamic>? namedArguments]) {
    final methodFunction = _methodMap[methodName.toLowerCase()];
    if (methodFunction == null) {
      throw Exception("method '$methodName' not exist in QueryGrammar class");
    }

    return methodFunction(positionalArguments);
  }

  /// The components of a select query, in the order they are compiled.
  List<String> selectComponents = [
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
    'unions',
    'lock',
  ];

  /// Compiles the common table expressions (CTEs) of [query].
  ///
  /// Returns an empty string when there are none, otherwise
  /// `with [recursive] "cte1" ("col1", "col2") as [materialized] (...), ...`.
  String compileExpressions(QueryBuilder query) {
    if (query.expressionsProp.isEmpty) {
      return '';
    }

    final recursive = recursiveKeyword(query.expressionsProp);

    final List<String> statements = [];
    for (final expr in query.expressionsProp) {
      final name = expr['name'] as String;
      final sql = expr['query'] as String;
      final cols = expr['columns'] as List<String>?;
      final isMaterialized = expr['materialized'] == true;

      final columnList =
          (cols != null && cols.isNotEmpty) ? '(${columnize(cols)})' : '';
      final separator = columnList.isNotEmpty
          ? ' '
          : ''; // Adiciona espaço só se houver colunas

      final materializedHint = isMaterialized ? ' MATERIALIZED' : '';

      statements.add(
          '${wrapTable(name)}$separator$columnList as$materializedHint ($sql)'); // Usa 'as' minúsculo
    }

    return 'with $recursive${statements.join(', ')}';
  }

  /// Returns `recursive ` when any of [expressions] is recursive, otherwise
  /// an empty string.
  String recursiveKeyword(List<Map<String, dynamic>> expressions) {
    final needsRecursive = expressions.any((e) => e['recursive'] == true);
    return needsRecursive ? 'recursive ' : '';
  }

  /// Compiles the limit set with `recursionLimit()`:
  /// `option (maxrecursion n)` (SQL Server syntax), or an empty string
  /// without one. MySQL and PostgreSQL override it to throw.
  String compileRecursionLimit(QueryBuilder query) {
    if (query.recursionLimitProp == null) {
      return '';
    }
    return 'option (maxrecursion ${query.recursionLimitProp})';
  }

  /// Compiles an insert of the rows selected by [sql], the compiled subquery:
  /// `[with ...] insert into table (columns) select ...`.
  ///
  /// The common table expressions of [query] come first, as their bindings
  /// do in `QueryBuilder.insertUsing`.
  String compileInsertUsing(QueryBuilder query, dynamic columns, String sql) {
    final table = this.wrapTable(query.fromProp);
    final columnsSql = this.columnize(columns);
    return '${this.compileExpressions(query)} '
            'insert into $table ($columnsSql) $sql'
        .trim();
  }

  /// Compiles a select query into SQL.
  String compileSelect(QueryBuilder query) {
    final queryColumns = query.getColumns();
    final original = queryColumns != null ? [...queryColumns] : null;

    if (Utils.is_null(query.columnsProp)) {
      query.columnsProp = ['*'];
    }
    final compiledComps = compileComponents(query);

    var sql = Utils.trim(concatenate(compiledComps));

    query.setColumns(original);

    // Dialects without a query-level recursion limit throw here instead of
    // silently ignoring recursionLimit().
    if (query.recursionLimitProp != null) {
      sql = Utils.trim('$sql ${compileRecursionLimit(query)}');
    }

    return sql;
  }

  /// Compiles each of the [selectComponents] that [query] has set, by
  /// component name.
  Map<String, dynamic> compileComponents(QueryBuilder query) {
    final sql = <String, dynamic>{};
    for (var component in this.selectComponents) {
      final proP = query.getProperty(component);
      var isProp = proP != null;
      if (proP is List) {
        isProp = proP.isNotEmpty;
      } else if (proP is Map) {
        isProp = proP.isNotEmpty;
      }
      if (isProp) {
        // Direct dispatch (avoids per-call string construction + map lookup in
        // the hot path). Virtual dispatch still reaches dialect overrides.
        sql[component] = _compileComponent(query, component, proP);
      }
    }
    return sql;
  }

  /// Compile a single select component by name via a direct switch.
  ///
  /// SQL output is identical to routing through [callMethod]; the switch just
  /// skips the `'compile' + ucfirst(...)` allocation and the `_methodMap`
  /// lookup performed on every component of every compile.
  dynamic _compileComponent(
      QueryBuilder query, String component, dynamic prop) {
    switch (component) {
      case 'expressions':
        return compileExpressions(query);
      case 'aggregate':
        return compileAggregate(query, prop);
      case 'columns':
        return compileColumns(query, prop);
      case 'from':
        return compileFrom(query, prop);
      case 'joins':
        return compileJoins(query, prop);
      case 'wheres':
        return compileWheres(query);
      case 'groups':
        return compileGroups(query, prop);
      case 'havings':
        return compileHavings(query, prop);
      case 'orders':
        return compileOrders(query, prop);
      case 'limit':
        return compileLimit(query, prop);
      case 'offset':
        return compileOffset(query, prop);
      case 'unions':
        return compileUnions(query);
      case 'lock':
        return compileLock(query, prop);
      default:
        return callMethod('compile' + Utils.ucfirst(component), [query, prop]);
    }
  }

  /// Compiles an aggregate select: `select count(columns) as aggregate`.
  ///
  /// A distinct query puts `distinct` before the columns unless they are `*`.
  String compileAggregate(QueryBuilder query, Map<String, dynamic> aggregate) {
    var column = columnize(aggregate['columns']);

    // `count(distinct col)` aggregates distinct values; `distinct *` is not
    // valid SQL.
    if (query.distinctProp && column != '*') {
      column = 'distinct ' + column;
    }

    return 'select ' + aggregate['function'] + '(' + column + ') as aggregate';
  }

  /// Compiles `select [distinct] columns`.
  ///
  /// Returns null for an aggregate query, which [compileAggregate] selects.
  /// [columns] are names or [QueryExpression]s.
  String? compileColumns(QueryBuilder query, columns) {
    // compileAggregate writes the select list of an aggregate query.
    if (query.aggregateProp != null) {
      return null;
    }

    var select = query.distinctProp ? 'select distinct ' : 'select ';

    final result = select + this.columnize(columns);

    return result;
  }

  /// Compiles `from table`, or returns null when [table] is null.
  ///
  /// [table] is a name or a [QueryExpression].
  String? compileFrom(QueryBuilder query, dynamic table) {
    if (table == null) {
      return null; // Retorna null se a tabela for nula
    }
    return 'from ' + this.wrapTable(table);
  }

  /// Compiles the joins: `<type> join table on ...`, or `cross join table`
  /// for a cross join without conditions.
  String compileJoins(QueryBuilder query, List<JoinClause> joins) {
    var sql = <String>[];

    for (var join in joins) {
      var table = this.wrapTable(join.table);
      var type = join.type.toLowerCase();

      // A cross join without conditions has no `on`.
      if (type == 'cross' && (join.clauses.isEmpty)) {
        sql.add("cross join $table");
        continue;
      }

      var clauses = <String>[];
      for (var clause in join.clauses) {
        clauses.add(this.compileJoinConstraint(clause));
      }

      // Without conditions there is no `on` (a dangling `on` is invalid).
      if (clauses.isEmpty) {
        sql.add("$type join $table");
        continue;
      }

      // The first condition takes no leading `and`/`or`.
      clauses[0] = this.removeLeadingBoolean(clauses[0]);

      var clausesString = Utils.implode(' ', clauses);
      sql.add("$type join $table on $clausesString");
    }

    return Utils.implode(' ', sql);
  }

  /// Compiles one join condition, its boolean first: `and first = second`.
  ///
  /// A raw condition (`JoinClause.onRaw`) is written as given and
  /// `JoinClause.onTrue` compiles to `and TRUE`. `second` is a column, or for
  /// a `where` condition a placeholder: `?`, or `(?, ?, ...)` for `in` and
  /// `not in` with a list of values (an empty list compiles `0 = 1` for `in`
  /// and `1 = 1` for `not in`).
  String compileJoinConstraint(Map<String, dynamic> clause) {
    if (clause['type'] == 'raw') {
      return '${clause['boolean']} ${clause['sql']}';
    }

    bool isNested = clause['nested'] ?? false;
    if (isNested) {
      return this.compileNestedJoinConstraint(clause);
    }

    // `on TRUE` (JoinClause.onTrue) has no operator or second operand.
    if (clause['first'] is QueryExpression &&
        (clause['first'] as QueryExpression).getValue() == 'TRUE') {
      return "${clause['boolean']} TRUE";
    }

    var first = this.wrap(clause['first']);
    var second;
    bool isWhereClause = clause['where'] ?? false;
    if (isWhereClause) {
      final operator = clause['operator'];
      final values = clause['second'];
      if ((operator == SqlOperator.inList ||
              operator == SqlOperator.notInList) &&
          values is List) {
        if (values.isEmpty) {
          final always = operator == SqlOperator.inList ? '0 = 1' : '1 = 1';
          return "${clause['boolean']} $always";
        }
        // The values are bound one by one by JoinClause.
        second = '(' + this.parameterize(values) + ')';
      } else {
        second = '?';
      }
    } else {
      second = this.wrap(clause['second']);
    }

    return "${clause['boolean']} $first ${clause['operator']} $second";
  }

  /// Compiles a nested group of join conditions: `and (... or ...)`.
  String compileNestedJoinConstraint(Map clause) {
    final clauses = [];
    for (var nestedClause in clause['join'].clauses) {
      clauses.add(this.compileJoinConstraint(nestedClause));
    }
    clauses[0] = this.removeLeadingBoolean(clauses[0]);
    final clausesStr = Utils.implode(' ', clauses);
    return "${clause['boolean']} ($clausesStr)";
  }

  /// Compiles the where clauses of [query]: `where ...`, or an empty string
  /// without any.
  String compileWheres(QueryBuilder query) {
    var sql = <String>[];

    if (Utils.array_is_empty(query.wheresProp)) {
      return '';
    }

    for (var where in query.wheresProp) {
      sql.add(where['boolean'] + ' ' + _compileWhere(query, where));
    }

    // Every clause starts with its boolean; the first one is removed.
    if (Utils.count(sql) > 0) {
      var sqlRe = Utils.implode(' ', sql);

      return 'where ' + removeLeadingBoolean(sqlRe);
    }

    return '';
  }

  /// Compile a single where clause by its `type` via a direct switch.
  ///
  /// SQL is identical to routing through [callMethod]; the switch avoids the
  /// `"where" + type` string allocation and `_methodMap` lookup per clause.
  /// Unknown types fall back to [callMethod] for full backward compatibility.
  String _compileWhere(QueryBuilder query, Map<String, dynamic> where) {
    switch (where['type']) {
      case 'Basic':
        return whereBasic(query, where);
      case 'Nested':
        return whereNested(query, where);
      case 'Sub':
        return whereSub(query, where);
      case 'Between':
        return whereBetween(query, where);
      case 'Exists':
        return whereExists(query, where);
      case 'NotExists':
        return whereNotExists(query, where);
      case 'In':
        return whereIn(query, where);
      case 'NotIn':
        return whereNotIn(query, where);
      case 'InSub':
        return whereInSub(query, where);
      case 'NotInSub':
        return whereNotInSub(query, where);
      case 'Null':
        return whereNull(query, where);
      case 'NotNull':
        return whereNotNull(query, where);
      case 'Date':
        return whereDate(query, where);
      case 'Time':
        return whereTime(query, where);
      case 'Day':
        return whereDay(query, where);
      case 'Month':
        return whereMonth(query, where);
      case 'Year':
        return whereYear(query, where);
      case 'Raw':
        return whereRaw(query, where);
      case 'Column':
        return whereColumn(query, where);
      case 'JsonContains':
        return whereJsonContains(query, where);
      case 'JsonLength':
        return whereJsonLength(query, where);
      case 'Fulltext':
        return whereFullText(query, where);
      case 'ArrayOp':
        return whereArrayOp(query, where);
      case 'Like':
        return whereLike(query, where);
      case 'InRaw':
        return whereInRaw(query, where);
      case 'NotInRaw':
        return whereNotInRaw(query, where);
      case 'InTuple':
        return whereInTuple(query, where);
      case 'NotInTuple':
        return whereNotInTuple(query, where);
      case 'RowValues':
        return whereRowValues(query, where);
      case 'AnyArray':
        return whereAnyArray(query, where);
      case 'BetweenColumns':
        return whereBetweenColumns(query, where);
      case 'ValueBetween':
        return whereValueBetween(query, where);
      default:
        return callMethod('where${where['type']}', [query, where]).toString();
    }
  }

  /// Compiles a nested where group: `(... or ...)`.
  String whereNested(QueryBuilder query, Map<String, dynamic> where) {
    var nested = where['query'];
    return '(' + Utils.substr(this.compileWheres(nested), 6) + ')';
  }

  /// Compiles a comparison with a subquery:
  /// `column <operator> (select ...)`.
  String whereSub(QueryBuilder query, Map<String, dynamic> where) {
    var select = this.compileSelect(where['query']);
    return this.wrap(where['column']) + ' ' + where['operator'] + " ($select)";
  }

  /// Compiles a basic comparison: `column <operator> ?`.
  String whereBasic(QueryBuilder query, Map<String, dynamic> where) {
    var value = this.parameter(where['value']);
    return this.wrap(where['column']) + ' ' + where['operator'] + ' ' + value;
  }

  /// Compiles `column [not] between ? and ?`; a [QueryExpression] bound is
  /// inlined.
  String whereBetween(QueryBuilder query, Map<String, dynamic> where) {
    var between = where['not'] ? 'not between' : 'between';
    final values = where['values'];
    final low = values is List ? this.parameter(values[0]) : '?';
    final high = values is List ? this.parameter(values[1]) : '?';
    return this.wrap(where['column']) + ' ' + between + ' $low and $high';
  }

  /// Compiles `exists (select ...)`.
  String whereExists(QueryBuilder query, Map<String, dynamic> where) {
    return 'exists (' + compileSelect(where['query']) + ')';
  }

  /// Compiles `not exists (select ...)`.
  String whereNotExists(QueryBuilder query, Map<String, dynamic> where) {
    return 'not exists (' + compileSelect(where['query']) + ')';
  }

  static bool _isEmptyInList(dynamic values) =>
      values == null || (values is Iterable && values.isEmpty);

  /// Compiles `column in (?, ...)`.
  String whereIn(QueryBuilder query, Map<String, dynamic> where) {
    // An empty list matches nothing (instead of the invalid `in ()`).
    if (_isEmptyInList(where['values'])) {
      return '0 = 1';
    }

    List<dynamic> values = where['values'];

    var valuesString = this.parameterize(values);

    return this.wrap(where['column']) + ' in (' + valuesString + ')';
  }

  /// Compiles `column not in (?, ...)`.
  String whereNotIn(QueryBuilder query, Map<String, dynamic> where) {
    // An empty list excludes nothing (instead of the invalid `not in ()`).
    if (_isEmptyInList(where['values'])) {
      return '1 = 1';
    }

    var values = this.parameterize(where['values']);

    return this.wrap(where['column']) + ' not in (' + values + ')';
  }

  /// Compiles `column in (select ...)`.
  String whereInSub(QueryBuilder query, Map<String, dynamic> where) {
    var select = this.compileSelect(where['query']);

    return this.wrap(where['column']) + ' in (' + select + ')';
  }

  /// Compiles `column not in (select ...)`.
  String whereNotInSub(QueryBuilder query, Map<String, dynamic> where) {
    var select = this.compileSelect(where['query']);

    return this.wrap(where['column']) + ' not in (' + select + ')';
  }

  /// Compiles `column is null`.
  String whereNull(QueryBuilder query, Map<String, dynamic> where) {
    return this.wrap(where['column']) + ' is null';
  }

  /// Compiles `column is not null`.
  String whereNotNull(QueryBuilder query, Map<String, dynamic> where) {
    return this.wrap(where['column']) + ' is not null';
  }

  /// Compiles `date(column) <operator> ?`.
  String whereDate(QueryBuilder query, dynamic where) {
    return this.dateBasedWhere('date', query, where);
  }

  /// Compiles `time(column) <operator> ?`.
  String whereTime(QueryBuilder query, dynamic where) {
    return dateBasedWhere('time', query, where);
  }

  /// Compiles `day(column) <operator> ?`.
  String whereDay(QueryBuilder query, where) {
    return this.dateBasedWhere('day', query, where);
  }

  /// Compiles `month(column) <operator> ?`.
  String whereMonth(QueryBuilder query, where) {
    return this.dateBasedWhere('month', query, where);
  }

  /// Compiles `year(column) <operator> ?`.
  String whereYear(QueryBuilder query, where) {
    return this.dateBasedWhere('year', query, where);
  }

  /// Compiles `type(column) <operator> ?`, with [type] a SQL function such
  /// as `date` or `year`.
  String dateBasedWhere(String type, QueryBuilder query, where) {
    var value = this.parameter(where['value']);

    return type +
        '(' +
        this.wrap(where['column']) +
        ') ' +
        where['operator'] +
        ' ' +
        value;
  }

  /// Returns the SQL of a raw where clause as given.
  String whereRaw(QueryBuilder query, where) {
    return where['sql'];
  }

  /// Compiles a comparison of two columns: `first <operator> second`, e.g.
  /// `"table1"."col1" = "table2"."col2"`.
  String whereColumn(QueryBuilder query, Map<String, dynamic> where) {
    final firstWrapped = this.wrap(where['first']);
    final secondWrapped = this.wrap(where['second']);
    final operator = where['operator'];

    return '$firstWrapped $operator $secondWrapped';
  }

  /// JSON containment predicate. Throws [UnsupportedError]; dialects that
  /// support it override this.
  String whereJsonContains(QueryBuilder query, Map<String, dynamic> where) {
    throw UnsupportedError(
        'whereJsonContains is not supported by this grammar.');
  }

  /// JSON array length predicate. Throws [UnsupportedError]; dialects that
  /// support it override this.
  String whereJsonLength(QueryBuilder query, Map<String, dynamic> where) {
    throw UnsupportedError('whereJsonLength is not supported by this grammar.');
  }

  /// Full-text search predicate. Throws [UnsupportedError]; dialects that
  /// support it override this.
  String whereFullText(QueryBuilder query, Map<String, dynamic> where) {
    throw UnsupportedError('whereFullText is not supported by this grammar.');
  }

  /// `column [not] like ?`. Dialects override it for case handling; the
  /// generic grammar has no case-sensitive form.
  String whereLike(QueryBuilder query, Map<String, dynamic> where) {
    if (where['lower'] == true) {
      final operator = where['not'] == true ? 'not like' : 'like';
      return 'lower(${this.wrap(where['column'])}) $operator '
          'lower(${this.parameter(where['value'])})';
    }
    if (where['caseSensitive'] == true) {
      throw UnsupportedError(
          'Case-sensitive like is not supported by this grammar.');
    }
    final operator = where['not'] == true ? 'not like' : 'like';
    return '${this.wrap(where['column'])} $operator ${this.parameter(where['value'])}';
  }

  /// `column in (1, 2, 3)` with integers inlined (whereIntegerInRaw).
  String whereInRaw(QueryBuilder query, Map<String, dynamic> where) {
    final values = where['values'] as List;
    if (values.isEmpty) return '0 = 1';
    return '${this.wrap(where['column'])} in (${values.join(', ')})';
  }

  /// `column not in (1, 2, 3)` with integers inlined.
  String whereNotInRaw(QueryBuilder query, Map<String, dynamic> where) {
    final values = where['values'] as List;
    if (values.isEmpty) return '1 = 1';
    return '${this.wrap(where['column'])} not in (${values.join(', ')})';
  }

  /// `(c1, c2) in ((?, ?), ...)` (whereInTuple); empty: never true.
  String whereInTuple(QueryBuilder query, Map<String, dynamic> where) =>
      _tupleIn(where, 'in', '0 = 1');

  /// `(c1, c2) not in ((?, ?), ...)`; empty: always true.
  String whereNotInTuple(QueryBuilder query, Map<String, dynamic> where) =>
      _tupleIn(where, 'not in', '1 = 1');

  String _tupleIn(Map<String, dynamic> where, String operator, String empty) {
    final rows = where['values'] as List;
    if (rows.isEmpty) return empty;
    final columns = (where['columns'] as List).map(this.wrap).join(', ');
    final tuples =
        rows.map((row) => '(${this.parameterize(row as List)})').join(', ');
    return '($columns) $operator ($tuples)';
  }

  /// `(c1, c2) <op> (?, ?)` (whereRowValues).
  String whereRowValues(QueryBuilder query, Map<String, dynamic> where) {
    final columns = (where['columns'] as List).map(this.wrap).join(', ');
    return '($columns) ${where['operator']} '
        '(${this.parameterize(where['values'] as List)})';
  }

  /// Whether a list binding is sent as one array parameter
  /// (`QueryBuilder.whereAnyArray`); grammars without it get `in (...)`.
  bool get supportsArrayBindings => false;

  /// Whether `insert/update/delete ... returning` is compiled
  /// (`QueryBuilder.returning`).
  bool get supportsReturning => false;

  /// `column = any(?)` with one array parameter. Only grammars with
  /// [supportsArrayBindings] produce this clause.
  String whereAnyArray(QueryBuilder query, Map<String, dynamic> where) {
    throw UnsupportedError(
        'Array parameters are not supported by this grammar.');
  }

  /// `column [not] between first and second`, both bounds columns.
  String whereBetweenColumns(QueryBuilder query, Map<String, dynamic> where) {
    final bounds = where['values'] as List;
    final between = where['not'] == true ? 'not between' : 'between';
    return '${this.wrap(where['column'])} $between ${this.wrap(bounds[0])} '
        'and ${this.wrap(bounds[1])}';
  }

  /// `? [not] between first and second` (whereValueBetween).
  String whereValueBetween(QueryBuilder query, Map<String, dynamic> where) {
    final bounds = where['values'] as List;
    final between = where['not'] == true ? 'not between' : 'between';
    return '${this.parameter(where['value'])} $between ${this.wrap(bounds[0])} '
        'and ${this.wrap(bounds[1])}';
  }

  /// `explain [analyze] <sql>` (QueryBuilder.explain).
  String compileExplain(String sql, {bool analyze = false}) =>
      analyze ? 'explain analyze $sql' : 'explain $sql';

  /// Array operator predicate (`@>`/`<@`/`&&`). Dialect-specific — overridden
  /// where supported (PostgreSQL).
  String whereArrayOp(QueryBuilder query, Map<String, dynamic> where) {
    throw UnsupportedError(
        'Array operators are not supported by this grammar.');
  }

  /// Compiles `group by columns`.
  String compileGroups(QueryBuilder query, groups) {
    return 'group by ' + this.columnize(groups);
  }

  /// Compiles the having clauses: `having ...`.
  String compileHavings(
      QueryBuilder query, List<Map<String, dynamic>> havings) {
    var sqlParts = havings.map((having) => compileHaving(having)).toList();

    var combinedSql = sqlParts.join(' ');

    return 'having ' + removeLeadingBoolean(combinedSql);
  }

  /// Compiles one having clause, its boolean first: raw, between, null, not
  /// null, a nested group or a basic comparison ([compileBasicHaving]).
  String compileHaving(Map<String, dynamic> having) {
    switch (having['type']) {
      case 'raw':
        return having['boolean'] + ' ' + having['sql'];
      case 'between':
        final not = having['not'] == true ? 'not ' : '';
        return '${having['boolean']} ${this.wrap(having['column'])} '
            '${not}between ? and ?';
      case 'Null':
        return '${having['boolean']} ${this.wrap(having['column'])} is null';
      case 'NotNull':
        return '${having['boolean']} ${this.wrap(having['column'])} is not null';
      case 'Nested':
        final nested = having['query'] as QueryBuilder;
        final sql = this.compileHavings(nested, nested.havingsProp);
        // Strip "having " from the nested compilation.
        return '${having['boolean']} (${sql.substring(7)})';
    }
    return this.compileBasicHaving(having);
  }

  /// Compiles a basic having comparison: `and column <operator> ?`.
  String compileBasicHaving(Map<String, dynamic> having) {
    var column = this.wrap(having['column']);

    var parameter = this.parameter(having['value']);

    return having['boolean'] +
        ' ' +
        column +
        ' ' +
        having['operator'] +
        ' ' +
        parameter;
  }

  /// Compiles `order by column direction, ...`; raw orders are written as
  /// given.
  String compileOrders(QueryBuilder query, List<Map<String, dynamic>> orders) {
    return 'order by ' +
        Utils.implode(
            ', ',
            orders.map((order) {
              if (order['sql'] != null) {
                return order['sql'];
              }
              return this.wrap(order['column']) + ' ' + order['direction'];
            }).toList());
  }

  /// Compiles the expression of a random order: `RANDOM()`. The seed is
  /// ignored.
  String compileRandom($seed) {
    return 'RANDOM()';
  }

  /// Compiles `limit n`.
  String compileLimit(QueryBuilder query, int limit) {
    return 'limit $limit';
  }

  /// Compiles `offset n`.
  String compileOffset(QueryBuilder query, int offset) {
    return 'offset $offset';
  }

  /// Compiles the unions of [query], followed by their `order by`, `limit`
  /// and `offset`.
  String compileUnions(QueryBuilder query) {
    var sql = '';

    for (var union in query.unionsProp) {
      sql += compileUnion(union);
    }

    if (query.unionOrdersProp.isNotEmpty) {
      sql += ' ' + compileOrders(query, query.unionOrdersProp);
    }

    if (query.unionLimit != null) {
      sql += ' ' + compileLimit(query, query.unionLimit!);
    }

    if (query.unionOffset != null) {
      sql += ' ' + compileOffset(query, query.unionOffset!);
    }

    return sql.trimLeft();
  }

  /// Compiles one union: ` union select ...` or ` union all select ...`.
  String compileUnion(Map<String, dynamic> union) {
    var joiner = union['all'] == true ? ' union all ' : ' union ';
    return joiner + union['query'].toSql();
  }

  /// Compiles a query for whether [query] returns any row:
  /// `select exists(select ...) as "exists"`.
  String compileExists(QueryBuilder query) {
    final select = compileSelect(query);
    return "select exists($select) as ${this.wrap('exists')}";
  }

  /// Compiles a single-row insert:
  /// `insert into table (columns) values (?, ...)`.
  String compileInsert(QueryBuilder query, Map<String, dynamic> values) {
    var table = this.wrapTable(query.fromProp);

    // if (!Utils.is_array(values)) {
    //   values = [values];
    // }
    var columns = this.columnize(values.keys.toList());
    var parameters = this.parameterize(values.values.toList());
    return "insert into $table ($columns) values ($parameters)";
  }

  /// Compile a single-row insert plus an optional `ON CONFLICT` and/or
  /// `RETURNING` clause (used by the low-level fluent insert path).
  String compileInsertWithClauses(
    QueryBuilder query,
    Map<String, dynamic> values,
    OnConflictClause? conflict,
    List<dynamic>? returning,
  ) {
    final buffer = StringBuffer(this.compileInsert(query, values));
    if (conflict != null) {
      buffer.write(' ');
      buffer.write(this.compileOnConflict(conflict));
    }
    if (returning != null) {
      buffer.write(this.compileReturning(returning));
    }
    return buffer.toString();
  }

  /// Compile a multi-row insert (`values (...), (...)`).
  String compileInsertRows(
    QueryBuilder query,
    List<Map<String, dynamic>> rows,
  ) {
    final table = this.wrapTable(query.fromProp);
    final columns = rows.first.keys.toList();
    final columnsSql = this.columnize(columns);
    final singleRow = '(${List.filled(columns.length, '?').join(', ')})';
    final allRows = List.filled(rows.length, singleRow).join(', ');
    return 'insert into $table ($columnsSql) values $allRows';
  }

  /// Compile an "insert or ignore" statement.
  ///
  /// Default (PostgreSQL/SQLite): `INSERT ... ON CONFLICT DO NOTHING`.
  String compileInsertOrIgnore(
    QueryBuilder query,
    List<Map<String, dynamic>> rows,
  ) {
    return '${this.compileInsertRows(query, rows)} on conflict do nothing';
  }

  /// Compile an atomic UPSERT.
  ///
  /// Default (PostgreSQL/SQLite): `INSERT ... ON CONFLICT (uniqueBy) DO UPDATE
  /// SET ...`. When [update] is null, every non-[uniqueBy] column is updated
  /// from the excluded (would-be-inserted) row.
  String compileUpsert(
    QueryBuilder query,
    List<Map<String, dynamic>> rows,
    List<String> uniqueBy,
    Map<String, dynamic>? update,
  ) {
    final insertSql = this.compileInsertRows(query, rows);
    final target = uniqueBy.map((c) => this.wrap(c)).join(', ');

    final setParts = <String>[];
    if (update == null) {
      final columns = rows.first.keys.where((c) => !uniqueBy.contains(c));
      for (final column in columns) {
        setParts.add('${this.wrap(column)} = ${_excludedColumn(column)}');
      }
    } else {
      for (final entry in update.entries) {
        setParts
            .add('${this.wrap(entry.key)} = ${this.parameter(entry.value)}');
      }
    }

    if (setParts.isEmpty) {
      // Nothing to update -> behave like insert-or-ignore.
      return '$insertSql on conflict ($target) do nothing';
    }
    return '$insertSql on conflict ($target) do update set '
        '${setParts.join(', ')}';
  }

  /// Reference to the pseudo-row of would-be-inserted values in a conflict
  /// update. PostgreSQL/SQLite use `excluded.<col>`.
  String _excludedColumn(String column) => upsertInsertedValue(column);

  /// SQL for "the value this upsert tried to insert" in the update part:
  /// `excluded."col"` (PostgreSQL/SQLite), `values(`col`)` on MySQL.
  String upsertInsertedValue(String column) => 'excluded.${this.wrap(column)}';

  /// Compile a standalone `ON CONFLICT` clause from an [OnConflictClause].
  String compileOnConflict(OnConflictClause conflict) {
    final buffer = StringBuffer('on conflict');

    if (conflict.constraint != null) {
      buffer.write(' on constraint ${this.wrap(conflict.constraint)}');
    } else if (conflict.columns.isNotEmpty) {
      buffer.write(' (${conflict.columns.map(this.wrap).join(', ')})');
    }

    if (conflict.doNothing || conflict.updateValues == null) {
      buffer.write(' do nothing');
      return buffer.toString();
    }

    final setParts = <String>[];
    for (final entry in conflict.updateValues!.entries) {
      setParts.add('${this.wrap(entry.key)} = ${this.parameter(entry.value)}');
    }
    buffer.write(' do update set ${setParts.join(', ')}');
    if (conflict.updateWhereRaw != null) {
      buffer.write(' where ${conflict.updateWhereRaw}');
    }
    return buffer.toString();
  }

  /// Compile a `RETURNING` clause. Default is PostgreSQL syntax.
  String compileReturning(List<dynamic> returning) {
    if (returning.isEmpty) return '';
    final cols = returning.length == 1 && returning.first == '*'
        ? '*'
        : this.columnize(returning);
    return ' returning $cols';
  }

  /// Compiles an insert whose generated id is read back. The generic grammar
  /// ignores [sequence] (the id column) and compiles [compileInsert].
  String compileInsertGetId(
      QueryBuilder query, Map<String, dynamic> values, String? sequence) {
    return this.compileInsert(query, values);
  }

  /// Compiles `[with ...] update table [joins] set column = ?, ... [where]`.
  String compileUpdate(QueryBuilder query, Map<String, dynamic> values) {
    var table = this.wrapTable(query.fromProp);

    dynamic columns = [];
    for (var entry in values.entries) {
      columns.add(this.wrap(entry.key) + ' = ' + this.parameter(entry.value));
    }
    columns = Utils.implode(', ', columns);
    // Joins go between the table and `set` (`update t inner join ... set`).
    var joins = '';
    if (query.joinsProp.isNotEmpty) {
      joins = ' ' + this.compileJoins(query, query.joinsProp);
    }

    var where = this.compileWheres(query);
    final res = Utils.trim("update $table$joins set $columns $where");

    return (this.compileExpressions(query) + ' ' + res).trim();
  }

  /// Bindings of an UPDATE, in the order the compiled SQL uses them:
  /// `[with ...] update t [joins] set ... [where]`.
  ///
  /// [QueryExpression] values are removed later by `cleanBindings`.
  List<dynamic> prepareBindingsForUpdate(
      QueryBuilder query, Map<String, dynamic> values) {
    return [
      ...query.bindings['expressions'],
      ...query.bindings['join'],
      ...values.values,
      ...query.bindings['where'],
    ];
  }

  /// Bindings of a DELETE, in the order the compiled SQL uses them:
  /// `[with ...] delete from t [where]`.
  List<dynamic> prepareBindingsForDelete(QueryBuilder query) {
    return [
      ...query.bindings['expressions'],
      ...query.bindings['join'],
      ...query.bindings['where'],
    ];
  }

  /// Compiles `[with ...] delete from table [where]`.
  String compileDelete(QueryBuilder query) {
    var table = this.wrapTable(query.fromProp);
    var where =
        Utils.is_array(query.wheresProp) ? this.compileWheres(query) : '';
    final res = Utils.trim("delete from $table " + where);

    return (this.compileExpressions(query) + ' ' + res).trim();
  }

  /// Compiles `truncate table`, as a map from each statement to its bindings.
  Map<String, dynamic> compileTruncate(QueryBuilder query) {
    return {'truncate ' + this.wrapTable(query.fromProp): []};
  }

  /// Compiles the row lock: [value] when it is SQL text, otherwise an empty
  /// string (the generic grammar has no lock syntax).
  String compileLock(QueryBuilder query, dynamic value) {
    return Utils.is_string(value) ? value : '';
  }

  /// `LOCK TABLE` of the query's table (`QueryBuilder.lockTable`). Only
  /// PostgreSQL has it in a transaction: MySQL's `LOCK TABLES` commits the
  /// current transaction and locks per session.
  String compileLockTable(QueryBuilder query, TableLockMode mode,
      {bool noWait = false}) {
    throw UnsupportedError('lockTable() needs PostgreSQL: MySQL LOCK TABLES '
        'commits the current transaction. Lock rows with lockForUpdate() or '
        'use an advisory lock instead.');
  }

  /// Whether the grammar supports savepoints.
  bool supportsSavepoints() {
    return true;
  }

  /// Compiles `SAVEPOINT name`.
  String compileSavepoint(String name) {
    return 'SAVEPOINT ' + name;
  }

  /// Compiles `ROLLBACK TO SAVEPOINT name`.
  String compileSavepointRollBack(String name) {
    return 'ROLLBACK TO SAVEPOINT ' + name;
  }

  /// Joins the compiled [segments] with spaces, skipping empty and null ones.
  String concatenate(Map<String, dynamic> segments) {
    // return Utils.implode(' ', Utils.array_filter(segments,  (value) {
    //     return value != '';
    // }));

    return segments.values
        .where((value) => value != '' && value != null)
        .join(' ');
  }

  /// Replaces each `?` outside string literals in [sql] with the escaped
  /// binding, for logs and debugging (QueryBuilder.toRawSql). Never execute
  /// the result: the escaping is best-effort.
  String substituteBindingsIntoRawSql(String sql, List bindings) {
    final escaped = bindings.map(this.escapeRawValue).toList();
    final buffer = StringBuffer();
    var next = 0;
    var inString = false;
    for (var i = 0; i < sql.length; i++) {
      final char = sql[i];
      final pair = i + 1 < sql.length ? sql.substring(i, i + 2) : char;
      // '' (SQL) and \' (MySQL) are escaped quotes inside a literal.
      if (inString && (pair == "''" || pair == "\\'")) {
        buffer.write(pair);
        i++;
        continue;
      }
      if (char == "'") {
        inString = !inString;
        buffer.write(char);
      } else if (char == '?' && !inString && next < escaped.length) {
        buffer.write(escaped[next++]);
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  /// SQL literal for a binding in [substituteBindingsIntoRawSql].
  String escapeRawValue(dynamic value) {
    if (value == null) return 'null';
    if (value is bool) return this.escapeRawBool(value);
    if (value is num || value is BigInt) return value.toString();
    if (value is QueryExpression) return value.getValue().toString();
    if (value is Uint8List) return this.escapeRawBinary(value);
    if (value is DateTime) {
      return this.quoteRawString(this.formatDateTime(value));
    }
    if (value is Map || value is List) {
      return this.quoteRawString(jsonEncode(value));
    }
    return this.quoteRawString(value.toString());
  }

  /// A quoted string literal (`'` doubled).
  String quoteRawString(String value) => "'${value.replaceAll("'", "''")}'";

  String escapeRawBool(bool value) => value ? '1' : '0';

  String escapeRawBinary(Uint8List value) =>
      "x'${value.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}'";

  /// Removes the boolean that leads a list of conditions: an `and ` or `or `
  /// (in any case) at the start of [value]. An `and`/`or` further in is
  /// kept.
  String removeLeadingBoolean(String value) {
    return value.replaceFirst(_leadingBoolean, '');
  }

  static final RegExp _leadingBoolean =
      RegExp(r'^\s*(and|or)\s+', caseSensitive: false);
}
