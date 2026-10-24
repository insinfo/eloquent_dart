import 'dart:async';
import 'dart:convert';

import 'package:eloquent/src/connection_interface.dart';
import 'package:eloquent/src/driver/driver_access.dart';
import 'package:eloquent/src/contracts/pagination/default_length_aware_paginator.dart';
import 'package:eloquent/src/contracts/pagination/default_paginator.dart';
import 'package:eloquent/src/contracts/pagination/length_aware_paginator.dart';
import 'package:eloquent/src/contracts/pagination/pagination_utils.dart';

import 'package:eloquent/src/pdo/core/pdo_result.dart';
import 'package:eloquent/src/query/cursor_pagination.dart';
import 'package:eloquent/src/query/expression.dart';
import 'package:eloquent/src/query/grammars/query_grammar.dart';
import 'package:eloquent/src/query/join_clause.dart';
import 'package:eloquent/src/query/on_conflict_clause.dart';
import 'package:eloquent/src/query/processors/processor.dart';
import 'package:eloquent/src/query/query_lock.dart';
import 'package:eloquent/src/exceptions/records_not_found_exception.dart';
import 'package:eloquent/src/exceptions/unique_constraint_violation_exception.dart';
import 'package:eloquent/src/query/sql_constants.dart';
import 'package:eloquent/src/support/arr.dart';
import 'package:eloquent/src/utils/utils.dart';

/// Default of optional `value` parameters, so `where(col, x)` (two arguments)
/// can be told apart from `where(col, x, null)`.
class _Absent {
  const _Absent();
}

const Object _absent = _Absent();

/// A [QueryBuilder.afterQuery] callback: changes the rows in place or
/// returns new ones (`null` keeps them).
typedef AfterQueryCallback = FutureOr<List<Map<String, dynamic>>?> Function(
    List<Map<String, dynamic>> rows);

/// What [QueryBuilder.count] counts on grouped, `having`, `union` or
/// `distinct` queries.
enum CountMode {
  /// The number of rows the query returns: such queries are counted through
  /// `select count(*) from (<query>) as "aggregate_table"`.
  rows,

  /// Laravel's semantics: a plain `count(...)` aggregate. With `groupBy` (and
  /// no `having`/`union`) it returns the first group's count, and
  /// `distinct()` with `*` counts every row. With `having` or `union` Laravel
  /// itself counts through a subquery, and so does this mode.
  laravel,
}

class QueryBuilder {
  /// The common table expressions.
  List<Map<String, dynamic>> expressionsProp = [];

  /// The recursion limit.
  int? recursionLimitProp;

  /// Returns the builder state named [propertyName].
  ///
  /// The names are Laravel's property names (`'columns'`, `'wheres'`,
  /// `'orders'`, `'unionLimit'`, ...); the grammar reads the select
  /// components through it, as Laravel reads `$query->{$component}`. Throws
  /// [ArgumentError] for an unknown name.
  dynamic getProperty(String propertyName) {
    switch (propertyName) {
      case 'columns':
        return this.columnsProp;
      case 'from':
        return this.fromProp;
      case 'limit':
        return this.limitProp;
      case 'offset':
        return this.offsetProp;
      case 'aggregate':
        return this.aggregateProp;
      case 'distinct':
        return this.distinctProp;
      case 'joins':
        return this.joinsProp;
      case 'wheres':
        return this.wheresProp;
      case 'groups':
        return this.groupsProp;
      case 'havings':
        return this.havingsProp;
      case 'orders':
        return this.ordersProp;
      case 'unions':
        return this.unionsProp;
      case 'bindings':
        return this.bindings;
      case 'unionLimit':
        return this.unionLimit;
      case 'unionOffset':
        return this.unionOffset;
      case 'unionOrders':
        return this.unionOrdersProp;
      case 'lock':
        return this.lockProp;
      case 'backups':
        return this.backups;
      case 'bindingBackups':
        return this.bindingBackups;
      case 'operators':
        return this._operators;
      case 'recursionLimit':
        return this.recursionLimitProp;
      case 'expressions':
        return this.expressionsProp;
      default:
        // It used to print and return the name itself as the value.
        throw ArgumentError.value(
            propertyName, 'propertyName', 'Unknown QueryBuilder property.');
    }
  }

  /// The database connection instance.
  late ConnectionInterface connection;

  /// The database query grammar instance.
  late QueryGrammar grammar;

  /// The database query post processor instance.
  late Processor processor;

  /// The current query value bindings.
  Map<String, List<dynamic>> bindings = {
    'select': [],
    'from': [],
    'join': [],
    'where': [],
    'groupBy': [],
    'having': [],
    'order': [],
    'union': [],
    // Orders of a union are compiled after every union part.
    'unionOrder': [],
    'expressions': [],
  };

  /// An aggregate function and column to be run.
  Map<String, dynamic>? aggregateProp;

  /// The columns that should be returned; null selects `*`.
  List<dynamic>? columnsProp;

  List<dynamic>? getColumns() {
    return columnsProp;
  }

  void setColumns(List<dynamic>? cols) {
    columnsProp = cols;
  }

  /// Indicates if the query returns distinct results.
  bool distinctProp = false;

  /// Columns for a PostgreSQL `SELECT DISTINCT ON (...)` clause.
  List<String>? distinctOnProp;

  /// The table which the query is targeting.
  dynamic fromProp;

  /// The table joins for the query.
  List<JoinClause> joinsProp = [];

  /// The where constraints for the query.
  List<Map<String, dynamic>> wheresProp = [];

  /// The groupings for the query.
  List groupsProp = [];

  /// The having constraints for the query.
  List<Map<String, dynamic>> havingsProp = [];

  /// The orderings for the query.
  List<Map<String, dynamic>> ordersProp = [];

  /// The maximum number of records to return.
  int? limitProp;

  /// The number of records to skip.
  int? offsetProp;

  /// The query union statements.
  List<Map<String, dynamic>> unionsProp = [];

  /// The maximum number of union records to return.
  int? unionLimit;

  /// The number of union records to skip.
  int? unionOffset;

  /// The orderings for the union query.
  List<Map<String, dynamic>> unionOrdersProp = [];

  /// The row lock: `true` (for update), `false` (shared), a [QueryLock] or a
  /// raw lock clause; null means no lock.
  dynamic lockProp;

  /// The `orders`, `limit`, `offset` and `columns` saved while the count of
  /// [getCountForPagination] runs.
  Map<String, dynamic> backups = {};

  /// The `order` and `select` bindings saved while the count of
  /// [getCountForPagination] runs.
  Map<String, List<dynamic>> bindingBackups = {};

  /// All of the available clause operators.
  final List<String> _operators = List<String>.from(SqlOperator.defaults);

  /// Whether selects run on the write connection.
  bool useWritePdoProp = false;

  /// The `ON CONFLICT` clause compiled into [insert], set by
  /// [onConflict], [doUpdate] and [doNothing].
  OnConflictClause? onConflictProp;

  /// The columns of the `RETURNING` clause compiled into [insert], set by
  /// [returning]; the insert's results then hold the inserted rows.
  List<dynamic>? returningProp;

  /// Creates a query builder on [connection] that compiles with [grammar] and
  /// post-processes results with [processor].
  QueryBuilder(this.connection, this.grammar, this.processor);

  /// Adds a common table expression: `with name (columns) as (query)`.
  ///
  /// [query] is a [QueryBuilder], a `Function(QueryBuilder)` that builds the
  /// subquery, or raw SQL. [columns] is an optional list of column names.
  /// [recursive] makes the clause `with recursive` (for every CTE of the
  /// query); [materialized] emits `as MATERIALIZED (...)` (PostgreSQL).
  QueryBuilder withExpression(String name, dynamic query,
      [dynamic columns, bool recursive = false, bool materialized = false]) {
    final sub = this.createSub(query);
    final sql = sub[0] as String;
    final bindings = sub[1] as List;
    this.expressionsProp.add({
      'name': name,
      'query': sql,
      'columns': columns,
      'recursive': recursive,
      'materialized': materialized,
    });
    this.addBinding(bindings, 'expressions');
    return this;
  }

  /// Adds a recursive common table expression: `with recursive name ...`.
  ///
  /// Takes the same forms of [query] and [columns] as [withExpression].
  QueryBuilder withRecursiveExpression(String name, query,
      [columns = null, bool materialized = false]) {
    return this.withExpression(name, query, columns, true, materialized);
  }

  /// Adds a non-recursive, materialized common table expression:
  /// `with name as MATERIALIZED (query)` (PostgreSQL 12+).
  ///
  /// Takes the same forms of [query] and [columns] as [withExpression].
  QueryBuilder withMaterializedExpression(String name, dynamic query,
      [dynamic columns]) {
    final sub = this.createSub(query);
    final sql = sub[0] as String;
    final bindings = sub[1] as List;
    this.expressionsProp.add({
      'name': name,
      'query': sql,
      'columns': columns,
      'recursive': false,
      'materialized': true,
    });
    this.addBinding(bindings, 'expressions');
    return this;
  }

  /// Sets the recursion limit of the query's recursive CTEs.
  ///
  /// The base grammar compiles it as SQL Server's `option (maxrecursion n)`;
  /// the PostgreSQL and MySQL grammars throw [UnsupportedError] when the
  /// query is compiled.
  QueryBuilder recursionLimit(int value) {
    this.recursionLimitProp = value;
    return this;
  }

  /// Inserts the rows selected by [query] into [columns] of the table:
  /// `insert into table (columns) select ...`.
  ///
  /// [query] is a [QueryBuilder], a `Function(QueryBuilder)` or raw SQL. The
  /// common table expressions of this builder ([withExpression]) are
  /// compiled into the insert. Returns the driver's insert result.
  Future<dynamic> insertUsing(columns, query) async {
    final sub = this.createSub(query);
    final sql = sub[0] as String;
    final subBindings = sub[1] as List;

    // The CTEs come before the select in the SQL of every grammar, so their
    // bindings come first, then the subquery's.
    final exprBindings = bindings['expressions'] ?? <dynamic>[];

    final List<dynamic> mergedBindings = [
      ...exprBindings,
      ...subBindings,
    ];

    final res = await this.connection.insert(
        this.grammar.compileInsertUsing(this, columns, sql),
        this.cleanBindings(mergedBindings));
    return res;
  }

  /// Sets the columns to be selected, replacing the previous select list and
  /// its bindings.
  ///
  /// [columnsP] is a column, a list of columns, or a map
  /// `{alias: column-or-subquery}`: a column becomes `column as alias` and a
  /// subquery (`QueryBuilder` or `Function(QueryBuilder)`) becomes
  /// `(subquery) as alias`. Defaults to `*`.
  QueryBuilder select([dynamic columnsP = const ['*']]) {
    this.bindings['select'] = [];
    if (columnsP is Map) {
      this.columnsProp = [];
      _addSelectEntries(columnsP);
    } else if (columnsP is List) {
      this.columnsProp = columnsP;
    } else if (columnsP != null) {
      this.columnsProp = [columnsP];
    } else {
      this.columnsProp = const ['*'];
    }
    return this;
  }

  static bool _isQueryable(dynamic value) =>
      value is QueryBuilder || value is Function;

  void _addSelectEntries(Map columns) {
    columns.forEach((alias, column) {
      if (alias is String && _isQueryable(column)) {
        this.selectSub(column, alias);
      } else if (alias is String && column is String) {
        this.columnsProp = [...?this.columnsProp, '$column as $alias'];
      } else {
        this.columnsProp = [...?this.columnsProp, column];
      }
    });
  }

  /// Adds `(query) as alias` to the select list.
  ///
  /// [query] is a [QueryBuilder], a `Function(QueryBuilder)` or raw SQL; its
  /// bindings go to the select bindings.
  QueryBuilder selectSub(dynamic query, String alias) {
    final res = this.createSub(query);
    final newQuery = res[0] as String;
    final bindings = res[1] as List;

    return this.selectRaw(
        '(' + newQuery + ') as ' + this.grammar.wrap(alias), bindings);
  }

  /// Adds a raw SQL [expression] to the select list, with [bindingsP] for
  /// its `?` placeholders.
  QueryBuilder selectRaw(String expression, [List? bindingsP = const []]) {
    this.addSelect(QueryExpression(expression));

    if (bindingsP != null) {
      this.addBinding(bindingsP, 'select');
    }

    return this;
  }

  /// Sets the FROM clause to the raw SQL [expression], with [bindingsP] for
  /// its `?` placeholders.
  ///
  /// ```dart
  ///  var map = await db
  ///     .table('clientes')
  ///     .selectRaw('clientes.*')
  ///     .fromRaw('(SELECT * FROM public.clientes) AS clientes')
  ///     .limit(1)
  ///     .first();
  /// ```
  QueryBuilder fromRaw(String expression, [List? bindingsP = const []]) {
    this.fromProp = QueryExpression(expression);
    this.addBinding(bindingsP, 'from');
    return this;
  }

  /// Returns `[sql, bindings]` for a subquery.
  ///
  /// [query] is a [QueryBuilder], raw SQL, a [QueryExpression], or a
  /// `Function(QueryBuilder)` that is called with a new builder (see
  /// [forSubQuery]) to build it.
  List createSub(dynamic query) {
    // A function receives a fresh query to build before it is compiled.
    if (query is Function) {
      final callback = query;
      callback(query = this.forSubQuery());
    }

    final result = this.parseSub(query);

    return result;
  }

  /// Returns `[sql, bindings]` for a [QueryBuilder], raw SQL or a
  /// [QueryExpression].
  ///
  /// Raw SQL and expressions have no bindings. Throws [ArgumentError] for
  /// any other value.
  List parseSub(dynamic query) {
    if (query is QueryBuilder) {
      return [query.toSql(), query.getBindings()];
    } else if (query is String) {
      return [query, []];
    } else if (query is QueryExpression) {
      // Used by lateral joins. An expression carries no bindings: the caller
      // adds them separately.
      return [query.getValue(), []];
    } else {
      throw ArgumentError.value(query, 'query',
          'Expected a QueryBuilder, String, or QueryExpression.');
    }
  }

  /// Adds a column, a list of columns or a map `{alias: column-or-subquery}`
  /// to the select list.
  ///
  /// A map entry adds `column as alias` or `(subquery) as alias`; when it
  /// has a subquery and nothing was selected yet, the table's columns
  /// (`table.*`) are kept, as in Laravel.
  QueryBuilder addSelect(dynamic columnP) {
    if (columnP is Map) {
      if (this.columnsProp == null &&
          columnP.values.any(_isQueryable) &&
          this.fromProp is String) {
        this.columnsProp = ['${_fromAlias()}.*'];
      }
      _addSelectEntries(columnP);
      return this;
    }
    var col = columnP is List ? columnP : [columnP];
    this.columnsProp = [...?columnsProp, ...col];
    return this;
  }

  /// The alias of the FROM table (`t` in `table as t`), or the table itself.
  String _fromAlias() {
    final from = this.fromProp.toString();
    final match =
        RegExp(r'\s+as\s+(\S+)$', caseSensitive: false).firstMatch(from);
    return match != null ? match.group(1)! : from;
  }

  /// Makes the query `select distinct`.
  QueryBuilder distinct() {
    this.distinctProp = true;

    return this;
  }

  /// PostgreSQL `SELECT DISTINCT ON (columns) ...`.
  ///
  /// Keeps only the first row of each set of rows where the given [columns]
  /// are equal. Pair with `orderBy` on the same leading columns to make the
  /// choice deterministic.
  QueryBuilder distinctOn(List<String> columns) {
    this.distinctOnProp = columns;
    this.distinctProp = true;
    return this;
  }

  /// Sets the table the query targets, `table as alias` when [as] is given.
  ///
  /// [tableP] is a table name, a [QueryExpression], or a subquery
  /// (`QueryBuilder` or `Function(QueryBuilder)`, see [fromSub]), which
  /// requires [as].
  QueryBuilder from(dynamic tableP, [String? as]) {
    if (_isQueryable(tableP)) {
      if (as == null) {
        throw ArgumentError.notNull('as (alias of the subquery in FROM)');
      }
      return this.fromSub(tableP, as);
    }
    this.fromProp = as != null ? '$tableP as $as' : tableP;
    return this;
  }

  /// `from (subquery) as alias`.
  QueryBuilder fromSub(dynamic query, String alias) {
    final res = this.createSub(query);
    return this.fromRaw(
        '(${res[0]}) as ${this.grammar.wrapTable(alias)}', res[1] as List);
  }

  /// Adds a join: `type join table on one operator two`.
  ///
  /// [table] is a table name or a [QueryExpression]. [one] is the first
  /// column, or a `Function(JoinClause)` that adds several `on`/`where`
  /// conditions (then [operator] and [two] are ignored). [type] is the join
  /// type (`inner`, `left`, `right`, `cross`). With [where] the condition
  /// compares [one] with the bound value [two] instead of a column.
  QueryBuilder join(dynamic table, dynamic one,
      [String? operator,
      dynamic two = null,
      String type = SqlJoin.inner,
      bool where = false]) {
    // A function builds a join with several conditions.
    if (one is Function) {
      final join = JoinClause(type, table, this);
      one(join);
      this.joinsProp.add(join);
      this.addBinding(join.bindingsLocal, 'join');
    }
    // Otherwise the join has a single "on" condition.
    else {
      final join = JoinClause(type, table, this);
      this.joinsProp.add(join.on(one, operator, two, SqlBool.and, where));
      this.addBinding(join.bindingsLocal, 'join');
    }

    return this;
  }

  /// Adds a join whose condition compares column [one] with the bound value
  /// [two]: `join table on one operator ?`.
  QueryBuilder joinWhere(String table, one, String? operator, two,
      [String type = SqlJoin.inner]) {
    return this.join(table, one, operator, two, type, true);
  }

  /// Joins a subquery: `join (query) as alias on ...`.
  ///
  /// [query] is a [QueryBuilder], a `Function(QueryBuilder)` or raw SQL. The
  /// remaining arguments are those of [join]; [first] may be a
  /// `Function(JoinClause)`.
  ///
  /// ```dart
  /// var subQuery = db
  ///     .table('public.clientes')
  ///     .selectRaw('clientes_grupos.numero_cliente as numero_cliente, '
  ///         'json_agg(row_to_json(grupos.*)) as grupos')
  ///     .join('public.clientes_grupos', 'clientes_grupos.numero_cliente',
  ///         '=', 'clientes.numero')
  ///     .join('public.grupos', 'grupos.numero', '=',
  ///         'clientes_grupos.numero_grupo')
  ///     .groupBy('numero_cliente');
  ///
  /// var map = await db
  ///     .table('clientes')
  ///     .selectRaw('clientes.*')
  ///     .fromRaw('(SELECT * FROM public.clientes) AS clientes')
  ///     .joinSub(subQuery, 'grupos', (JoinClause join) {
  ///       join.on('grupos.numero_cliente', '=', 'clientes.numero');
  ///     })
  ///     .limit(1)
  ///     .first();
  /// ```
  QueryBuilder joinSub(dynamic query, alias, dynamic first,
      [String? operator,
      dynamic second,
      String type = SqlJoin.inner,
      bool where = false]) {
    final res = this.createSub(query);

    final newQuery = res[0] as String;
    final bindings = res[1] as List;

    final expression = '(' + newQuery + ') as ' + this.grammar.wrap(alias);

    this.addBinding(bindings, 'join');

    return this.join(
        QueryExpression(expression), first, operator, second, type, where);
  }

  /// `left join (subquery) as alias on ...`.
  QueryBuilder leftJoinSub(dynamic query, String alias, dynamic first,
          [String? operator, dynamic second]) =>
      this.joinSub(query, alias, first, operator, second, SqlJoin.left);

  /// `right join (subquery) as alias on ...`.
  QueryBuilder rightJoinSub(dynamic query, String alias, dynamic first,
          [String? operator, dynamic second]) =>
      this.joinSub(query, alias, first, operator, second, SqlJoin.right);

  /// `cross join (subquery) as alias`.
  QueryBuilder crossJoinSub(dynamic query, String alias) {
    final res = this.createSub(query);
    this.addBinding(res[1], 'join');
    return this.crossJoin(
        QueryExpression('(${res[0]}) as ${this.grammar.wrapTable(alias)}'));
  }

  /// Adds a `left join`; see [join] for the forms of [first].
  QueryBuilder leftJoin(String table, first,
      [String? operator, dynamic second]) {
    return this.join(table, first, operator, second, SqlJoin.left);
  }

  /// Adds a `left join` comparing column [one] with the bound value [two];
  /// see [joinWhere].
  QueryBuilder leftJoinWhere(
      String table, dynamic one, String operator, dynamic two) {
    return this.joinWhere(table, one, operator, two, SqlJoin.left);
  }

  /// Adds a `right join`; see [join] for the forms of [first].
  QueryBuilder rightJoin(String table, dynamic first, String operator,
      [dynamic second]) {
    return this.join(table, first, operator, second, SqlJoin.right);
  }

  /// Adds a `right join` comparing column [one] with the bound value [two];
  /// see [joinWhere].
  QueryBuilder rightJoinWhere(
      String table, dynamic one, String operator, dynamic two) {
    return this.joinWhere(table, one, operator, two, SqlJoin.right);
  }

  /// Adds a `cross join table`.
  ///
  /// With [first] the join gets an `on` condition, as in [join].
  QueryBuilder crossJoin(dynamic table,
      [dynamic first, String? operator, dynamic second]) {
    if (first != null) {
      return this.join(table, first, operator, second, SqlJoin.cross);
    }
    this.joinsProp.add(JoinClause(SqlJoin.cross, table, this));
    return this;
  }

  /// Runs [callback] when [condition] is truthy, otherwise [otherwise].
  ///
  /// Truthy means not null, false, 0, '' or an empty collection.
  /// [condition] may be a function returning the value. A callback that
  /// takes two parameters also receives the value:
  /// `when(nome, (q, n) => q.where(...))`.
  QueryBuilder when(dynamic condition, Function callback,
      [Function? otherwise]) {
    final value = condition is dynamic Function() ? condition() : condition;
    if (_isTruthy(value)) {
      _callConditional(callback, value);
    } else if (otherwise != null) {
      _callConditional(otherwise, value);
    }
    return this;
  }

  /// The opposite of [when]: runs [callback] when [condition] is falsy.
  QueryBuilder unless(dynamic condition, Function callback,
      [Function? otherwise]) {
    final value = condition is dynamic Function() ? condition() : condition;
    if (!_isTruthy(value)) {
      _callConditional(callback, value);
    } else if (otherwise != null) {
      _callConditional(otherwise, value);
    }
    return this;
  }

  /// Passes the builder to [callback] (to apply a reusable scope) and
  /// returns it.
  QueryBuilder tap(void Function(QueryBuilder query) callback) {
    callback(this);
    return this;
  }

  void _callConditional(Function callback, dynamic value) {
    if (callback is dynamic Function(QueryBuilder, Never)) {
      Function.apply(callback, [this, value]);
    } else {
      Function.apply(callback, [this]);
    }
  }

  static bool _isTruthy(dynamic value) {
    if (value == null || value == false || value == 0 || value == '') {
      return false;
    }
    if (value is Iterable) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  /// Adds a where clause: `column operator ?`.
  ///
  /// [column] is a column, a map `{column: value}` (each compared with `=`,
  /// grouped in parentheses), or a `Function(QueryBuilder)` that builds a
  /// nested group (see [whereNested]). A [value] that is a
  /// `Function(QueryBuilder)` is a subquery: `column operator (select ...)`.
  /// A [QueryExpression] value is inlined instead of bound. [boolean] is the
  /// connector with the previous condition (`and`/`or`).
  ///
  /// Called with two arguments (`where('status', 'ativo')`) the second one is
  /// the value and the operator is `=`, as in Laravel. A `null` value becomes
  /// `is null` for `=` and `is not null` for `<>`/`!=`; any other operator with
  /// `null` throws [ArgumentError] instead of silently changing the filter.
  ///
  /// ```dart
  /// query.where((QueryBuilder qw1) {
  ///   for (var i = 0; i < processos.length; i++) {
  ///     var proc = processos[i];
  ///     if (i == 0) {
  ///       qw1.where((QueryBuilder q) {
  ///         q.where('sw_processo.cod_processo', '=', proc.keys.first);
  ///         q.where('sw_processo.ano_exercicio', '=', proc.values.first);
  ///       });
  ///     } else {
  ///       qw1.orWhere((QueryBuilder q) {
  ///         q.where('sw_processo.cod_processo', '=', proc.keys.first);
  ///         q.where('sw_processo.ano_exercicio', '=', proc.values.first);
  ///       });
  ///     }
  ///   }
  /// });
  /// ```
  QueryBuilder where(dynamic column,
      [dynamic operator,
      dynamic value = _absent,
      String boolean = SqlBool.and]) {
    // Two-argument form: the "operator" slot holds the value.
    if (identical(value, _absent)) {
      if (column is Map || column is Function) {
        value = null;
      } else {
        value = operator;
        operator = SqlOperator.equals;
      }
    }

    // A map of column/value pairs becomes a nested group of `=` conditions,
    // joined to the query with the given boolean.
    if (column is Map) {
      return this.whereNested((query) {
        for (var entry in column.entries) {
          query.where(entry.key, SqlOperator.equals, entry.value);
        }
      }, boolean);
    }

    // A function builds a nested group wrapped in parentheses.
    if (column is Function) {
      return this.whereNested(column, boolean);
    }

    if (operator != null && operator is! String) {
      throw ArgumentError.value(operator, 'operator',
          'Expected an SQL operator such as "=", ">" or "like".');
    }

    if (value is Function) {
      return this
          .whereSub(column as String, operator as String?, value, boolean);
    }

    // `= null` means "is null" and `<> null` / `!= null` means "is not null".
    // Any other comparison with null matches nothing in SQL, so it is an error.
    if (value == null) {
      final op = (operator as String?)?.trim().toLowerCase();
      if (op == null || op == SqlOperator.equals || op == '==') {
        return this.whereNull(column as String, boolean, false);
      }
      if (op == '<>' || op == '!=') {
        return this.whereNull(column as String, boolean, true);
      }
      throw ArgumentError.value(
          value,
          'value',
          'Operator "$operator" cannot be compared with null; '
              'use whereNull/whereNotNull.');
    }

    const type = SqlWhereType.basic;

    this.wheresProp.add({
      'type': type,
      'column': column,
      'operator': operator,
      'value': value,
      'boolean': boolean
    });

    if (!(value is QueryExpression)) {
      // One placeholder, one binding: a List value (Uint8List, a PostgreSQL
      // array, JSON) used to be spread into several bindings.
      this.addBinding([value], 'where');
    }

    return this;
  }

  /// Adds an `or` where clause; takes the same arguments as [where].
  QueryBuilder orWhere(dynamic column,
      [dynamic operator, dynamic value = _absent]) {
    return this.where(column, operator, value, SqlBool.or);
  }

  /// Adds a where clause, guessing the operator from the arguments' values.
  ///
  /// Prefer [where], which tells `where(c, v)` from `where(c, op, v)` by the
  /// number of arguments. Here a missing argument and `null` are the same,
  /// so the forms are told apart by value:
  ///
  /// - [column] as a map or a `Function(QueryBuilder)` adds a nested group,
  ///   as in [where].
  /// - With [operator] and a non-null [value], [operator] must be a known
  ///   operator; otherwise it throws [ArgumentError].
  /// - With [operator] and a null [value], a known operator is used with
  ///   `null` (`=`/`==` become `is null`, `!=`/`<>` `is not null`, any other
  ///   throws [ArgumentError]); anything else is the value, compared with
  ///   `=`. So a value that is itself an operator (`'like'`, `'='`) is read
  ///   as the operator.
  /// - Without [operator] the clause is `column is null`.
  /// - A `Function(QueryBuilder)` value is a subquery, as in [whereSub].
  ///
  /// As in [where], a list value is one binding for its one placeholder.
  ///
  /// ```dart
  /// query.whereFlex('email', 'test@example.com'); // "email" = ?
  /// query.whereFlex('age', '>', 18); // "age" > ?
  /// query.whereFlex('deleted_at', '=', null); // "deleted_at" is null
  /// ```
  QueryBuilder whereFlex(dynamic column,
      [dynamic operator, // Kept as dynamic
      dynamic value,
      String boolean = SqlBool.and]) {
    if (column is Map) {
      return this.whereNested((query) {
        column.forEach((k, v) {
          query.where(k, SqlOperator.equals, v);
        });
      }, boolean);
    }

    if (column is Function(QueryBuilder)) {
      return this.whereNested(column, boolean);
    }

    String? finalOperator;
    dynamic finalValue;

    if (operator != null) {
      if (value != null) {
        // whereFlex('column', 'op', value): the operator must be known.
        if (operator is String && isValidOperator(operator)) {
          finalOperator = operator;
          finalValue = value;
        } else {
          throw ArgumentError(
              'When 3 arguments are provided, the second must be a valid string operator. Got type ${operator.runtimeType} ("$operator")');
        }
      } else {
        // whereFlex('column', x): x is the operator (compared with null
        // below) when it is a known operator, otherwise the value.
        if (operator is String && isValidOperator(operator)) {
          finalOperator = operator;
          finalValue = null;
        } else {
          finalOperator = SqlOperator.equals;
          finalValue = operator;
        }
      }
    } else {
      // whereFlex('column') means `column is null`.
      finalOperator = SqlOperator.equals;
      finalValue = null;
    }

    if (finalValue is Function(QueryBuilder)) {
      return this
          .whereSub(column as String, finalOperator, finalValue, boolean);
    }

    if (finalValue == null) {
      bool not = (finalOperator == SqlOperator.notEquals ||
          finalOperator == SqlOperator.notEqualsSql);
      if (finalOperator == SqlOperator.equals ||
          finalOperator == SqlOperator.doubleEquals ||
          not) {
        return this.whereNull(column as String, boolean, not);
      }
      // Any other operator with null fails the check below.
    }

    if (this.invalidOperatorAndValue(finalOperator, finalValue)) {
      throw ArgumentError(
          'Illegal operator "$finalOperator" and value combination ($finalValue). Operator must be "=" or "!=" or "<>" if value is null.');
    }

    const type = SqlWhereType.basic;
    this.wheresProp.add({
      'type': type,
      'column': column,
      'operator': finalOperator,
      'value': finalValue,
      'boolean': boolean
    });

    if (!(finalValue is QueryExpression)) {
      // One placeholder, one binding (addBinding spreads a bare list).
      this.addBinding([finalValue], 'where');
    }

    return this;
  }

  /// Adds an `or` where clause; takes the same arguments as [whereFlex].
  QueryBuilder orWhereFlex(dynamic column, [dynamic operator, dynamic value]) {
    return this.whereFlex(column, operator, value, SqlBool.or);
  }

  /// Whether [op] is one of the builder's or the grammar's operators,
  /// ignoring case.
  bool isValidOperator(String? op) {
    if (op == null) return false;
    final allOperators = {..._operators, ...grammar.getOperators()}
        .map((o) => o.toString().toLowerCase())
        .toSet();
    return allOperators.contains(op.toLowerCase());
  }

  /// Whether [operator] cannot be used with [value]: only `=`, `==`, `!=`
  /// and `<>` can be compared with null.
  bool invalidOperatorAndValue(String? operator, dynamic value) {
    if (value == null) {
      bool isValidNullOp = (operator == SqlOperator.equals ||
          operator == SqlOperator.doubleEquals ||
          operator == SqlOperator.notEquals ||
          operator == SqlOperator.notEqualsSql);
      return !isValidNullOp;
    }
    return false;
  }

  /// Adds `column = (select ...)`, the subquery built by [closure].
  QueryBuilder whereSubQueryValue(String column, Function(QueryBuilder) closure,
      [String boolean = SqlBool.and]) {
    return this.where(column, SqlOperator.equals, closure, boolean);
  }

  /// Adds a where clause comparing two columns: `first operator second`.
  ///
  /// When [operator] is not a known operator it is the second column and the
  /// comparison is `=`: `whereColumn('a', 'b')` is `a = b`. [first] may also
  /// be a list or map of conditions, grouped in parentheses (see
  /// [addArrayOfWheres]).
  QueryBuilder whereColumn(dynamic first,
      [String? operator, dynamic second, String boolean = SqlBool.and]) {
    if (first is List || first is Map) {
      return this.addArrayOfWheres(first, boolean, 'whereColumn');
    }

    // Not a known operator: whereColumn('a', 'b') is shorthand for `a = b`.
    if (operator == null ||
        !(this._operators.contains(operator.toLowerCase()) ||
            this.grammar.getOperators().contains(operator.toLowerCase()))) {
      second = operator;
      operator = SqlOperator.equals;
    }

    const type = SqlWhereType.column;

    this.wheresProp.add({
      'type': type,
      'first': first,
      'operator': operator,
      'second': second,
      'boolean': boolean
    });

    return this;
  }

  /// Adds an `or` where clause comparing two columns; see [whereColumn].
  ///
  /// `orWhereColumn('first_name', 'last_name')` adds
  /// `or first_name = last_name`.
  QueryBuilder orWhereColumn(dynamic first,
      [String? operator, dynamic second]) {
    return this.whereColumn(first, operator, second, SqlBool.or);
  }

  /// The builder method an array of conditions is applied with. For
  /// `whereColumn([...])` both sides are columns; it used to fall back to
  /// `where`, binding the second column as a value.
  static Function _arrayWhereMethod(QueryBuilder query, String method) {
    switch (method) {
      case 'orWhere':
        return query.orWhere;
      case 'whereColumn':
        return query.whereColumn;
      case 'orWhereColumn':
        return query.orWhereColumn;
      default:
        return query.where;
    }
  }

  /// Adds a list or map of conditions as one nested group.
  ///
  /// A map entry `{column: value}` is compared with `=`; an entry with an
  /// int key and a list value, or a list item that is itself a list, holds
  /// the arguments of a call to [method] (`'where'`, `'orWhere'`,
  /// `'whereColumn'` or `'orWhereColumn'`). With `whereColumn` the map
  /// values are columns, not bound values.
  QueryBuilder addArrayOfWheres(dynamic column, String boolean,
      [String method = 'where']) {
    return this.whereNested((QueryBuilder query) {
      if (column is Map) {
        column.forEach((key, value) {
          // `{0: ['column', '>', 1]}`: the arguments of a call to [method].
          if (key is int && value is List) {
            Function.apply(_arrayWhereMethod(query, method), value);
          } else if (method == 'whereColumn') {
            // {'first': 'second'}: both sides are columns.
            query.whereColumn(key, SqlOperator.equals, value);
          } else {
            query.where(key, SqlOperator.equals, value);
          }
        });
      }
      // A list holds argument lists and maps of conditions.
      else if (column is List) {
        for (var item in column) {
          if (item is List) {
            Function.apply(_arrayWhereMethod(query, method), item);
          } else if (item is Map) {
            item.forEach((key, value) {
              if (method == 'whereColumn') {
                query.whereColumn(key, SqlOperator.equals, value);
              } else {
                query.where(key, SqlOperator.equals, value);
              }
            });
          }
        }
      }
    }, boolean);
  }

  // ---------------------------------------- whereAny / All / None / Not

  /// `(c1 op ? or c2 op ? ...)`: any of [columns] matches.
  /// `whereAny(['nome', 'email'], 'like', '%ana%')`; with two arguments the
  /// operator is `=`.
  QueryBuilder whereAny(List columns, dynamic operator,
          [dynamic value = _absent, String boolean = SqlBool.and]) =>
      _whereColumnsGroup(columns, operator, value, SqlBool.or, boolean);

  QueryBuilder orWhereAny(List columns, dynamic operator,
          [dynamic value = _absent]) =>
      _whereColumnsGroup(columns, operator, value, SqlBool.or, SqlBool.or);

  /// `(c1 op ? and c2 op ? ...)`: every one of [columns] matches.
  QueryBuilder whereAll(List columns, dynamic operator,
          [dynamic value = _absent, String boolean = SqlBool.and]) =>
      _whereColumnsGroup(columns, operator, value, SqlBool.and, boolean);

  QueryBuilder orWhereAll(List columns, dynamic operator,
          [dynamic value = _absent]) =>
      _whereColumnsGroup(columns, operator, value, SqlBool.and, SqlBool.or);

  /// `not (c1 op ? or c2 op ? ...)`: none of [columns] matches.
  QueryBuilder whereNone(List columns, dynamic operator,
          [dynamic value = _absent, String boolean = SqlBool.and]) =>
      _whereColumnsGroup(columns, operator, value, SqlBool.or, '$boolean not');

  QueryBuilder orWhereNone(List columns, dynamic operator,
          [dynamic value = _absent]) =>
      _whereColumnsGroup(columns, operator, value, SqlBool.or, 'or not');

  QueryBuilder _whereColumnsGroup(List columns, dynamic operator, dynamic value,
      String inner, String boolean) {
    if (identical(value, _absent)) {
      value = operator;
      operator = SqlOperator.equals;
    }
    return this.whereNested((QueryBuilder query) {
      for (final column in columns) {
        query.where(column, operator, value, inner);
      }
    }, boolean);
  }

  /// `not (...)`: the negation of a where (same arguments as [where],
  /// including a `Function(QueryBuilder)` group).
  QueryBuilder whereNot(dynamic column,
          [dynamic operator,
          dynamic value = _absent,
          String boolean = SqlBool.and]) =>
      this.where(column, operator, value, '$boolean not');

  QueryBuilder orWhereNot(dynamic column,
          [dynamic operator, dynamic value = _absent]) =>
      this.where(column, operator, value, 'or not');

  // ------------------------------------------------------------- whereLike

  /// Portable LIKE: case-insensitive by default (`ilike` on PostgreSQL, the
  /// column collation on MySQL); `caseSensitive: true` uses `like` /
  /// `like binary`. `%` and `_` in [value] are wildcards.
  ///
  /// [unaccent] (PostgreSQL, extension `unaccent`) compares
  /// `unaccent(column::text) ilike unaccent(?)`; other grammars ignore it
  /// (on MySQL the collation decides accents). [lower] compares
  /// `lower(column) like lower(?)` instead: the same rows as `ilike`, but an
  /// expression index on `lower(...)` (`text_pattern_ops`, prefix patterns)
  /// can be used, and MySQL ignores case even with a `_bin`/`_cs` collation.
  /// [column] is a column or `db.raw(...)`.
  QueryBuilder whereLike(Object column, String value,
      {bool caseSensitive = false,
      bool unaccent = false,
      bool lower = false,
      String boolean = SqlBool.and,
      bool not = false}) {
    if (lower && caseSensitive) {
      throw ArgumentError('lower: true is case-insensitive; it cannot be '
          'combined with caseSensitive: true.');
    }
    this.wheresProp.add({
      'type': 'Like',
      'column': column,
      'value': value,
      'caseSensitive': caseSensitive,
      'unaccent': unaccent,
      'lower': lower,
      'boolean': boolean,
      'not': not,
    });
    this.addBinding(value, 'where');
    return this;
  }

  QueryBuilder orWhereLike(Object column, String value,
          {bool caseSensitive = false,
          bool unaccent = false,
          bool lower = false}) =>
      this.whereLike(column, value,
          caseSensitive: caseSensitive,
          unaccent: unaccent,
          lower: lower,
          boolean: SqlBool.or);

  QueryBuilder whereNotLike(Object column, String value,
          {bool caseSensitive = false,
          bool unaccent = false,
          bool lower = false,
          String boolean = SqlBool.and}) =>
      this.whereLike(column, value,
          caseSensitive: caseSensitive,
          unaccent: unaccent,
          lower: lower,
          boolean: boolean,
          not: true);

  QueryBuilder orWhereNotLike(Object column, String value,
          {bool caseSensitive = false,
          bool unaccent = false,
          bool lower = false}) =>
      this.whereLike(column, value,
          caseSensitive: caseSensitive,
          unaccent: unaccent,
          lower: lower,
          boolean: SqlBool.or,
          not: true);

  // ----------------------------------------------------- whereIntegerInRaw

  /// `column in (1, 2, 3)` with the integers inlined instead of bound: no
  /// parameter limit (PostgreSQL rejects more than 65535) for long id lists.
  /// Throws for values that are not integers.
  QueryBuilder whereIntegerInRaw(String column, Iterable values,
      [String boolean = SqlBool.and, bool not = false]) {
    final integers = values.map((value) {
      if (value is int) return value;
      if (value is BigInt) return value;
      final parsed = int.tryParse('$value');
      if (parsed == null) {
        throw ArgumentError.value(value, 'values', 'Not an integer.');
      }
      return parsed;
    }).toList();
    this.wheresProp.add({
      'type': not ? 'NotInRaw' : 'InRaw',
      'column': column,
      'values': integers,
      'boolean': boolean,
    });
    return this;
  }

  QueryBuilder orWhereIntegerInRaw(String column, Iterable values) =>
      this.whereIntegerInRaw(column, values, SqlBool.or);

  QueryBuilder whereIntegerNotInRaw(String column, Iterable values,
          [String boolean = SqlBool.and]) =>
      this.whereIntegerInRaw(column, values, boolean, true);

  QueryBuilder orWhereIntegerNotInRaw(String column, Iterable values) =>
      this.whereIntegerInRaw(column, values, SqlBool.or, true);

  // ------------------------------------------------------------ whereSearch

  /// [value] with the LIKE wildcards `%` and `_` (and the escape character
  /// `\`) escaped, so it matches literally inside a LIKE pattern (PostgreSQL
  /// and MySQL use `\` as the LIKE escape character).
  static String escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  /// The LIKE pattern that finds [term] (escaped) as given by [match].
  static String likePattern(String term,
          [SearchMatch match = SearchMatch.contains]) =>
      switch (match) {
        SearchMatch.contains => '%${escapeLike(term)}%',
        SearchMatch.startsWith => '${escapeLike(term)}%',
        SearchMatch.endsWith => '%${escapeLike(term)}',
        SearchMatch.exact => escapeLike(term),
        SearchMatch.wordsInOrder =>
          '%${term.trim().split(RegExp(r'\s+')).map(escapeLike).join('%')}%',
      };

  /// Text search of [term] in [columns]:
  /// `(col1 ilike ? or col2 ilike ? ...)` on PostgreSQL (`like` on MySQL,
  /// where the collation decides case and accents).
  ///
  /// - The term is matched literally: `%` and `_` in it are escaped; [match]
  ///   chooses contains (default), starts with, ends with or the whole value.
  /// - [unaccent] (PostgreSQL, extension `unaccent`) compares
  ///   `unaccent(col::text) ilike unaccent(?)`, so "jose" finds "José".
  /// - [lower] compares `lower(col) like lower(?)` (with [unaccent]:
  ///   `lower(unaccent(col::text)) like lower(unaccent(?))`), the form an
  ///   expression index can serve; see [whereLike].
  /// - [everyWord] splits the term on spaces and requires each word in some
  ///   column: "ana silva" finds "Ana Maria da Silva".
  /// - A null or blank [term] adds nothing, so an optional filter needs no
  ///   `if`.
  /// - [columns] are identifiers (quoted, never SQL), or `db.raw(...)` for an
  ///   expression such as `coalesce(a, b)`.
  ///
  /// ```dart
  /// query.whereSearch(['c.nom_cgm', 'c.cpf'], filtros.searchString,
  ///     unaccent: true);
  /// ```
  QueryBuilder whereSearch(List<Object> columns, String? term,
      {SearchMatch match = SearchMatch.contains,
      bool unaccent = false,
      bool lower = false,
      bool caseSensitive = false,
      bool everyWord = false,
      String boolean = SqlBool.and}) {
    final text = term?.trim() ?? '';
    if (text.isEmpty) return this;
    _checkLikeColumns(columns, 'columns');
    final words = everyWord ? text.split(RegExp(r'\s+')) : [text];

    void anyColumn(QueryBuilder group, String word) {
      for (final column in columns) {
        group.whereLike(column, likePattern(word, match),
            caseSensitive: caseSensitive,
            unaccent: unaccent,
            lower: lower,
            boolean: SqlBool.or);
      }
    }

    if (words.length == 1) {
      return this.whereNested(
          (QueryBuilder group) => anyColumn(group, words.first), boolean);
    }
    return this.whereNested((QueryBuilder all) {
      for (final word in words) {
        all.whereNested((QueryBuilder group) => anyColumn(group, word));
      }
    }, boolean);
  }

  /// [whereSearch] joined with `or`.
  QueryBuilder orWhereSearch(List<Object> columns, String? term,
          {SearchMatch match = SearchMatch.contains,
          bool unaccent = false,
          bool lower = false,
          bool caseSensitive = false,
          bool everyWord = false}) =>
      this.whereSearch(columns, term,
          match: match,
          unaccent: unaccent,
          lower: lower,
          caseSensitive: caseSensitive,
          everyWord: everyWord,
          boolean: SqlBool.or);

  /// `(col1 like ? or col2 like ? ...)` with the LIKE [pattern] as given
  /// (`%` and `_` are wildcards; see [whereSearch] to match a term
  /// literally). Case-insensitive unless [caseSensitive]; [unaccent] as in
  /// [whereSearch].
  QueryBuilder whereAnyLike(List<Object> columns, String pattern,
      {bool caseSensitive = false,
      bool unaccent = false,
      bool lower = false,
      String boolean = SqlBool.and}) {
    _checkLikeColumns(columns, 'columns');
    return this.whereNested((QueryBuilder group) {
      for (final column in columns) {
        group.whereLike(column, pattern,
            caseSensitive: caseSensitive,
            unaccent: unaccent,
            lower: lower,
            boolean: SqlBool.or);
      }
    }, boolean);
  }

  QueryBuilder orWhereAnyLike(List<Object> columns, String pattern,
          {bool caseSensitive = false,
          bool unaccent = false,
          bool lower = false}) =>
      this.whereAnyLike(columns, pattern,
          caseSensitive: caseSensitive,
          unaccent: unaccent,
          lower: lower,
          boolean: SqlBool.or);

  static void _checkLikeColumns(List<Object> columns, String name) {
    if (columns.isEmpty) {
      throw ArgumentError.value(columns, name, 'Must not be empty.');
    }
    for (final column in columns) {
      if (column is QueryExpression) continue;
      if (column is String && column.trim().isNotEmpty) continue;
      throw ArgumentError.value(
          column, name, 'Expected a column name or db.raw(...).');
    }
  }

  // ---------------------------------------------------------- whereInTuple

  /// `(col1, col2) in ((?, ?), (?, ?), ...)`: rows whose composite key is one
  /// of [tuples], e.g. `whereInTuple(['cod_processo', 'ano_exercicio'],
  /// [[10, '2024'], [11, '2025']])`. Every tuple has one value per column;
  /// an empty [tuples] matches nothing. A null in a tuple never matches.
  QueryBuilder whereInTuple(
      List<String> columns, Iterable<List<Object?>> tuples,
      [String boolean = SqlBool.and, bool not = false]) {
    if (columns.isEmpty) {
      throw ArgumentError.value(columns, 'columns', 'Must not be empty.');
    }
    final rows = <List<Object?>>[];
    for (final tuple in tuples) {
      if (tuple.length != columns.length) {
        throw ArgumentError.value(tuple, 'tuples',
            'Expected ${columns.length} values, one per column.');
      }
      rows.add(List<Object?>.of(tuple));
    }
    this.wheresProp.add({
      'type': not ? 'NotInTuple' : 'InTuple',
      'columns': List<String>.of(columns),
      'values': rows,
      'boolean': boolean,
    });
    for (final row in rows) {
      this.addBinding(row, 'where');
    }
    return this;
  }

  QueryBuilder orWhereInTuple(
          List<String> columns, Iterable<List<Object?>> tuples) =>
      this.whereInTuple(columns, tuples, SqlBool.or);

  /// `(col1, col2) not in ((?, ?), ...)`; an empty [tuples] excludes nothing.
  QueryBuilder whereNotInTuple(
          List<String> columns, Iterable<List<Object?>> tuples,
          [String boolean = SqlBool.and]) =>
      this.whereInTuple(columns, tuples, boolean, true);

  QueryBuilder orWhereNotInTuple(
          List<String> columns, Iterable<List<Object?>> tuples) =>
      this.whereInTuple(columns, tuples, SqlBool.or, true);

  static const _rowValueOperators = {'=', '<>', '!=', '<', '>', '<=', '>='};

  /// Row comparison `(col1, col2) <operator> (?, ?)` (Laravel's
  /// whereRowValues), e.g. keyset pagination on a composite key:
  /// `whereRowValues(['ano', 'numero'], '>', [2024, 150])`.
  QueryBuilder whereRowValues(
      List<String> columns, String operator, List<Object?> values,
      [String boolean = SqlBool.and]) {
    if (columns.isEmpty || columns.length != values.length) {
      throw ArgumentError(
          'whereRowValues needs as many values as columns (${columns.length}).');
    }
    if (!_rowValueOperators.contains(operator)) {
      throw ArgumentError.value(operator, 'operator',
          'Expected one of ${_rowValueOperators.join(' ')}.');
    }
    this.wheresProp.add({
      'type': 'RowValues',
      'columns': List<String>.of(columns),
      'operator': operator,
      'values': List<Object?>.of(values),
      'boolean': boolean,
    });
    this.addBinding(List<Object?>.of(values), 'where');
    return this;
  }

  QueryBuilder orWhereRowValues(
          List<String> columns, String operator, List<Object?> values) =>
      this.whereRowValues(columns, operator, values, SqlBool.or);

  // --------------------------------------------------------- whereAnyArray

  static final _sqlTypeName = RegExp(
      r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?( [A-Za-z_][A-Za-z0-9_]*)*(\(\d+(, ?\d+)?\))?$');

  /// `column = any(?)` with all [values] in ONE array parameter (PostgreSQL),
  /// instead of one parameter per value as in [whereIn]: the SQL text is the
  /// same for any number of values (one prepared statement) and there is no
  /// 65535-parameter limit. [elementType] adds a cast, `= any(?::int[])`, for
  /// columns whose type the driver cannot infer (e.g. `uuid`). An empty list
  /// matches nothing. Grammars without array parameters (MySQL) compile a
  /// plain `column in (?, ...)`.
  QueryBuilder whereAnyArray(String column, Iterable<Object?> values,
      {String? elementType, String boolean = SqlBool.and, bool not = false}) {
    final list = List<Object?>.of(values);
    if (!this.grammar.supportsArrayBindings) {
      return this.whereIn(column, list, boolean, not);
    }
    if (elementType != null && !_sqlTypeName.hasMatch(elementType.trim())) {
      throw ArgumentError.value(
          elementType, 'elementType', 'Not an SQL type name.');
    }
    this.wheresProp.add({
      'type': 'AnyArray',
      'column': column,
      'value': list,
      'elementType': elementType?.trim(),
      'not': not,
      'boolean': boolean,
    });
    if (list.isNotEmpty) this.addBinding([list], 'where');
    return this;
  }

  QueryBuilder orWhereAnyArray(String column, Iterable<Object?> values,
          {String? elementType}) =>
      this.whereAnyArray(column, values,
          elementType: elementType, boolean: SqlBool.or);

  /// `column <> all(?)` (PostgreSQL), the [whereAnyArray] form of
  /// `not in`; an empty list excludes nothing.
  QueryBuilder whereNotAnyArray(String column, Iterable<Object?> values,
          {String? elementType, String boolean = SqlBool.and}) =>
      this.whereAnyArray(column, values,
          elementType: elementType, boolean: boolean, not: true);

  QueryBuilder orWhereNotAnyArray(String column, Iterable<Object?> values,
          {String? elementType}) =>
      this.whereAnyArray(column, values,
          elementType: elementType, boolean: SqlBool.or, not: true);

  // ---------------------------------------------- between columns / value

  /// `column between first and second`, both bounds columns:
  /// `whereBetweenColumns('valor', ['minimo', 'maximo'])`.
  QueryBuilder whereBetweenColumns(String column, List<String> columns,
      [String boolean = SqlBool.and, bool not = false]) {
    _checkTwoColumns(columns);
    this.wheresProp.add({
      'type': 'BetweenColumns',
      'column': column,
      'values': List<String>.of(columns),
      'boolean': boolean,
      'not': not,
    });
    return this;
  }

  QueryBuilder orWhereBetweenColumns(String column, List<String> columns) =>
      this.whereBetweenColumns(column, columns, SqlBool.or);

  QueryBuilder whereNotBetweenColumns(String column, List<String> columns,
          [String boolean = SqlBool.and]) =>
      this.whereBetweenColumns(column, columns, boolean, true);

  QueryBuilder orWhereNotBetweenColumns(String column, List<String> columns) =>
      this.whereBetweenColumns(column, columns, SqlBool.or, true);

  /// `? between first and second`: a value inside the range of two columns,
  /// e.g. a date within a validity period:
  /// `whereValueBetween(hoje, ['data_inicio', 'data_fim'])`.
  QueryBuilder whereValueBetween(Object value, List<String> columns,
      [String boolean = SqlBool.and, bool not = false]) {
    _checkTwoColumns(columns);
    this.wheresProp.add({
      'type': 'ValueBetween',
      'value': value,
      'values': List<String>.of(columns),
      'boolean': boolean,
      'not': not,
    });
    this.addBinding([value], 'where');
    return this;
  }

  QueryBuilder orWhereValueBetween(Object value, List<String> columns) =>
      this.whereValueBetween(value, columns, SqlBool.or);

  QueryBuilder whereValueNotBetween(Object value, List<String> columns,
          [String boolean = SqlBool.and]) =>
      this.whereValueBetween(value, columns, boolean, true);

  QueryBuilder orWhereValueNotBetween(Object value, List<String> columns) =>
      this.whereValueBetween(value, columns, SqlBool.or, true);

  static void _checkTwoColumns(List<String> columns) {
    if (columns.length != 2) {
      throw ArgumentError.value(
          columns, 'columns', 'Expected two columns: [low, high].');
    }
  }

  /// Adds a raw SQL where condition, with [bindings] for its `?`
  /// placeholders.
  QueryBuilder whereRaw(String sql,
      [List bindings = const [], boolean = SqlBool.and]) {
    const type = SqlWhereType.raw;
    this.wheresProp.add({'type': type, 'sql': sql, 'boolean': boolean});
    this.addBinding(bindings, 'where');
    return this;
  }

  /// Adds a raw SQL `or` where condition; see [whereRaw].
  QueryBuilder orWhereRaw(String sql, [List bindings = const []]) {
    return this.whereRaw(sql, bindings, SqlBool.or);
  }

  /// Adds `column between ? and ?` (`not between` when [not]).
  ///
  /// [values] holds the two bounds, both included; anything other than two
  /// bounds throws [ArgumentError]. A [QueryExpression] bound is inlined.
  QueryBuilder whereBetween(String column,
      [List? values, String boolean = SqlBool.and, bool not = false]) {
    if (values == null || values.length != 2) {
      throw ArgumentError.value(
          values, 'values', 'Must hold exactly two bounds.');
    }
    const type = SqlWhereType.between;

    this.wheresProp.add({
      'column': column,
      'type': type,
      'values': values,
      'boolean': boolean,
      'not': not
    });

    this.addBinding(
        [...values.where((value) => value is! QueryExpression)], 'where');

    return this;
  }

  /// Adds `or column between ? and ?`; see [whereBetween].
  QueryBuilder orWhereBetween(String column, List values) {
    return this.whereBetween(column, values, SqlBool.or);
  }

  /// Adds `column not between ? and ?`; see [whereBetween].
  QueryBuilder whereNotBetween(String column, List values,
      [String boolean = SqlBool.and]) {
    return this.whereBetween(column, values, boolean, true);
  }

  /// Adds `or column not between ? and ?`; see [whereBetween].
  QueryBuilder orWhereNotBetween(String column, List values) {
    return this.whereNotBetween(column, values, SqlBool.or);
  }

  /// Adds a parenthesized group of conditions built by [callback].
  ///
  /// [callback] receives a new query on the same table (see
  /// [forNestedWhere]); a group left without conditions adds nothing.
  QueryBuilder whereNested(Function callback, [String boolean = SqlBool.and]) {
    var query = this.forNestedWhere();

    callback(query);

    return this.addNestedWhereQuery(query, boolean);
  }

  /// Returns a new query on the same table, for a nested where group.
  QueryBuilder forNestedWhere() {
    var query = this.newQuery();

    return query.from(this.fromProp);
  }

  /// Adds the where conditions of [query] as a parenthesized group, with
  /// its bindings; does nothing when [query] has no conditions.
  QueryBuilder addNestedWhereQuery(QueryBuilder query,
      [boolean = SqlBool.and]) {
    if (query.wheresProp.isNotEmpty) {
      const type = SqlWhereType.nested;

      this.wheresProp.add({'type': type, 'query': query, 'boolean': boolean});

      this.addBinding(query.getBindings(), 'where');
    }

    return this;
  }

  /// Adds `column operator (select ...)`, the subquery built by [callback]
  /// on a new query.
  QueryBuilder whereSub(
      String column, String? operator, Function callback, String boolean) {
    const type = SqlWhereType.sub;

    var query = this.newQuery();

    callback(query);

    this.wheresProp.add({
      'type': type,
      'column': column,
      'operator': operator,
      'query': query,
      'boolean': boolean
    });

    this.addBinding(query.getBindings(), 'where');

    return this;
  }

  /// Like [whereSub], but builds the subquery on [forSubQuery] and uses `=`
  /// when [operator] is null.
  QueryBuilder whereSubFlex(
      String column, String? operator, Function callback, String boolean) {
    const type = SqlWhereType.sub;
    final query = this.forSubQuery();
    callback(query);

    operator ??= SqlOperator.equals;

    this.wheresProp.add({
      'type': type,
      'column': column,
      'operator': operator,
      'query': query,
      'boolean': boolean
    });

    this.addBinding(query.getBindings(), 'where');
    return this;
  }

  /// Adds `exists (select ...)` (`not exists` when [not]), the subquery
  /// built by [callback] on a new query.
  ///
  /// The callback receives a [QueryBuilder], so it uses `from(...)` instead
  /// of `table(...)`:
  ///
  /// ```dart
  /// db.table('usuario as usuario')
  ///   .whereExists((q) {
  ///     q.selectRaw('1')
  ///      .from('administracao.usuario_organograma as uo_filtro')
  ///      .whereColumn('uo_filtro.numcgm', '=', 'usuario.numcgm')
  ///      .where('uo_filtro.id_organograma', '=', 10);
  ///   });
  /// ```
  QueryBuilder whereExists(Function callback,
      [String boolean = SqlBool.and, bool not = false]) {
    var type = not ? SqlWhereType.notExists : SqlWhereType.exists;

    var query = this.newQuery();

    callback(query);

    this.wheresProp.add(
        {'type': type, 'operator': null, 'query': query, 'boolean': boolean});

    this.addBinding(query.getBindings(), 'where');

    return this;
  }

  /// Adds `or exists (select ...)` (`or not exists` when [not]); see
  /// [whereExists].
  QueryBuilder orWhereExists(Function callback, [bool not = false]) {
    return this.whereExists(callback, SqlBool.or, not);
  }

  /// Adds `not exists (select ...)`; see [whereExists].
  QueryBuilder whereNotExists(Function callback,
      [String boolean = SqlBool.and]) {
    return this.whereExists(callback, boolean, true);
  }

  /// Adds `or not exists (select ...)`; see [whereExists].
  QueryBuilder orWhereNotExists(Function callback) {
    return this.orWhereExists(callback, true);
  }

  /// Adds `column in (?, ...)` (`not in` when [not]).
  ///
  /// [values] is a list or other iterable (one binding per element), a
  /// [QueryBuilder] or a `Function(QueryBuilder)` that builds a subquery:
  /// `column in (select ...)`. An empty list matches nothing (`0 = 1`); with
  /// [not] it excludes nothing (`1 = 1`).
  QueryBuilder whereIn(String column, dynamic values,
      [String boolean = SqlBool.and, bool not = false]) {
    var type = not ? SqlWhereType.notInList : SqlWhereType.inList;

    if (values is QueryBuilder) {
      return this.whereInExistingQuery(column, values, boolean, not);
    }

    if (values is Function) {
      return this.whereInSub(column, values, boolean, not);
    }

    // Sets and other iterables are bound like lists.
    if (values is Iterable && values is! List) {
      values = values.toList();
    }

    this.wheresProp.add(
        {'type': type, 'column': column, 'values': values, 'boolean': boolean});

    this.addBinding(values, 'where');

    return this;
  }

  /// Adds `or column in (...)`; see [whereIn].
  QueryBuilder orWhereIn(String column, dynamic values) {
    return this.whereIn(column, values, SqlBool.or);
  }

  /// Adds `column not in (...)`; see [whereIn].
  QueryBuilder whereNotIn(String column, values,
      [String boolean = SqlBool.and]) {
    return this.whereIn(column, values, boolean, true);
  }

  /// Adds `or column not in (...)`; see [whereIn].
  QueryBuilder orWhereNotIn(String column, values) {
    return this.whereNotIn(column, values, SqlBool.or);
  }

  /// Adds `column in (select ...)` (`not in` when [not]), the subquery
  /// built by [callback] on a new query.
  QueryBuilder whereInSub(
      String column, Function callback, String boolean, bool not) {
    final type = not ? SqlWhereType.notInSub : SqlWhereType.inSub;

    final query = this.newQuery();
    callback(query);

    this.wheresProp.add(
        {'type': type, 'column': column, 'query': query, 'boolean': boolean});

    this.addBinding(query.getBindings(), 'where');

    return this;
  }

  /// Adds `column in (select ...)` (`not in` when [not]) with an existing
  /// [query] as the subquery.
  QueryBuilder whereInExistingQuery(
      String column, QueryBuilder query, String boolean, bool not) {
    var type = not ? SqlWhereType.notInSub : SqlWhereType.inSub;

    this.wheresProp.add(
        {'type': type, 'column': column, 'query': query, 'boolean': boolean});

    this.addBinding(query.getBindings(), 'where');

    return this;
  }

  /// Adds `column is null` (`is not null` when [not]).
  QueryBuilder whereNull(String column,
      [String boolean = SqlBool.and, bool not = false]) {
    var type = not ? SqlWhereType.isNotNull : SqlWhereType.isNull;

    this.wheresProp.add({'type': type, 'column': column, 'boolean': boolean});

    return this;
  }

  /// Adds `or column is null`.
  QueryBuilder orWhereNull(String column) {
    return this.whereNull(column, SqlBool.or);
  }

  // --- PostgreSQL JSON / array / full-text helpers -------------------------

  /// Adds a JSON containment condition: `("column")::jsonb @> ?` on
  /// PostgreSQL, `json_contains(column, ?[, path])` on MySQL/MariaDB; other
  /// grammars throw [UnsupportedError].
  ///
  /// [value] is JSON-encoded and bound; a [QueryExpression] is inlined. Use
  /// for jsonb columns and arrays, e.g. `whereJsonContains('tags', ['urgent'])`
  /// or `whereJsonContains('meta->roles', 'admin')`. [not] negates it.
  QueryBuilder whereJsonContains(String column, dynamic value,
      [String boolean = SqlBool.and, bool not = false]) {
    this.wheresProp.add({
      'type': 'JsonContains',
      'column': column,
      'value': value,
      'boolean': boolean,
      'not': not,
    });
    if (value is! QueryExpression) {
      this.addBinding(json.encode(value), 'where');
    }
    return this;
  }

  QueryBuilder orWhereJsonContains(String column, dynamic value) =>
      this.whereJsonContains(column, value, SqlBool.or);

  QueryBuilder whereJsonDoesntContain(String column, dynamic value,
          [String boolean = SqlBool.and]) =>
      this.whereJsonContains(column, value, boolean, true);

  QueryBuilder orWhereJsonDoesntContain(String column, dynamic value) =>
      this.whereJsonContains(column, value, SqlBool.or, true);

  /// Adds a JSON array length comparison:
  /// `jsonb_array_length(("column")::jsonb) <operator> ?` (PostgreSQL).
  QueryBuilder whereJsonLength(String column, String operator, dynamic value,
      [String boolean = SqlBool.and]) {
    this.wheresProp.add({
      'type': 'JsonLength',
      'column': column,
      'operator': operator,
      'value': value,
      'boolean': boolean,
    });
    if (value is! QueryExpression) {
      this.addBinding(value, 'where');
    }
    return this;
  }

  QueryBuilder orWhereJsonLength(
          String column, String operator, dynamic value) =>
      this.whereJsonLength(column, operator, value, SqlBool.or);

  /// Adds a full-text search of [value] across [columns] (a column or a
  /// list of columns).
  ///
  /// On PostgreSQL it is `(to_tsvector(lang, col) || ...) @@ <tsquery>`;
  /// [options] may include `'language'` (default `'english'`) and `'mode'`
  /// (`'plain'`, `'phrase'` or `'websearch'`). MySQL compiles its own
  /// `match ... against` form.
  QueryBuilder whereFullText(dynamic columns, String value,
      [Map<String, dynamic> options = const {}, String boolean = SqlBool.and]) {
    final cols = columns is List
        ? columns.map((c) => c.toString()).toList()
        : <String>[columns.toString()];
    this.wheresProp.add({
      'type': 'Fulltext',
      'columns': cols,
      'value': value,
      'options': options,
      'boolean': boolean,
    });
    this.addBinding(value, 'where');
    return this;
  }

  QueryBuilder orWhereFullText(dynamic columns, String value,
          [Map<String, dynamic> options = const {}]) =>
      this.whereFullText(columns, value, options, SqlBool.or);

  /// PostgreSQL array containment: `"column" @> ?` — true when [column]
  /// contains every element of [value].
  QueryBuilder whereArrayContains(String column, List value,
          [String boolean = SqlBool.and]) =>
      _whereArrayOp(column, '@>', value, boolean);

  QueryBuilder orWhereArrayContains(String column, List value) =>
      _whereArrayOp(column, '@>', value, SqlBool.or);

  /// PostgreSQL array containment: `"column" <@ ?` — true when every element of
  /// [column] is present in [value].
  QueryBuilder whereArrayContainedBy(String column, List value,
          [String boolean = SqlBool.and]) =>
      _whereArrayOp(column, '<@', value, boolean);

  QueryBuilder orWhereArrayContainedBy(String column, List value) =>
      _whereArrayOp(column, '<@', value, SqlBool.or);

  /// PostgreSQL array overlap: `"column" && ?` — true when [column] and [value]
  /// share at least one element.
  QueryBuilder whereArrayOverlaps(String column, List value,
          [String boolean = SqlBool.and]) =>
      _whereArrayOp(column, '&&', value, boolean);

  QueryBuilder orWhereArrayOverlaps(String column, List value) =>
      _whereArrayOp(column, '&&', value, SqlBool.or);

  QueryBuilder _whereArrayOp(
      String column, String operator, List value, String boolean) {
    this.wheresProp.add({
      'type': 'ArrayOp',
      'column': column,
      'operator': operator,
      'value': value,
      'boolean': boolean,
    });
    // One binding for the whole list (addBinding would spread it).
    this.bindings['where']!.add(value);
    return this;
  }

  /// Adds `column is not null`.
  QueryBuilder whereNotNull(String column, [String boolean = SqlBool.and]) {
    return this.whereNull(column, boolean, true);
  }

  /// Adds `or column is not null`.
  QueryBuilder orWhereNotNull(String column) {
    return this.whereNotNull(column, SqlBool.or);
  }

  /// Compares the date part of [column] with [value]: `"column"::date op ?`
  /// on PostgreSQL, `date("column") op ?` on MySQL.
  QueryBuilder whereDate(String column, String? operator, DateTime? value,
      [String boolean = SqlBool.and]) {
    return this.addDateBasedWhere('Date', column, operator, value, boolean);
  }

  /// Adds an `or` comparison of the date part of [column]; see [whereDate].
  ///
  /// `orWhereDate('created_at', '=', someDate)`.
  QueryBuilder orWhereDate(String column, String operator, DateTime? value) {
    return this.whereDate(column, operator, value, SqlBool.or);
  }

  /// Compares the time part of [column] with [value] (e.g. `'12:00:00'`):
  /// `time("column") op ?` on MySQL, `"column"::time op ?` on PostgreSQL.
  QueryBuilder whereTime(String column, String operator, dynamic value,
      [String boolean = SqlBool.and]) {
    return this.addDateBasedWhere('Time', column, operator, value, boolean);
  }

  /// Adds an `or` comparison of the time part of [column]; see [whereTime].
  QueryBuilder orWhereTime(String column, String operator, dynamic value) {
    return this.whereTime(column, operator, value, SqlBool.or);
  }

  /// Compares the day of the month of [column] with [value]:
  /// `extract(day from "column") op ?` on PostgreSQL, `day("column") op ?`
  /// on MySQL.
  QueryBuilder whereDay(String column, String operator, int value,
      [String boolean = SqlBool.and]) {
    return this.addDateBasedWhere('Day', column, operator, value, boolean);
  }

  /// Compares the month (1-12) of [column] with [value]; see [whereDay].
  QueryBuilder whereMonth(String column, String operator, int value,
      [String boolean = SqlBool.and]) {
    return this.addDateBasedWhere('Month', column, operator, value, boolean);
  }

  /// Compares the year of [column] with [value]; see [whereDay].
  QueryBuilder whereYear(String column, String operator, int value,
      [String boolean = SqlBool.and]) {
    return this.addDateBasedWhere('Year', column, operator, value, boolean);
  }

  /// Adds a where clause of [type] `'Date'`, `'Time'`, `'Day'`, `'Month'` or
  /// `'Year'`, compiled by the grammar's method of the same name.
  QueryBuilder addDateBasedWhere(
      String type, String column, String? operator, dynamic value,
      [String boolean = SqlBool.and]) {
    this.wheresProp.add({
      'column': column,
      'type': type,
      'boolean': boolean,
      'operator': operator,
      'value': value
    });
    this.addBinding(value, 'where');
    return this;
  }

  /// Adds the where clauses named by a Laravel dynamic where [method], one
  /// `=` comparison per column with the [parameters] in order.
  ///
  /// [method] starts with `where`, followed by CamelCase column names joined
  /// by `And` or `Or`: `dynamicWhere('whereFirstNameAndLastName',
  /// ['John', 'Doe'])` adds
  ///
  /// ```dart
  /// where('first_name', '=', 'John', 'and')
  ///   .where('last_name', '=', 'Doe', 'and')
  /// ```
  QueryBuilder dynamicWhere(String method, List<dynamic> parameters) {
    final finder = method.substring(5);

    // Splits on "And"/"Or" followed by an uppercase letter, keeping them.
    final RegExp regExp = RegExp(r'(And|Or)(?=[A-Z])');
    final List<String> tokens = [];
    int start = 0;
    for (final match in regExp.allMatches(finder)) {
      tokens.add(finder.substring(start, match.start));
      tokens.add(match.group(0)!);
      start = match.end;
    }
    tokens.add(finder.substring(start));

    String connector = SqlBool.and;
    int index = 0;
    for (final token in tokens) {
      if (token != 'And' && token != 'Or') {
        addDynamic(token, connector, parameters, index);
        index++;
      } else {
        connector = token.toLowerCase();
      }
    }
    return this;
  }

  /// Adds `snake_case(segment) = parameters[index]` with [connector], for
  /// [dynamicWhere].
  void addDynamic(
      String segment, String connector, List<dynamic> parameters, int index) {
    final column = Utils.toSnakeCase(segment);
    where(column, SqlOperator.equals, parameters[index], connector);
  }

  /// Adds columns to the `group by` clause.
  ///
  /// [column] is a column name, a [QueryExpression] (`db.raw(...)`) or a list
  /// of them. Anything else throws [ArgumentError] (it used to be ignored
  /// silently).
  QueryBuilder groupBy(dynamic column) {
    if (column is List) {
      for (final item in column) {
        _checkGroup(item);
      }
      this.groupsProp = [...this.groupsProp, ...column];
    } else {
      _checkGroup(column);
      this.groupsProp = [...this.groupsProp, column];
    }

    return this;
  }

  static void _checkGroup(dynamic group) {
    if (group is! String && group is! QueryExpression) {
      throw ArgumentError.value(group, 'column',
          'Expected a column name or a QueryExpression (db.raw(...)).');
    }
  }

  /// Adds the raw SQL [sql] to the `group by` clause, with [bindingsP] for
  /// its `?` placeholders.
  ///
  /// ```dart
  /// db.table('t')
  ///     .selectRaw('date_trunc(?, created_at) as dia, count(*) as total',
  ///         ['day'])
  ///     .groupByRaw('date_trunc(?, created_at)', ['day']);
  /// ```
  QueryBuilder groupByRaw(String sql, [List bindingsP = const []]) {
    this.groupsProp = [...this.groupsProp, QueryExpression(sql)];
    this.addBinding(bindingsP, 'groupBy');
    return this;
  }

  /// Adds a having clause: `having column operator ?`.
  ///
  /// `having(column, value)` (two arguments) means `=`; a
  /// `Function(QueryBuilder)` column builds a nested group (see
  /// [havingNested]). A [QueryExpression] value is inlined instead of bound.
  QueryBuilder having(dynamic column,
      [dynamic operator,
      dynamic value = _absent,
      String boolean = SqlBool.and]) {
    if (column is Function) {
      return this.havingNested(column, boolean);
    }
    if (identical(value, _absent)) {
      value = operator;
      operator = SqlOperator.equals;
    }
    var type = 'basic';

    this.havingsProp.add({
      'type': type,
      'column': column,
      'operator': operator,
      'value': value,
      'boolean': boolean
    });

    if (!(value is QueryExpression)) {
      // One placeholder, one binding: a List value (Uint8List, a PostgreSQL
      // array, JSON) used to be spread into several bindings.
      this.addBinding([value], 'having');
    }

    return this;
  }

  /// Adds an `or` having clause; takes the same arguments as [having].
  QueryBuilder orHaving(dynamic column,
      [dynamic operator, dynamic value = _absent]) {
    return this.having(column, operator, value, SqlBool.or);
  }

  /// Adds a parenthesized group of having clauses built by [callback]; an
  /// empty group adds nothing.
  QueryBuilder havingNested(Function callback, [String boolean = SqlBool.and]) {
    final query = this.forNestedWhere();
    callback(query);
    if (query.havingsProp.isNotEmpty) {
      this
          .havingsProp
          .add({'type': 'Nested', 'query': query, 'boolean': boolean});
      this.addBinding(query.bindings['having'], 'having');
    }
    return this;
  }

  /// Adds `having column between ? and ?` (`not between` when [not]).
  ///
  /// Throws [ArgumentError] unless [values] has exactly two elements.
  QueryBuilder havingBetween(String column, List values,
      [String boolean = SqlBool.and, bool not = false]) {
    if (values.length != 2) {
      throw ArgumentError.value(values, 'values', 'Expected two values.');
    }
    this.havingsProp.add({
      'type': 'between',
      'column': column,
      'boolean': boolean,
      'not': not,
    });
    this.addBinding(this.cleanBindings(values), 'having');
    return this;
  }

  QueryBuilder orHavingBetween(String column, List values) =>
      this.havingBetween(column, values, SqlBool.or);

  QueryBuilder havingNotBetween(String column, List values,
          [String boolean = SqlBool.and]) =>
      this.havingBetween(column, values, boolean, true);

  QueryBuilder orHavingNotBetween(String column, List values) =>
      this.havingBetween(column, values, SqlBool.or, true);

  /// Adds `having column is null` (`is not null` when [not]) for each of
  /// [columns], a column or a list of them.
  QueryBuilder havingNull(dynamic columns,
      [String boolean = SqlBool.and, bool not = false]) {
    final list = columns is List ? columns : [columns];
    for (final column in list) {
      this.havingsProp.add({
        'type': not ? 'NotNull' : 'Null',
        'column': column,
        'boolean': boolean,
      });
    }
    return this;
  }

  QueryBuilder orHavingNull(dynamic columns) =>
      this.havingNull(columns, SqlBool.or);

  QueryBuilder havingNotNull(dynamic columns, [String boolean = SqlBool.and]) =>
      this.havingNull(columns, boolean, true);

  QueryBuilder orHavingNotNull(dynamic columns) =>
      this.havingNull(columns, SqlBool.or, true);

  /// Adds a raw SQL having condition, with [bindings] for its `?`
  /// placeholders.
  QueryBuilder havingRaw(String sql,
      [List bindings = const [], String boolean = SqlBool.and]) {
    const type = 'raw';

    this.havingsProp.add({
      'type': type,
      'sql': sql,
      'boolean': boolean,
    });

    this.addBinding(bindings, 'having');

    return this;
  }

  /// Adds a raw SQL `or` having condition; see [havingRaw].
  QueryBuilder orHavingRaw(String sql, [List bindings = const []]) {
    return this.havingRaw(sql, bindings, SqlBool.or);
  }

  /// Adds an `order by` clause.
  ///
  /// [column] is a column, a [QueryExpression] or a subquery (`QueryBuilder`
  /// or `Function(QueryBuilder)`). [direction] must be `asc` or `desc` in any
  /// case; anything else throws [ArgumentError] (it used to become `desc`
  /// silently). After a union the order applies to the whole union.
  QueryBuilder orderBy(dynamic column, [String direction = SqlSort.asc]) {
    final _direction = direction.trim().toLowerCase();
    if (_direction != SqlSort.asc && _direction != SqlSort.desc) {
      throw ArgumentError.value(
          direction, 'direction', 'Order direction must be "asc" or "desc".');
    }

    if (_isQueryable(column)) {
      final res = this.createSub(column);
      column = QueryExpression('(${res[0]})');
      // Union orders are compiled after the unions, at the end of the SQL.
      this.addBinding(
          res[1], this.unionsProp.isNotEmpty ? 'unionOrder' : 'order');
    }

    var map = {'column': column, 'direction': _direction};
    if (this.unionsProp.isNotEmpty) {
      this.unionOrdersProp.add(map);
    } else {
      this.ordersProp.add(map);
    }

    return this;
  }

  /// Orders by a column chosen by the client (a request parameter) without
  /// putting the client's text in the SQL: [field] is looked up in
  /// [allowed] (`{'nome': 'c.nom_cgm', 'data': 'p.timestamp'}`), whose values
  /// are columns, `db.raw(...)` expressions or lists of them (several
  /// columns, same direction).
  ///
  /// A null, blank or unknown [field] orders by [fallback] (a column, a raw
  /// expression or a list) in [fallbackDirection], or adds no order when
  /// there is no [fallback]. [direction] accepts `asc`/`desc` (any case, also
  /// `ascending`/`descending`); anything else is `asc`.
  ///
  /// ```dart
  /// query.orderByInput(filtros.orderBy, filtros.orderDir,
  ///     allowed: {'nome': 'c.nom_cgm', 'cpf': 'c.cpf'}, fallback: 'c.numcgm');
  /// ```
  QueryBuilder orderByInput(String? field, String? direction,
      {required Map<String, Object> allowed,
      Object? fallback,
      String fallbackDirection = SqlSort.asc}) {
    final key = field?.trim();
    final target = key == null || key.isEmpty ? null : allowed[key];
    if (target == null) {
      if (fallback == null) return this;
      return _orderByTargets(fallback, fallbackDirection, 'fallback');
    }
    return _orderByTargets(target, inputDirection(direction), 'allowed');
  }

  /// `asc` or `desc` from a client's direction: `desc`/`descending` in any
  /// case is `desc`, anything else (null included) is `asc`.
  static String inputDirection(String? direction) {
    switch (direction?.trim().toLowerCase()) {
      case 'desc':
      case 'descending':
        return SqlSort.desc;
      default:
        return SqlSort.asc;
    }
  }

  QueryBuilder _orderByTargets(Object target, String direction, String name) {
    final targets = target is List ? target : [target];
    if (targets.isEmpty) {
      throw ArgumentError.value(target, name, 'Must not be empty.');
    }
    for (final item in targets) {
      if (item is QueryExpression ||
          (item is String && item.trim().isNotEmpty)) {
        this.orderBy(item, direction);
      } else {
        throw ArgumentError.value(
            target, name, 'Expected a column, db.raw(...) or a list of them.');
      }
    }
    return this;
  }

  /// Adds `order by column desc`.
  QueryBuilder orderByDesc(dynamic column) {
    return this.orderBy(column, SqlSort.desc);
  }

  /// Removes every order (and its bindings) and optionally orders again by
  /// [column]; useful when reusing a query for a count or another page.
  QueryBuilder reorder([dynamic column, String direction = SqlSort.asc]) {
    this.ordersProp = [];
    this.unionOrdersProp = [];
    this.bindings['order'] = [];
    this.bindings['unionOrder'] = [];
    if (column != null) {
      return this.orderBy(column, direction);
    }
    return this;
  }

  /// Removes every order and orders by [column] descending; see [reorder].
  QueryBuilder reorderDesc(dynamic column) {
    return this.reorder(column, SqlSort.desc);
  }

  /// Orders by [column] descending, newest first.
  QueryBuilder latest([String column = 'created_at']) {
    return this.orderBy(column, SqlSort.desc);
  }

  /// Orders by [column] ascending, oldest first.
  QueryBuilder oldest([String column = 'created_at']) {
    return this.orderBy(column, SqlSort.asc);
  }

  /// Orders the results randomly: `order by RANDOM()`.
  ///
  /// On MySQL [seed] is inlined as `RAND(seed)`: it must be an int or the
  /// decimal text of one, anything else throws [ArgumentError]. Other
  /// grammars ignore it.
  QueryBuilder inRandomOrder([Object? seed = '']) {
    final randomExpression = this.grammar.compileRandom(seed);
    return this.orderByRaw(randomExpression);
  }

  /// Adds the raw SQL [sql] to the `order by` clause, with [bindings] for
  /// its `?` placeholders. After a union it orders the whole union.
  QueryBuilder orderByRaw(String sql, [bindings = const []]) {
    var type = 'raw';
    var map = {'type': type, 'sql': sql};
    if (this.unionsProp.isNotEmpty) {
      this.unionOrdersProp.add(map);
    } else {
      this.ordersProp.add(map);
    }

    // With unions the order is compiled after the union parts: its bindings
    // used to be emitted before theirs.
    this.addBinding(
        bindings, this.unionsProp.isNotEmpty ? 'unionOrder' : 'order');

    return this;
  }

  /// Sets the number of rows to skip; a negative [value] is 0.
  ///
  /// After a union it applies to the whole union.
  QueryBuilder offset(int value) {
    var v = value < 0 ? 0 : value;
    if (this.unionsProp.isNotEmpty) {
      this.unionOffset = v;
    } else {
      this.offsetProp = v;
    }

    return this;
  }

  /// Same as [offset].
  QueryBuilder skip(int value) {
    return this.offset(value);
  }

  /// Sets the maximum number of rows to return; a negative [value] is
  /// ignored.
  ///
  /// After a union it applies to the whole union.
  QueryBuilder limit(int value) {
    if (value >= 0) {
      if (this.unionsProp.isNotEmpty) {
        this.unionLimit = value;
      } else {
        this.limitProp = value;
      }
    }

    return this;
  }

  /// Same as [limit].
  QueryBuilder take(int value) {
    return this.limit(value);
  }

  /// Sets the limit and offset for the 1-based [page] of [perPage] rows.
  QueryBuilder forPage(int page, [int perPage = 15]) {
    return this.skip((page - 1) * perPage).take(perPage);
  }

  /// The page of [perPage] rows after [lastId] (ascending by [column]);
  /// `null` means the first page.
  ///
  /// Keyset pagination: adds `column > ?`, replaces any order by [column]
  /// with `order by column asc` and sets the limit.
  QueryBuilder forPageAfterId([
    int perPage = 15,
    dynamic lastId = 0,
    String column = 'id',
  ]) {
    this.ordersProp = this.ordersProp.where((order) {
      return order['column'] != column;
    }).toList();
    if (lastId != null) {
      this.where(column, SqlOperator.greater, lastId);
    }
    this.orderBy(column, SqlSort.asc);
    this.take(perPage);
    return this;
  }

  /// The page of [perPage] rows before [lastId] (descending by [column]);
  /// `null` means the first page.
  QueryBuilder forPageBeforeId([
    int perPage = 15,
    dynamic lastId = 0,
    String column = 'id',
  ]) {
    this.ordersProp =
        this.ordersProp.where((order) => order['column'] != column).toList();
    if (lastId != null) {
      this.where(column, SqlOperator.less, lastId);
    }
    this.orderBy(column, SqlSort.desc);
    this.take(perPage);
    return this;
  }

  /// Adds `union` (`union all` when [all]) with another query.
  ///
  /// [queryP] is a [QueryBuilder] or a `Function(QueryBuilder)` that builds
  /// one; anything else throws [ArgumentError]. Orders, limits and offsets
  /// set after a union apply to the whole union.
  QueryBuilder union(dynamic queryP, [bool all = false]) {
    final QueryBuilder query;
    if (queryP is QueryBuilder) {
      query = queryP;
    } else if (queryP is Function) {
      query = this.newQuery();
      queryP(query);
    } else {
      throw ArgumentError.value(queryP, 'query',
          'Expected a QueryBuilder or a Function(QueryBuilder).');
    }

    this.unionsProp.add({'query': query, 'all': all});

    this.addBinding(query.getBindings(), 'union');

    return this;
  }

  /// Adds `union all` with another query; see [union].
  QueryBuilder unionAll(dynamic query) {
    return this.union(query, true);
  }

  /// Locks the selected rows.
  ///
  /// [value] is `true` (`FOR UPDATE`), `false` (shared lock), a [QueryLock],
  /// or a raw SQL string used verbatim (for example `'for no key update'`).
  /// Any lock but `false` runs the select on the write connection.
  QueryBuilder lock([dynamic value = true]) {
    if (value is! bool && value is! String && value is! QueryLock) {
      throw ArgumentError.value(
          value, 'value', 'Expected a bool, a String or a QueryLock.');
    }
    this.lockProp = value;

    if (value != false) {
      this.useWritePdo();
    }

    return this;
  }

  /// Locks the selected rows for update (`FOR UPDATE`).
  ///
  /// [skipLocked] adds `SKIP LOCKED` (rows locked by another transaction are
  /// skipped instead of waited for, the usual job-queue pattern), [noWait]
  /// adds `NOWAIT` (fail instead of waiting), and [of] restricts the lock to
  /// the rows of the given tables/aliases (`FOR UPDATE OF ...`).
  ///
  /// ```dart
  /// final job = await db.table('jobs')
  ///     .where('status', '=', 'pending')
  ///     .orderBy('id')
  ///     .limit(1)
  ///     .lockForUpdate(skipLocked: true)
  ///     .first();
  /// // select * from "jobs" where "status" = ? order by "id" asc limit 1
  /// //   for update skip locked
  /// ```
  QueryBuilder lockForUpdate(
      {bool skipLocked = false, bool noWait = false, List<String>? of}) {
    if (!skipLocked && !noWait && (of == null || of.isEmpty)) {
      return this.lock(true);
    }
    return this.lock(QueryLock(
        skipLocked: skipLocked, noWait: noWait, of: of ?? const <String>[]));
  }

  /// Locks the selected rows with a shared lock: `for share` on PostgreSQL,
  /// `lock in share mode` on MySQL (`for share` with modifiers).
  ///
  /// Accepts the same modifiers as [lockForUpdate].
  QueryBuilder sharedLock(
      {bool skipLocked = false, bool noWait = false, List<String>? of}) {
    if (!skipLocked && !noWait && (of == null || of.isEmpty)) {
      return this.lock(false);
    }
    return this.lock(QueryLock(
        forUpdate: false,
        skipLocked: skipLocked,
        noWait: noWait,
        of: of ?? const <String>[]));
  }

  /// Adds `SKIP LOCKED` to the current lock.
  ///
  /// Without a lock it implies `FOR UPDATE`, so `skipLocked()` alone yields
  /// `for update skip locked`. Throws [StateError] on a raw lock clause.
  QueryBuilder skipLocked() {
    return this.lock(_currentQueryLock().copyWith(skipLocked: true));
  }

  /// Adds `NOWAIT` to the current lock.
  ///
  /// Without a lock it implies `FOR UPDATE`. Throws [StateError] on a raw
  /// lock clause.
  QueryBuilder noWait() {
    return this.lock(_currentQueryLock().copyWith(noWait: true));
  }

  QueryLock _currentQueryLock() {
    final current = this.lockProp;
    if (current is QueryLock) return current;
    if (current == false) return const QueryLock(forUpdate: false);
    if (current is String) {
      throw StateError(
          'Cannot add a lock modifier to the raw lock clause "$current".');
    }
    return const QueryLock();
  }

  /// Returns the select SQL of the query, with `?` placeholders.
  String toSql() {
    return this.grammar.compileSelect(this);
  }

  /// Returns the row with `id = id`, or null when there is none.
  ///
  /// Adds the condition to this builder and sets its limit to 1.
  Future<Map<String, dynamic>?> find(int id,
      [List<String> columns = const ['*']]) {
    return this.where('id', SqlOperator.equals, id).first(columns);
  }

  /// Returns the value of [column] in the first row, or `null` when there is
  /// no row.
  ///
  /// `'t.col'` and `'col as alias'` are accepted.
  Future<dynamic> value(String column) async {
    final row = await this.first([column]);
    if (row == null) return null;
    return _valueFromRow(row, column);
  }

  dynamic _valueFromRow(Map<String, dynamic> row, String column) {
    final key = stripTableForPluck(column) as String;
    if (row.containsKey(key)) return row[key];
    // Drivers may change the case of unquoted aliases.
    for (final entry in row.entries) {
      if (entry.key.toLowerCase() == key.toLowerCase()) return entry.value;
    }
    return row.length == 1 ? row.values.first : null;
  }

  /// Returns the only row of the query.
  ///
  /// Throws [RecordsNotFoundException] when there is none and
  /// [MultipleRecordsFoundException] when there is more than one.
  Future<Map<String, dynamic>> sole(
      [List<String> columns = const ['*']]) async {
    final rows = await this.clone().take(2).get(columns);
    if (rows.isEmpty) {
      throw RecordsNotFoundException();
    }
    if (rows.length > 1) {
      throw MultipleRecordsFoundException(rows.length);
    }
    return rows.first;
  }

  /// Returns the value of [column] in the only row of the query (see
  /// [sole]).
  Future<dynamic> soleValue(String column) async {
    return _valueFromRow(await this.sole([column]), column);
  }

  /// Returns the first row; throws [RecordsNotFoundException] when there is
  /// none.
  Future<Map<String, dynamic>> firstOrFail(
      [List<String> columns = const ['*']]) async {
    final row = await this.first(columns);
    if (row == null) {
      throw RecordsNotFoundException();
    }
    return row;
  }

  /// Returns the row with `id = id`, or the result of [callback] when there
  /// is none.
  Future<dynamic> findOr(dynamic id, FutureOr<dynamic> Function() callback,
      [List<String> columns = const ['*']]) async {
    final row = await this.where('id', SqlOperator.equals, id).first(columns);
    return row ?? await callback();
  }

  /// Returns the first row, or null when there is none.
  ///
  /// Sets the limit of this builder to 1. [timeoutInSeconds] is passed to
  /// [get].
  Future<Map<String, dynamic>?> first(
      [List<String> columns = const ['*'], int? timeoutInSeconds]) async {
    final results = await this.take(1).get(columns, timeoutInSeconds);
    return results.isNotEmpty ? results.first : null;
  }

  /// Runs the query as a select and returns the rows.
  ///
  /// [columnsP] is used only when no columns were selected on the builder.
  /// The [afterQuery] callbacks run on the rows (not for aggregates).
  Future<List<Map<String, dynamic>>> get(
      [List<String> columnsP = const ['*'], int? timeoutInSeconds]) async {
    // Only take over `columnsProp` (and restore it) when the caller passed
    // columns via this call, i.e. when no columns were set on the builder. When
    // columns are already set we leave them untouched — avoiding the previous
    // per-call `[...columnsProp]` clone/restore allocation.
    final hadColumns = this.columnsProp != null;
    if (!hadColumns) {
      this.columnsProp = columnsP;
    }

    List<Map<String, dynamic>> results;
    try {
      final resultRunSelect = await this.runSelect(timeoutInSeconds);
      results = this.processor.processSelect(this, resultRunSelect);
    } finally {
      // Restored even when the query fails, so the builder stays usable.
      if (!hadColumns) {
        this.columnsProp = null;
      }
    }
    if (this.afterQueryCallbacks.isNotEmpty && this.aggregateProp == null) {
      results = await _applyAfterQuery(results);
    }
    return results;
  }

  /// Rows of `EXPLAIN <this query>` ([analyze]: `EXPLAIN ANALYZE`, which
  /// runs the query; PostgreSQL and MySQL 8.0.18+).
  Future<List<Map<String, dynamic>>> explain({bool analyze = false}) {
    final sql = this.grammar.compileExplain(this.toSql(), analyze: analyze);
    return this
        .connection
        .select(sql, this.getBindings(), !this.useWritePdoProp);
  }

  /// Callbacks run on the rows of [get] (and so of [first], [paginate],
  /// [chunk]...), in order; not on aggregates such as [count].
  final List<AfterQueryCallback> afterQueryCallbacks = [];

  /// Runs [callback] on the rows after the query (Laravel's afterQuery): it
  /// may change the rows in place or return new ones (`null` keeps them).
  ///
  /// ```dart
  /// query.afterQuery((rows) {
  ///   for (final row in rows) row['nome'] = (row['nome'] as String).trim();
  ///   return null;
  /// });
  /// ```
  QueryBuilder afterQuery(AfterQueryCallback callback) {
    this.afterQueryCallbacks.add(callback);
    return this;
  }

  Future<List<Map<String, dynamic>>> _applyAfterQuery(
      List<Map<String, dynamic>> rows) async {
    var result = rows;
    for (final callback in this.afterQueryCallbacks) {
      result = await callback(result) ?? result;
    }
    return result;
  }

  /// Runs the compiled select on the connection (the read connection unless
  /// [useWritePdo] was called) and returns the raw rows.
  Future<List<Map<String, dynamic>>> runSelect([int? timeoutInSeconds]) async {
    final sqlStr = this.toSql();

    final bid = this.getBindings();

    final com = this.connection;

    final results =
        await com.select(sqlStr, bid, !this.useWritePdoProp, timeoutInSeconds);

    return results;
  }

  /// Streams the rows of the query one by one through a server-side cursor.
  ///
  /// Unlike [chunk]/[each] (which page with LIMIT/OFFSET and materialize each
  /// page), this keeps memory roughly constant for arbitrarily large result
  /// sets by consuming an incremental reader. Only supported on drivers that
  /// implement streaming (currently `dpgsql`); otherwise throws
  /// [UnsupportedError].
  ///
  /// ```dart
  /// await for (final row in db.table('big').where('ok', '=', true).cursor()) {
  ///   process(row);
  /// }
  /// ```
  Stream<Map<String, dynamic>> cursor([int? fetchSize]) async* {
    final original = this.columnsProp != null ? [...this.columnsProp!] : null;
    if (this.columnsProp == null) {
      this.columnsProp = ['*'];
    }
    try {
      final sqlStr = this.toSql();
      final bid = this.getBindings();
      yield* this.connection.cursor(
            sqlStr,
            bid,
            !this.useWritePdoProp,
            fetchSize,
          );
    } finally {
      this.columnsProp = original;
    }
  }

  /// Same as [cursor]: streams the rows without loading them all in memory.
  Stream<Map<String, dynamic>> lazy([int? fetchSize]) => this.cursor(fetchSize);

  /// Returns direct, driver-specific access (bulk COPY, pipelining,
  /// LISTEN/NOTIFY, raw connection), or `null` when the active driver has no
  /// such support.
  ///
  /// ```dart
  /// final drv = db.table('t').driver();
  /// if (drv != null && drv.supportsCopy) {
  ///   await drv.copyInRows('temp_location', ['id', 'city'], rows);
  /// }
  /// ```
  DriverAccess? driver() => this.connection.driver();

  /// Returns the 1-based [page] of [perPage] rows with the total count (two
  /// queries: a count and the page).
  ///
  /// A null [page] is page 1 ([PaginationUtils.resolveCurrentPage]). The
  /// page query runs on a clone, so this builder keeps no limit or offset;
  /// no page query runs when the count is 0.
  Future<LengthAwarePaginator> paginate({
    int perPage = 15,
    List<String> columns = const ['*'],
    String pageName = 'page',
    int? page,
  }) async {
    page ??= PaginationUtils.resolveCurrentPage(pageName);

    int total = await getCountForPagination(columns);

    // A clone keeps limit/offset of the page off this builder.
    List<Map<String, dynamic>> results =
        total > 0 ? await clone().forPage(page, perPage).get(columns) : [];

    return DefaultLengthAwarePaginator(results, total, perPage, page, {
      'path': PaginationUtils.resolveCurrentPath(),
      'pageName': pageName,
    });
  }

  /// Like [paginate], but in ONE query: the page rows carry
  /// `count(*) over ()`, the total of rows that match. Opt-in, because it is
  /// not always faster: the database still has to find every matching row to
  /// count them (the separate count query of [paginate] can use an index-only
  /// scan and skip the joins and the select list), and on large or complex
  /// queries one heavier query can take longer than two light ones. Measure
  /// before using it.
  ///
  /// An empty page past the first one falls back to the count query. Queries
  /// with `distinct`, `distinct on` or unions use [paginate] (a window count
  /// would count the rows before DISTINCT or per union part).
  Future<LengthAwarePaginator> paginateWithWindowCount({
    int perPage = 15,
    List<String> columns = const ['*'],
    String pageName = 'page',
    int? page,
  }) async {
    if (this.distinctProp ||
        this.distinctOnProp != null ||
        this.unionsProp.isNotEmpty) {
      return this.paginate(
          perPage: perPage, columns: columns, pageName: pageName, page: page);
    }
    page ??= PaginationUtils.resolveCurrentPage(pageName);

    final query = this.clone().forPage(page, perPage);
    query.columnsProp ??= List<dynamic>.of(columns);
    query.selectRaw('count(*) over () as $_windowTotalAlias');
    final rows = await query.get();

    final int total;
    if (rows.isEmpty) {
      total = page == 1 ? 0 : await this.getCountForPagination(columns);
    } else {
      total = _aggregateToInt(rows.first[_windowTotalAlias]);
    }
    final items = [
      for (final row in rows)
        Map<String, dynamic>.of(row)..remove(_windowTotalAlias)
    ];
    return DefaultLengthAwarePaginator(items, total, perPage, page, {
      'path': PaginationUtils.resolveCurrentPath(),
      'pageName': pageName,
    });
  }

  static const _windowTotalAlias = 'eloquent_window_total';

  /// Keyset ("cursor") pagination on the orders of the query (Laravel's
  /// cursorPaginate): no OFFSET, so page 1000 costs the same as page 1, and
  /// no count query. Pass the [CursorPage.nextCursor] or
  /// [CursorPage.previousCursor] of the previous page as [cursor].
  ///
  /// The query must be ordered by plain columns that together are unique
  /// (end with the primary key: `orderBy('nome').orderBy('id')`), selected in
  /// the result, and without null values. A cursor is opaque: its values are
  /// only bound as parameters. An invalid cursor throws [FormatException].
  Future<CursorPage> cursorPaginate(
      {int perPage = 15,
      String? cursor,
      List<String> columns = const ['*']}) async {
    if (perPage < 1) {
      throw ArgumentError.value(perPage, 'perPage', 'Must be >= 1.');
    }
    final orders = <(String, bool)>[];
    for (final order in this.ordersProp) {
      final column = order['column'];
      if (order['sql'] != null || column is! String) {
        throw ArgumentError(
            'cursorPaginate needs orders by plain columns, not raw SQL.');
      }
      orders.add((column, order['direction'] == SqlSort.desc));
    }
    if (orders.isEmpty) {
      throw ArgumentError('cursorPaginate needs an orderBy on unique columns.');
    }
    if (this.unionsProp.isNotEmpty) {
      throw UnsupportedError('cursorPaginate does not support unions.');
    }

    final position =
        cursor == null || cursor.isEmpty ? null : PageCursor.decode(cursor);
    final previous = position != null && !position.pointsToNextItems;
    final query = this.clone();
    if (previous) {
      query.ordersProp = [
        for (final order in query.ordersProp)
          {
            ...order,
            'direction':
                order['direction'] == SqlSort.desc ? SqlSort.asc : SqlSort.desc,
          }
      ];
    }
    if (position != null) {
      final values = [
        for (final (column, _) in orders) position.valueOf(column)
      ];
      if (values.contains(null)) {
        throw const FormatException(
            'cursorPaginate does not support null order values.');
      }
      query.whereNested((QueryBuilder group) =>
          _cursorConditions(group, orders, values, 0, previous));
    }
    query.limit(perPage + 1);

    var rows = await query.get(columns);
    final more = rows.length > perPage;
    if (more) rows = rows.sublist(0, perPage);
    if (previous) rows = rows.reversed.toList();

    String? edge(Map<String, dynamic> row, bool next) => PageCursor({
          for (final (column, _) in orders) column: _cursorValue(row, column)
        }, pointsToNextItems: next)
            .encode();

    String? nextCursor;
    String? previousCursor;
    if (rows.isNotEmpty) {
      if (position == null) {
        if (more) nextCursor = edge(rows.last, true);
      } else if (position.pointsToNextItems) {
        previousCursor = edge(rows.first, false);
        if (more) nextCursor = edge(rows.last, true);
      } else {
        nextCursor = edge(rows.last, true);
        if (more) previousCursor = edge(rows.first, false);
      }
    }
    return CursorPage(
        items: rows,
        perPage: perPage,
        nextCursor: nextCursor,
        previousCursor: previousCursor);
  }

  /// `c0 > v0 or (c0 = v0 and (c1 > v1 or (c1 = v1 and ...)))`, with `<` for
  /// descending columns (inverted when reading the previous page).
  static void _cursorConditions(QueryBuilder query, List<(String, bool)> orders,
      List<Object?> values, int index, bool previous) {
    final (column, descending) = orders[index];
    final operator = descending != previous ? '<' : '>';
    query.where(column, operator, values[index]);
    if (index + 1 < orders.length) {
      query.orWhere((QueryBuilder next) {
        next.where(column, SqlOperator.equals, values[index]);
        next.whereNested((QueryBuilder rest) =>
            _cursorConditions(rest, orders, values, index + 1, previous));
      });
    }
  }

  Object? _cursorValue(Map<String, dynamic> row, String column) {
    final key = stripTableForPluck(column) as String;
    if (!row.containsKey(key)) {
      throw StateError('cursorPaginate: the rows have no "$key" column; '
          'select the order columns.');
    }
    final value = row[key];
    if (value == null) {
      throw StateError(
          'cursorPaginate does not support null values in the order column '
          '"$column".');
    }
    return value;
  }

  /// Returns the 1-based [page] of [perPage] rows with only next/previous
  /// information: no count query, so it is cheaper on large tables.
  ///
  /// Reads `perPage + 1` rows to know whether there is a next page. A null
  /// [page] is page 1 ([PaginationUtils.resolveCurrentPage]).
  Future<DefaultPaginator> simplePaginate({
    int perPage = 15,
    List<String> columns = const ['*'],
    String pageName = 'page',
    int? page,
  }) async {
    page ??= PaginationUtils.resolveCurrentPage(pageName);

    // One row more than the page tells whether there is a next page.
    final results = await this
        .clone()
        .skip((page - 1) * perPage)
        .take(perPage + 1)
        .get(columns);

    bool hasMorePages = results.length > perPage;

    List<Map<String, dynamic>> pageItems = results;
    if (hasMorePages) {
      pageItems = results.sublist(0, perPage);
    }

    return DefaultPaginator(
      pageItems,
      perPage,
      page,
      hasMorePages,
      {
        'path': PaginationUtils.resolveCurrentPath(),
        'pageName': pageName,
      },
    );
  }

  /// Returns the number of rows the query matches, ignoring its orders,
  /// limit and offset, for [paginate].
  ///
  /// Grouped, distinct and union queries are counted through a subquery.
  Future<int> getCountForPagination(
      [List<String> columns = const ['*']]) async {
    // Grouped/distinct/union queries: count their rows in the database
    // instead of fetching every aggregated row.
    if (_needsCountSubquery(clearSelectAliases(columns))) {
      return _countUsingSubquery(forPagination: true);
    }

    backupFieldsForCount();

    aggregateProp = {
      'function': 'count',
      'columns': clearSelectAliases(columns)
    };

    // The fields are restored even when the count fails, so the builder can
    // still be used.
    final List<Map<String, dynamic>> results;
    try {
      results = await get();
    } finally {
      aggregateProp = null;
      restoreFieldsForCount();
    }

    if (results.isNotEmpty && results.first.containsKey('aggregate')) {
      return _aggregateToInt(results.first['aggregate']);
    }

    return 0;
  }

  /// Saves and clears the orders, limit, offset, columns and their
  /// bindings, which a count query must not have; see
  /// [restoreFieldsForCount].
  void backupFieldsForCount() {
    backups['orders'] = ordersProp;
    backups['limit'] = limitProp;
    backups['offset'] = offsetProp;
    backups['columns'] = columnsProp;

    ordersProp = [];
    limitProp = null;
    offsetProp = null;
    columnsProp = null;

    bindingBackups['order'] = bindings['order']!;
    bindingBackups['select'] = bindings['select']!;

    bindings['order'] = [];
    bindings['select'] = [];
  }

  /// Returns [columns] without their aliases, which break count queries:
  /// `'users.name as user_name'` becomes `'users.name'`.
  List<String> clearSelectAliases(List<String> columns) {
    return columns.map((column) {
      final aliasPos = column.toLowerCase().indexOf(' as ');
      return aliasPos != -1 ? column.substring(0, aliasPos) : column;
    }).toList();
  }

  /// Restores the fields saved by [backupFieldsForCount].
  void restoreFieldsForCount() {
    ordersProp = backups['orders'] as List<Map<String, dynamic>>;
    limitProp = backups['limit'] as int?;
    offsetProp = backups['offset'] as int?;
    columnsProp = backups['columns'] as List?;

    bindings['order'] = bindingBackups['order']!;
    bindings['select'] = bindingBackups['select']!;

    backups.clear();
    bindingBackups.clear();
  }

  /// Runs the query in pages of [count] rows (limit/offset) and calls
  /// [callback] with each page and its 1-based number.
  ///
  /// Returns false when [callback] returns false (which stops it), true
  /// after the last page. The pages are read with [forPage] on this builder,
  /// which keeps the last limit and offset. Rows changed between pages can
  /// be skipped or repeated; see [chunkById].
  Future<bool> chunk(
    int count,
    FutureOr<bool> Function(List<Map<String, dynamic>> chunk, int page)
        callback,
  ) async {
    int page = 1;

    while (true) {
      final results = await this.forPage(page, count).get();
      final countResults = results.length;

      if (countResults == 0) {
        break;
      }

      final cbResult = await callback(results, page);
      if (cbResult == false) {
        return false;
      }

      page++;

      // A short page is the last one.
      if (countResults < count) {
        break;
      }
    }

    return true;
  }

  /// Runs the query in pages of [count] rows by keyset on [column]
  /// (`column > last id`, ascending) and calls [callback] with each page.
  ///
  /// Unlike [chunk], rows inserted or updated between pages are neither
  /// skipped nor repeated. [alias] is the key of [column] in the rows when
  /// it is selected under another name (`'users.id as user_id'`). Returns
  /// false when [callback] returns false (which stops it), true after the
  /// last page. Throws [StateError] when the rows lack the id column.
  ///
  /// ```dart
  /// await query.chunkById(100, (chunk) async { ... }, column: 'id');
  /// ```
  Future<bool> chunkById(
    int count,
    FutureOr<bool> Function(List<Map<String, dynamic>> chunk) callback, {
    String column = 'id',
    String? alias,
  }) async {
    return _chunkById(count, callback, column, alias, descending: false);
  }

  /// Same as [chunkById], in descending order of [column].
  Future<bool> chunkByIdDesc(
    int count,
    FutureOr<bool> Function(List<Map<String, dynamic>> chunk) callback, {
    String column = 'id',
    String? alias,
  }) {
    return _chunkById(count, callback, column, alias, descending: true);
  }

  // Each page is a clone filtered by the last id (it used to stack
  // `id > ...` conditions and a limit on this builder at every page, and to
  // start from `id > 0`, skipping ids <= 0 and failing for non-numeric keys).
  Future<bool> _chunkById(
    int count,
    FutureOr<bool> Function(List<Map<String, dynamic>> chunk) callback,
    String column,
    String? alias, {
    required bool descending,
  }) async {
    if (count < 1) {
      throw ArgumentError.value(count, 'count', 'Must be at least 1.');
    }
    final key = stripTableForPluck(alias ?? column) as String;
    dynamic lastId;

    while (true) {
      final page = this.clone();
      if (descending) {
        page.forPageBeforeId(count, lastId, column);
      } else {
        page.forPageAfterId(count, lastId, column);
      }
      final results = await page.get();
      if (results.isEmpty) {
        break;
      }

      final cbResult = await callback(results);
      if (cbResult == false) {
        return false;
      }

      lastId = results.last[key];
      if (lastId == null) {
        throw StateError('chunkById stopped: the column "$key" is not in the '
            'query results (select it or pass alias).');
      }

      if (results.length < count) {
        break;
      }
    }

    return true;
  }

  /// Calls [callback] for every row with its 0-based index, reading [count]
  /// rows at a time by id (see [chunkById]).
  ///
  /// Returning `false` from [callback] stops the iteration.
  Future<bool> eachById(
    FutureOr<bool> Function(Map<String, dynamic> row, int index) callback, {
    int count = 1000,
    String column = 'id',
    String? alias,
  }) async {
    var index = 0;
    return this.chunkById(count, (rows) async {
      for (final row in rows) {
        if (await callback(row, index++) == false) {
          return false;
        }
      }
      return true;
    }, column: column, alias: alias);
  }

  /// Streams every row, reading [chunkSize] rows at a time by [column]
  /// (keyset pagination, see [chunkById]).
  ///
  /// Works on every driver; memory stays bounded.
  Stream<Map<String, dynamic>> lazyById(
      [int chunkSize = 1000, String column = 'id', String? alias]) {
    return _lazyById(chunkSize, column, alias, descending: false);
  }

  /// Same as [lazyById], in descending order of [column].
  Stream<Map<String, dynamic>> lazyByIdDesc(
      [int chunkSize = 1000, String column = 'id', String? alias]) {
    return _lazyById(chunkSize, column, alias, descending: true);
  }

  Stream<Map<String, dynamic>> _lazyById(
    int chunkSize,
    String column,
    String? alias, {
    required bool descending,
  }) async* {
    if (chunkSize < 1) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'Must be at least 1.');
    }
    final key = stripTableForPluck(alias ?? column) as String;
    dynamic lastId;
    while (true) {
      final page = this.clone();
      if (descending) {
        page.forPageBeforeId(chunkSize, lastId, column);
      } else {
        page.forPageAfterId(chunkSize, lastId, column);
      }
      final rows = await page.get();
      for (final row in rows) {
        yield row;
      }
      if (rows.length < chunkSize) {
        return;
      }
      lastId = rows.last[key];
      if (lastId == null) {
        throw StateError('lazyById stopped: the column "$key" is not in the '
            'query results (select it or pass alias).');
      }
    }
  }

  /// Returns every row mapped by [callback], reading [count] rows at a time
  /// with [chunk].
  Future<List<T>> chunkMap<T>(T Function(Map<String, dynamic> row) callback,
      [int count = 1000]) async {
    final result = <T>[];
    await this.chunk(count, (rows, page) {
      for (final row in rows) {
        result.add(callback(row));
      }
      return true;
    });
    return result;
  }

  /// Calls [callback] for every row with its 0-based index, reading [count]
  /// rows at a time with [chunk].
  ///
  /// Returns false when [callback] returns false (which stops it), true
  /// after the last row. Order the query so the pages are stable (Laravel
  /// requires an `orderBy`).
  Future<bool> each(
    FutureOr<bool> Function(Map<String, dynamic> row, int index) callback, [
    int count = 1000,
  ]) async {
    int globalIndex = 0;
    return await this.chunk(count, (chunkRows, page) async {
      for (int i = 0; i < chunkRows.length; i++) {
        final row = chunkRows[i];
        final cbResult = await callback(row, globalIndex);
        if (cbResult == false) {
          return false;
        }
        globalIndex++;
      }
      return true;
    });
  }

  /// Returns the values of [column]: a list, or a map keyed by the values
  /// of [key] when it is given.
  ///
  /// `'t.col'` and `'col as alias'` are accepted.
  Future<dynamic> pluck(String column, [String? key]) async {
    var results = await this.get(key == null ? [column] : [column, key]);

    // The rows are keyed by the bare column (or alias), without the table.
    return Arr.pluck(
        results, this.stripTableForPluck(column), this.stripTableForPluck(key));
  }

  /// Returns the key of [column] in a result row: the part after the last
  /// dot or space (`'t.col'` is `'col'`, `'col as c'` is `'c'`); null stays
  /// null.
  dynamic stripTableForPluck(column) {
    return column == null ? column : column.split(RegExp(r'\.| ')).last;
  }

  /// Returns the values of [column] joined with [glue]; nulls become empty
  /// strings.
  Future<String> implode(String column, [String glue = '']) async {
    final dynamic result = await this.pluck(column);
    if (result is List) {
      return result.map((item) => item?.toString() ?? '').join(glue);
    }
    return '';
  }

  /// Whether the query returns any row: `select exists(<query>) as "exists"`.
  Future<bool> exists() async {
    final sql = this.grammar.compileExists(this);

    // The third argument is `useReadPdo`, as in runSelect.
    final results =
        await this.connection.select(sql, getBindings(), !useWritePdoProp);

    if (results.isNotEmpty && results.first.containsKey('exists')) {
      // PostgreSQL returns a bool; MySQL/MariaDB return 1/0.
      final value = results.first['exists'];
      return value == true || value == 1 || value == '1' || value == 't';
    }

    return false;
  }

  /// Whether the query returns no row.
  Future<bool> doesntExist() async => !(await this.exists());

  /// Returns `true` when a row exists, otherwise the result of [callback].
  Future<dynamic> existsOr(FutureOr<dynamic> Function() callback) async =>
      await this.exists() ? true : await callback();

  /// Returns `true` when no row exists, otherwise the result of [callback].
  Future<dynamic> doesntExistOr(FutureOr<dynamic> Function() callback) async =>
      await this.doesntExist() ? true : await callback();

  /// Returns the number of rows the query returns ([CountMode.rows], the
  /// default).
  ///
  /// With `groupBy`, `having`, `union` or `distinct` (over the selected
  /// columns) it counts the rows of the whole query through a subquery,
  /// instead of the first group's count. Pass [CountMode.laravel] for
  /// Laravel's semantics.
  ///
  /// ```dart
  /// await db.table('t').groupBy('status').count(); // groups
  /// await db.table('t').groupBy('status')
  ///     .count('*', CountMode.laravel); // rows of the 1st group
  /// ```
  Future<int> count(
      [dynamic columns = '*', CountMode mode = CountMode.rows]) async {
    final columnList = columns is List
        ? columns.map((column) => column.toString()).toList()
        : <String>[columns.toString()];

    final useSubquery = mode == CountMode.rows
        ? _needsCountSubquery(columnList)
        // Laravel compiles having/union aggregates over a subquery
        // (Grammar::compileUnionAggregate) and nothing else.
        : havingsProp.isNotEmpty || unionsProp.isNotEmpty;
    if (useSubquery) {
      return _countUsingSubquery(forPagination: false);
    }

    final result = await this.aggregate('count', columnList);
    return _aggregateToInt(result);
  }

  /// Whether a plain `count(...)` would not count the rows of this query.
  bool _needsCountSubquery(List<String> columns) {
    final allColumns =
        columns.isEmpty || (columns.length == 1 && columns.first == '*');
    return groupsProp.isNotEmpty ||
        havingsProp.isNotEmpty ||
        unionsProp.isNotEmpty ||
        distinctOnProp != null ||
        (distinctProp && allColumns);
  }

  /// `select count(*) as aggregate from (<this query>) as "aggregate_table"`.
  /// For pagination, orders/limit/offset are removed from the inner query; for
  /// [count] they are kept when limit/offset are set (they change the result).
  Future<int> _countUsingSubquery({required bool forPagination}) async {
    final inner = this.clone()
      ..aggregateProp = null
      ..lockProp = null;
    final keepWindow = !forPagination &&
        (inner.limitProp != null ||
            inner.offsetProp != null ||
            inner.unionLimit != null ||
            inner.unionOffset != null);
    if (!keepWindow) {
      inner.ordersProp = [];
      inner.bindings['order'] = [];
      inner.limitProp = null;
      inner.offsetProp = null;
      // The window of a union too (its limit used to stay in the count).
      inner.unionOrdersProp = [];
      inner.bindings['unionOrder'] = [];
      inner.unionLimit = null;
      inner.unionOffset = null;
    }
    // `select *` is invalid with GROUP BY on PostgreSQL; a constant yields
    // one row per group without repeating (raw, bound) group expressions.
    if (inner.columnsProp == null &&
        inner.groupsProp.isNotEmpty &&
        !inner.distinctProp) {
      inner.columnsProp = [QueryExpression('1')];
    }

    final outer = this.newQuery()
      ..useWritePdoProp = this.useWritePdoProp
      ..fromRaw('(${inner.toSql()}) as ${grammar.wrap('aggregate_table')}',
          inner.getBindings());
    final result = await outer.aggregate('count', const ['*']);
    return _aggregateToInt(result);
  }

  static int _aggregateToInt(dynamic result) {
    if (result is int) return result;
    if (result is num) return result.toInt();
    if (result is BigInt) return result.toInt();
    if (result is String) return int.tryParse(result) ?? 0;
    return 0;
  }

  /// Returns the smallest value of [column], or null when there are no
  /// rows.
  ///
  /// The value is the driver's: a `DateTime` for a date column, a `String`
  /// for a text column (and for a PostgreSQL `numeric`). When [T] is a
  /// numeric type (`num`, `int`, `double`), given or inferred as in
  /// `final num? m = await q.min('price')`, a text value is parsed (null if
  /// it is not a number) and the number converted to [T].
  Future<T?> min<T>(String column) async {
    return _minMaxResult<T>(await this.aggregate("min", [column]));
  }

  /// Returns the largest value of [column], or null when there are no rows;
  /// the value is typed as in [min].
  Future<T?> max<T>(String column) async {
    return _minMaxResult<T>(await this.aggregate("max", [column]));
  }

  static T? _minMaxResult<T>(dynamic result) {
    if (result == null) return null;
    // `<T>[] is List<num?>` holds for num, int and double (nullable or not),
    // not for dynamic or Object.
    if (<T>[] is List<num?>) {
      // A value that is neither a number nor text (a DateTime) throws.
      num? number = result is String ? num.tryParse(result) : result as num;
      if (number == null) return null;
      if (<T>[] is List<int?>) number = number.toInt();
      if (<T>[] is List<double?>) number = number.toDouble();
      return number as T;
    }
    return result as T;
  }

  /// Returns the sum of [column], or null when there are no rows (SQL
  /// `sum` of no rows is null).
  Future<num?> sum(String column) async {
    final result = await this.aggregate('sum', [column]);
    return result is String ? num.tryParse(result) : result as num?;
  }

  /// Returns the average of [column], or null when there are no rows.
  Future<num?> avg(String column) async {
    final result = await this.aggregate('avg', [column]);
    return result is String ? num.tryParse(result) : result as num?;
  }

  /// Same as [avg].
  Future<num?> average(String column) async {
    return await this.avg(column);
  }

  /// Runs `select function(columns) as aggregate` on the query and returns
  /// the value as the driver gives it, or null when there is no row.
  ///
  /// The select list and its bindings are restored afterwards, even when
  /// the query fails.
  Future<dynamic> aggregate(String function,
      [List<String> columnsP = const <String>['*']]) async {
    this.aggregateProp = {'function': function, 'columns': columnsP};

    List<dynamic>? cols =
        this.columnsProp != null ? [...this.columnsProp!] : null;
    var previousColumns = cols;

    // An aggregate query has no select list: its bindings are set aside and
    // restored afterwards.
    // ignore: unused_local_variable
    var previousSelectBindings = [...this.bindings['select']!];

    this.bindings['select'] = [];

    final List<Map<String, dynamic>> results;
    try {
      results = await this.get(columnsP);
    } finally {
      // Reset even when the query fails, so the builder stays usable.
      this.aggregateProp = null;
      this.columnsProp = previousColumns;
      this.bindings['select'] = previousSelectBindings;
    }

    if (results.isNotEmpty) {
      var result = Utils.mapChangeKeyCaseSd(results[0]);
      return result['aggregate'];
    }
    return null;
  }

  /// Runs the aggregate [function] (`count`, `sum`, `avg`, `min` or `max`)
  /// and returns it as an int or a double.
  ///
  /// Null is 0; a value the driver returns as text (e.g. a `numeric`) is
  /// parsed, and an unparsable one is 0.
  Future<num> numericAggregate(String function,
      [List<String> columns = const ['*']]) async {
    final dynamic result = await this.aggregate(function, columns);
    if (result == null) {
      return 0;
    }
    if (result is int || result is double) {
      return result as num;
    }
    final String resultStr = result.toString();
    if (!resultStr.contains('.')) {
      return int.tryParse(resultStr) ?? 0;
    }
    return double.tryParse(resultStr) ?? 0.0;
  }

  /// Inserts one row and returns the driver's [PDOResults].
  ///
  /// A pending [onConflict] clause and a [returning] list are compiled into
  /// the insert; with [returning], the results hold the returned rows.
  /// [QueryExpression] values are inlined. [timeout] is rounded up to whole
  /// seconds.
  Future<dynamic> insert(Map<String, dynamic> values, [Duration? timeout]) {
    final conflict = this.onConflictProp;
    final returning = this.returningProp;

    if (conflict == null && returning == null) {
      final bindings =
          this.cleanBindings(values.values.toList(growable: false));
      final sql = this.grammar.compileInsert(this, values);
      return this.connection.insert(sql, bindings, _timeoutSeconds(timeout));
    }

    // Low-level path: honor a pending ON CONFLICT and/or RETURNING clause.
    final bindings = <dynamic>[...values.values];
    if (conflict?.updateValues != null) {
      // DO UPDATE SET values are appended after the INSERT values because the
      // conflict clause is emitted after VALUES in the generated SQL.
      bindings.addAll(conflict!.updateValues!.values);
    }
    final sql = this.grammar.compileInsertWithClauses(
          this,
          values,
          conflict,
          returning,
        );
    return this
        .connection
        .insert(sql, this.cleanBindings(bindings), _timeoutSeconds(timeout));
  }

  /// Sets an `ON CONFLICT` target for the next [insert].
  ///
  /// Give the conflict [columns] (`onConflict(['ano'])`) or a named
  /// [constraint] (`onConflict([], 'uq_name')`), then chain [doUpdate] or
  /// [doNothing] for the action. An atomic counter needs no explicit lock:
  ///
  /// ```dart
  /// final rows = await db.table('processos_sequences')
  ///   .onConflict(['ano'])
  ///   .doUpdate({'last_id': db.raw('processos_sequences.last_id + 1')})
  ///   .returning(['last_id'])
  ///   .insert({'ano': 2026, 'last_id': 1});
  /// final seq = rows.first['last_id'];
  /// ```
  QueryBuilder onConflict(
      [List<String> columns = const [], String? constraint]) {
    this.onConflictProp = OnConflictClause(
      columns: columns,
      constraint: constraint,
    );
    return this;
  }

  /// Makes the pending [onConflict] `DO UPDATE SET ...`.
  ///
  /// [values] may contain [QueryExpression]s via `db.raw(...)` so expressions
  /// such as `last_id = table.last_id + 1` are supported. [whereRaw] appends a
  /// raw `WHERE` predicate to the conflict update.
  QueryBuilder doUpdate(Map<String, dynamic> values, [String? whereRaw]) {
    final current = this.onConflictProp ?? const OnConflictClause();
    this.onConflictProp = current.copyWith(
      doNothing: false,
      updateValues: values,
      updateWhereRaw: whereRaw,
    );
    return this;
  }

  /// Makes the pending [onConflict] `DO NOTHING`.
  QueryBuilder doNothing() {
    final current = this.onConflictProp ?? const OnConflictClause();
    this.onConflictProp = current.copyWith(doNothing: true);
    return this;
  }

  /// Adds a `RETURNING columns` clause to the next [insert]; an empty
  /// [columns] means `*`.
  ///
  /// The insert's [PDOResults] then hold the inserted rows, as PL/pgSQL's
  /// `RETURNING ... INTO`. [update], [delete] and [upsert] do not use it.
  QueryBuilder returning([List<dynamic> columns = const ['*']]) {
    this.returningProp = columns.isEmpty ? ['*'] : columns;
    return this;
  }

  /// Inserts a row or a list of rows, skipping those that violate a unique
  /// or primary key, and returns the number of rows inserted.
  ///
  /// PostgreSQL/SQLite: `INSERT ... ON CONFLICT DO NOTHING`.
  /// MySQL: `INSERT IGNORE`.
  Future<int> insertOrIgnore(dynamic values) async {
    final rows = _normalizeMultiInsert(values);
    if (rows.isEmpty) return 0;
    final bindings = <dynamic>[];
    for (final row in rows) {
      bindings.addAll(row.values);
    }
    final sql = this.grammar.compileInsertOrIgnore(this, rows);
    return await this.connection.affectingStatement(
          sql,
          this.cleanBindings(bindings),
        );
  }

  /// Inserts rows or updates the ones that already exist, atomically, and
  /// returns the affected-row count reported by the driver.
  ///
  /// [values] is a single map or a list of maps (all with the same keys).
  /// [uniqueBy] are the conflict-target columns. [update] are the columns to
  /// update on conflict; when omitted, every non-[uniqueBy] column is
  /// updated with the value that would have been inserted. Values in
  /// [update] may be [QueryExpression]s.
  ///
  /// PostgreSQL: `INSERT ... ON CONFLICT (uniqueBy) DO UPDATE SET ...`.
  /// MySQL: `INSERT ... ON DUPLICATE KEY UPDATE ...`.
  Future<int> upsert(
    dynamic values,
    List<String> uniqueBy, [
    Map<String, dynamic>? update,
  ]) async {
    final rows = _normalizeMultiInsert(values);
    if (rows.isEmpty) return 0;

    final sql = this.grammar.compileUpsert(this, rows, uniqueBy, update);

    final bindings = <dynamic>[];
    for (final row in rows) {
      bindings.addAll(row.values);
    }
    if (update != null) {
      bindings.addAll(update.values);
    }
    return await this.connection.affectingStatement(
          sql,
          this.cleanBindings(bindings),
        );
  }

  /// Returns a single map or a list of maps as a list of rows; an empty map
  /// is no row.
  List<Map<String, dynamic>> _normalizeMultiInsert(dynamic values) {
    if (values is Map<String, dynamic>) {
      return values.isEmpty ? const [] : [values];
    }
    if (values is List) {
      return values.cast<Map<String, dynamic>>();
    }
    throw ArgumentError.value(
      values,
      'values',
      'Expected Map<String, dynamic> or List<Map<String, dynamic>>.',
    );
  }

  /// Inserts one row and returns the generated value of [sequence] (the
  /// primary key column).
  Future<dynamic> insertGetId(Map<String, dynamic> keyValues,
      [String sequence = 'id']) async {
    final sql = this.grammar.compileInsertGetId(this, keyValues, sequence);
    final values = this.cleanBindings(keyValues.values.toList());
    return await this.processor.processInsertGetId(this, sql, values, sequence);
  }

  // ------------------------------------------------------ bulk insert, next

  /// Inserts [rows] in bulk: PostgreSQL `COPY ... FROM STDIN` when the driver
  /// supports it (dpgsql, `db.driver()?.supportsCopy`), otherwise multi-row
  /// INSERTs of up to [batchSize] rows (fewer when the 65535-parameter limit
  /// requires it). Returns the rows inserted.
  ///
  /// Every row must have the [columns] (default: the keys of the first row).
  /// COPY takes scalar values (String, num, bool, DateTime); rows with lists,
  /// maps, bytes or `db.raw(...)` use the INSERT path. Like COPY, it fires no
  /// `on conflict` handling: a duplicate key fails the whole load.
  Future<int> copyInto(Iterable<Map<String, Object?>> rows,
      {List<String>? columns, int batchSize = 1000}) async {
    final list = rows is List<Map<String, Object?>> ? rows : rows.toList();
    if (list.isEmpty) return 0;
    if (this.fromProp is! String) {
      throw StateError('copyInto needs a table (from).');
    }
    final names = columns ?? list.first.keys.toList();
    if (names.isEmpty) {
      throw ArgumentError.value(columns, 'columns', 'Must not be empty.');
    }
    for (final row in list) {
      for (final name in names) {
        if (!row.containsKey(name)) {
          throw ArgumentError.value(row, 'rows', 'A row has no "$name".');
        }
      }
    }

    final driver = this.connection.driver();
    if (driver != null && driver.supportsCopy && list.every(_copyable)) {
      return driver.copyInRows(this.grammar.wrapTable(this.fromProp), names, [
        for (final row in list)
          [for (final name in names) _copyValue(row[name])]
      ]);
    }

    final perStatement = batchSize < 1
        ? 1
        : (batchSize * names.length > 65535
            ? 65535 ~/ names.length
            : batchSize);
    var inserted = 0;
    for (var start = 0; start < list.length; start += perStatement) {
      final end = start + perStatement > list.length
          ? list.length
          : start + perStatement;
      final chunk = [
        for (final row in list.sublist(start, end))
          {for (final name in names) name: row[name]}
      ];
      final sql = this.grammar.compileInsertRows(this, chunk);
      inserted += await this.connection.affectingStatement(sql, [
        for (final row in chunk)
          for (final name in names) row[name]
      ]);
    }
    return inserted;
  }

  static bool _copyable(Map<String, Object?> row) => row.values.every((v) =>
      v == null || v is String || v is num || v is bool || v is DateTime);

  Object? _copyValue(Object? value) =>
      value is DateTime ? this.grammar.formatDateTime(value) : value;

  /// Inserts [rows] with one array parameter per column (PostgreSQL):
  /// `insert into t (a, b) select * from unnest(?::int[], ?::text[])`. The
  /// SQL text is the same for any number of rows (one prepared statement)
  /// and there is no parameter limit. [types] gives the PostgreSQL type of
  /// every column (`{'id': 'int', 'nome': 'text', 'criado': 'timestamp'}`).
  /// Other grammars (MySQL) insert with multi-row INSERTs and ignore
  /// [types]. Returns the rows inserted.
  Future<int> insertUnnest(Iterable<Map<String, Object?>> rows,
      {required Map<String, String> types}) async {
    final list = rows is List<Map<String, Object?>> ? rows : rows.toList();
    if (list.isEmpty) return 0;
    if (types.isEmpty) {
      throw ArgumentError.value(types, 'types', 'Must not be empty.');
    }
    final names = types.keys.toList();
    for (final name in names) {
      final type = types[name]!.trim();
      if (!_sqlTypeName.hasMatch(type)) {
        throw ArgumentError.value(type, 'types', 'Not an SQL type name.');
      }
    }
    for (final row in list) {
      for (final name in names) {
        if (!row.containsKey(name)) {
          throw ArgumentError.value(row, 'rows', 'A row has no "$name".');
        }
        if (row[name] is QueryExpression) {
          throw ArgumentError.value(
              row[name], 'rows', 'Raw SQL is not supported by insertUnnest.');
        }
      }
    }
    if (!this.grammar.supportsArrayBindings) {
      return this.copyInto(list, columns: names);
    }
    final table = this.grammar.wrapTable(this.fromProp);
    final columnList = names.map(this.grammar.wrap).join(', ');
    final arrays = names.map((n) => '?::${types[n]!.trim()}[]').join(', ');
    final sql =
        'insert into $table ($columnList) select * from unnest($arrays)';
    // Each column as a PostgreSQL array literal (text), cast by the SQL: the
    // same for every driver, whatever it does with Dart lists.
    return this.connection.affectingStatement(sql, [
      for (final name in names)
        _arrayLiteral([for (final row in list) _copyValue(row[name])])
    ]);
  }

  /// `{"a","b",NULL}`: a PostgreSQL array literal of [values].
  static String _arrayLiteral(List<Object?> values) {
    final buffer = StringBuffer('{');
    for (var i = 0; i < values.length; i++) {
      if (i > 0) buffer.write(',');
      final value = values[i];
      if (value == null) {
        buffer.write('NULL');
      } else {
        final text =
            value.toString().replaceAll(r'\', r'\\').replaceAll('"', r'\"');
        buffer.write('"$text"');
      }
    }
    buffer.write('}');
    return buffer.toString();
  }

  /// Returns the next number of [column] in the rows of this query (its
  /// where clauses are the scope): `max(column) + 1`, or [start] when no row
  /// matches.
  ///
  /// ```dart
  /// db.table('andamento').where('cod_processo', p)
  ///     .nextValue('cod_andamento');
  /// ```
  ///
  /// With [lock] (default) concurrent callers with the same scope take turns
  /// on a `pg_advisory_xact_lock` of the table, column and scope (PostgreSQL;
  /// other grammars throw [UnsupportedError]: `select max ... for update`
  /// deadlocks under concurrency on InnoDB). The lock lasts until the
  /// transaction ends, so call it in the transaction that inserts the number
  /// (it throws [StateError] outside one). `lock: false` is a plain max + 1.
  /// A sequence or identity column is still the better tool when the
  /// numbers need not be consecutive per scope.
  Future<int> nextValue(String column,
      {int start = 1, bool lock = true}) async {
    final query = this.clone()
      ..ordersProp = []
      ..bindings['order'] = []
      ..limitProp = null
      ..offsetProp = null;
    if (lock) {
      if (!this.grammar.supportsArrayBindings) {
        throw UnsupportedError('nextValue(lock: true) needs PostgreSQL '
            '(pg_advisory_xact_lock); use an AUTO_INCREMENT column, or lock a '
            'parent row with lockForUpdate() and call nextValue(lock: false).');
      }
      if (!this.connection.isInTransaction) {
        throw StateError('nextValue(lock: true) needs a transaction: the lock '
            'lasts until commit and must cover the insert of the number.');
      }
      final key =
          '${query.fromProp}|$column|${query.grammar.compileWheres(query)}|'
          '${query.getBindings().join('|')}';
      await this.connection.select(
          'select pg_advisory_xact_lock(hashtextextended(?, 0))', [key], false);
    }
    final max = await query.max<num>(column);
    return max == null ? start : max.toInt() + 1;
  }

  /// Laravel's updateFrom: an update whose joins become the `FROM` list of
  /// `update ... from ...` (PostgreSQL), their conditions part of the WHERE.
  /// [update] already compiles joins this way here (and as `update ... join`
  /// on MySQL), so both methods give the same SQL; only inner joins.
  Future<int> updateFrom(Map<String, dynamic> keyValues, [Duration? timeout]) =>
      this.update(keyValues, timeout);

  /// Updates the rows the query matches with [keyValues] and returns the
  /// number of affected rows.
  ///
  /// [QueryExpression] values (`db.raw(...)`) are inlined. Joins are
  /// compiled as `update ... from` on PostgreSQL and `update ... join` on
  /// MySQL; a limit restricts the rows (by `ctid` on PostgreSQL). [timeout]
  /// is rounded up to whole seconds.
  Future<int> update(Map<String, dynamic> keyValues, [Duration? timeout]) {
    final sql = this.grammar.compileUpdate(this, keyValues);
    // Each dialect orders CTE/join/SET/where bindings like its SQL.
    final bindings = this.grammar.prepareBindingsForUpdate(this, keyValues);
    return this
        .connection
        .update(sql, this.cleanBindings(bindings), _timeoutSeconds(timeout));
  }

  /// Returns [timeout] in whole seconds for the driver, rounded up; null
  /// keeps the driver's default.
  static int? _timeoutSeconds(Duration? timeout) {
    if (timeout == null) return null;
    final ms = timeout.inMilliseconds;
    return ms <= 0 ? 0 : (ms + 999) ~/ 1000;
  }

  /// Updates the first row that matches [attributes] with [values], or
  /// inserts [attributes] + [values] when no row matches.
  ///
  /// Returns whether a row was inserted or updated; with empty [values] an
  /// existing row counts as done. The `where(attributes)` stays on this
  /// builder. Not atomic: concurrent callers can both insert (see
  /// [createOrFirst]).
  Future<bool> updateOrInsert(
    Map<String, dynamic> attributes, [
    Map<String, dynamic> values = const {},
  ]) async {
    // The wheres are added once and reused by the update below.
    this.where(attributes);
    final bool recordExists = await this.exists();

    if (!recordExists) {
      final inserted = await this.insert({
        ...attributes,
        ...values,
      });

      // Connections return PDOResults; the bool and num cases cover other
      // ConnectionInterface implementations.
      if (inserted is bool) {
        return inserted;
      } else if (inserted is num) {
        return inserted > 0;
      }
      return inserted != null;
    } else {
      if (values.isEmpty) return true;
      final int affectedRows = await this.limit(1).update(values);

      return affectedRows > 0;
    }
  }

  /// Laravel's createOrFirst: inserts [attributes] + [values] and returns the
  /// row; when a unique index or constraint refuses it
  /// ([UniqueConstraintViolationException]), returns the row that matches
  /// [attributes] instead (read from the write connection). The unique index
  /// decides, so two concurrent callers never insert the same row and need
  /// no lock; without a unique index on [attributes] it always inserts.
  ///
  /// On PostgreSQL the insert is `insert ... on conflict do nothing
  /// returning *`: a conflict is not an error, so a surrounding transaction
  /// stays usable on every adapter (postgres_v3 ends the transaction on any
  /// SQL error, even inside a SAVEPOINT). When no row
  /// matches [attributes] after a conflict (another unique index refused the
  /// row), a plain insert is run to throw the
  /// [UniqueConstraintViolationException].
  ///
  /// On MySQL the insert runs in a SAVEPOINT when inside a transaction and
  /// the row is read back by [attributes].
  ///
  /// ```dart
  /// final tag = await db.table('tags').createOrFirst({'slug': 'dart'},
  ///     {'nome': 'Dart'});
  /// ```
  Future<Map<String, dynamic>> createOrFirst(Map<String, dynamic> attributes,
      [Map<String, dynamic> values = const {}]) async {
    final row = {...attributes, ...values};
    if (this.grammar.supportsReturning) {
      final inserted = await (this.clone()
            ..onConflict().doNothing()
            ..returning())
          .insert(row) as PDOResults;
      if (inserted.rows.isNotEmpty) return inserted.rows.first;
      final existing =
          await this.clone().useWritePdo().where(attributes).first();
      if (existing != null) return existing;
      final result = await (this.clone()
            ..onConflictProp = null
            ..returning())
          .insert(row) as PDOResults;
      return result.rows.first;
    }
    try {
      if (!this.connection.isInTransaction) {
        return await _insertAndRead(this.clone(), attributes, row);
      }
      return await this.connection.transaction((ctx) =>
          _insertAndRead(this.clone()..connection = ctx, attributes, row));
    } on UniqueConstraintViolationException {
      final existing =
          await this.clone().useWritePdo().where(attributes).first();
      if (existing == null) rethrow;
      return existing;
    }
  }

  /// Laravel's firstOrCreate: the row that matches [attributes], or
  /// [createOrFirst] of [attributes] + [values] when there is none (so a
  /// concurrent insert of the same row is resolved by the unique index).
  Future<Map<String, dynamic>> firstOrCreate(Map<String, dynamic> attributes,
      [Map<String, dynamic> values = const {}]) async {
    final existing = await this.clone().where(attributes).first();
    return existing ?? await this.createOrFirst(attributes, values);
  }

  static Future<Map<String, dynamic>> _insertAndRead(QueryBuilder query,
      Map<String, dynamic> attributes, Map<String, dynamic> row) async {
    await query.insert(row);
    return await query.useWritePdo().where(attributes).first() ?? row;
  }

  /// Adds [amount] to [column] in the rows the query matches
  /// (`set column = column + amount`), also setting the [extra] columns, and
  /// returns the number of affected rows.
  Future<int> increment(String column,
      [num amount = 1, Map<String, dynamic> extra = const {}]) async {
    final wrapped = this.grammar.wrap(column);
    final Map<String, dynamic> columnsToUpdate = {
      ...extra,
      column: this.raw('$wrapped + $amount'),
    };
    final int affected = await this.update(columnsToUpdate);
    return affected;
  }

  /// Subtracts [amount] from [column] in the rows the query matches
  /// (`set column = column - amount`), also setting the [extra] columns, and
  /// returns the number of affected rows.
  Future<int> decrement(String column,
      [num amount = 1, Map<String, dynamic> extra = const {}]) async {
    final wrapped = this.grammar.wrap(column);

    final Map<String, dynamic> columnsToUpdate = {
      ...extra,
      column: this.raw('$wrapped - $amount'),
    };

    final int affected = await this.update(columnsToUpdate);

    return affected;
  }

  /// Deletes the rows the query matches and returns how many were deleted.
  ///
  /// A non-null [id] first adds `id = ?` to this builder. [timeout] is
  /// rounded up to whole seconds.
  Future<int> delete([dynamic id, Duration? timeout]) {
    if (id != null) {
      this.where('id', SqlOperator.equals, id);
    }

    var sql = this.grammar.compileDelete(this);
    final bindings = this.grammar.prepareBindingsForDelete(this);

    return this
        .connection
        .delete(sql, this.cleanBindings(bindings), _timeoutSeconds(timeout));
  }

  /// Empties the table (`truncate ... restart identity` on PostgreSQL).
  Future<void> truncate() async {
    for (var entry in this.grammar.compileTruncate(this).entries) {
      final sql = entry.key;
      final bindings = entry.value;

      await this.connection.statement(sql, bindings);
    }
  }

  /// Locks this query's table in [mode] (PostgreSQL `LOCK TABLE`), held
  /// until the transaction ends (there is no unlock).
  ///
  /// [noWait] fails at once (SQLSTATE `55P03`) instead of waiting for a
  /// conflicting lock.
  ///
  /// Prefer the narrowest tool: a unique index ([createOrFirst],
  /// [UniqueConstraintViolationException]) for uniqueness, [lockForUpdate]
  /// for rows, `db.advisoryLock(key)` to serialize one piece of code. A
  /// table lock also blocks unrelated work: [TableLockMode.exclusive]
  /// blocks `FOR UPDATE/SHARE` and the foreign key checks of inserts into
  /// tables that reference this one.
  ///
  /// Needs a transaction ([StateError] outside one, where PostgreSQL refuses
  /// `LOCK TABLE`) and PostgreSQL ([UnsupportedError] on MySQL).
  ///
  /// ```dart
  /// await db.transaction((ctx) async {
  ///   await ctx.table('normas.tipo_norma').lockTable(TableLockMode.exclusive);
  ///   // lock table "normas"."tipo_norma" in exclusive mode
  /// });
  /// ```
  Future<void> lockTable(TableLockMode mode,
      {bool noWait = false, Duration? timeout}) async {
    final sql = this.grammar.compileLockTable(this, mode, noWait: noWait);
    if (!this.connection.isInTransaction) {
      throw StateError('lockTable() needs a transaction: the lock is held '
          'until the transaction ends.');
    }
    await this.connection.statement(sql, [], _timeoutSeconds(timeout));
  }

  /// Returns an empty query on the same connection, grammar and processor.
  QueryBuilder newQuery() {
    return QueryBuilder(this.connection, this.grammar, this.processor);
  }

  /// Returns an empty query to build a subquery on.
  QueryBuilder forSubQuery() {
    return this.newQuery();
  }

  /// Appends where clauses and their bindings, e.g. those of another query.
  void mergeWheres(List<Map<String, dynamic>> wheresP, List bindingsP) {
    this.wheresProp.addAll(wheresP);
    this.bindings['where']!.addAll(bindingsP);
  }

  /// Returns [bindings] without the [QueryExpression]s, which are inlined
  /// in the SQL instead of bound.
  List cleanBindings(List bindings) {
    for (final binding in bindings) {
      if (binding is QueryExpression) {
        return Utils.arrayFilter(bindings, (binding) {
          return !(binding is QueryExpression);
        });
      }
    }

    return bindings;
  }

  /// Returns a raw SQL expression, inlined instead of bound.
  QueryExpression raw(dynamic value) {
    return this.connection.raw(value);
  }

  /// Returns all bindings in the order of their placeholders in the select
  /// SQL: CTEs, select, from, join, where, group by, having, order, unions
  /// and the union order.
  List getBindings() {
    var result = <dynamic>[];

    if (bindings['expressions'] is List &&
        bindings['expressions']!.isNotEmpty) {
      result.addAll(bindings['expressions']!);
    }

    if (this.bindings['select'] != null) {
      result.addAll(this.bindings['select']!);
    }
    if (bindings['from'] is List && bindings['from']!.isNotEmpty) {
      result.addAll(bindings['from']!);
    }
    if (this.bindings['join'] != null) {
      result.addAll(this.bindings['join']!);
    }
    if (this.bindings['where'] != null) {
      result.addAll(this.bindings['where']!);
    }
    if (this.bindings['groupBy'] != null) {
      result.addAll(this.bindings['groupBy']!);
    }
    if (this.bindings['having'] != null) {
      result.addAll(this.bindings['having']!);
    }
    if (this.bindings['order'] != null) {
      result.addAll(this.bindings['order']!);
    }
    if (this.bindings['union'] != null) {
      result.addAll(this.bindings['union']!);
    }
    if (this.bindings['unionOrder'] != null) {
      result.addAll(this.bindings['unionOrder']!);
    }

    return result;
  }

  /// Returns the bindings by type (`'select'`, `'where'`, ...).
  Map<String, dynamic> getRawBindings() {
    return this.bindings;
  }

  /// Replaces the bindings of [type] with [bindingsP], one value per
  /// placeholder; throws [ArgumentError] for an unknown type.
  QueryBuilder setBindings(List bindingsP, [String type = 'where']) {
    if (!bindings.containsKey(type)) {
      throw ArgumentError.value(type, 'type', 'Invalid binding type.');
    }
    bindings[type] = [...bindingsP];
    return this;
  }

  /// Adds [value] to the bindings of [type]; a list adds one binding per
  /// element. Throws [ArgumentError] for an unknown type.
  QueryBuilder addBinding(dynamic value, [String type = 'where']) {
    if (!this.bindings.containsKey(type)) {
      throw ArgumentError.value(type, 'type', 'Invalid binding type.');
    }

    final target = this.bindings[type]!;
    if (value is List) {
      target.addAll(value);
    } else {
      target.add(value);
    }

    return this;
  }

  /// Appends every binding of [query] to the bindings of the same type.
  QueryBuilder mergeBindings(QueryBuilder query) {
    query.bindings.forEach((key, value) {
      bindings.putIfAbsent(key, () => []).addAll(value);
    });
    return this;
  }

  /// Returns the database connection.
  ConnectionInterface getConnection() {
    return this.connection;
  }

  /// Returns the result post-processor.
  Processor getProcessor() {
    return this.processor;
  }

  /// Returns the query grammar.
  QueryGrammar getGrammar() {
    return this.grammar;
  }

  /// Runs selects on the write connection (e.g. to read a row just
  /// written, without replica lag).
  QueryBuilder useWritePdo() {
    this.useWritePdoProp = true;
    return this;
  }

  /// Adds `inner join lateral (subquery) as alias on ...`.
  ///
  /// [subquery] is a [QueryBuilder], a `Function(QueryBuilder)` or raw SQL.
  /// [onCallback] adds the `on` conditions to the [JoinClause]; a lateral
  /// join often uses `on true`.
  QueryBuilder joinLateral(
      dynamic subquery, String alias, Function(JoinClause) onCallback) {
    return _addLateralJoin(SqlJoin.inner, subquery, alias, onCallback);
  }

  /// Adds `left join lateral (subquery) as alias on ...`; see
  /// [joinLateral].
  QueryBuilder leftJoinLateral(
      dynamic subquery, String alias, Function(JoinClause) onCallback) {
    return _addLateralJoin(SqlJoin.left, subquery, alias, onCallback);
  }

  QueryBuilder _addLateralJoin(String type, dynamic subquery, String alias,
      Function(JoinClause) onCallback) {
    final res = createSub(subquery);

    final sql = res[0] as String;
    final bindings = res[1] as List;

    final expression = QueryExpression('($sql) as ${grammar.wrapTable(alias)}');

    // The subquery's bindings come before those of the `on` conditions.
    addBinding(bindings, 'join');

    final join = JoinClause(type, expression, this, true);

    onCallback(join);

    joinsProp.add(join);

    addBinding(join.bindingsLocal, 'join');

    return this;
  }

  /// Adds a join on the raw SQL [tableExpression] (not quoted), with
  /// [bindings] for its `?` placeholders.
  ///
  /// [on] adds the `on` conditions to the [JoinClause] (`onRaw` included).
  /// Without them no `on` is compiled, so [tableExpression] may carry its
  /// own (`'processo p ON p.id = ?'`), a `USING`, or need none
  /// (`generate_series(1, 10) as g` with a lateral or natural join).
  ///
  /// ```dart
  /// qb.joinRaw('(select * from foo) as f', [], SqlJoin.inner,
  ///     (join) => join.onRaw('true'));
  /// qb.joinRaw('processo p ON p.id = r.id_processo AND p.ano = ?', [ano]);
  /// ```
  QueryBuilder joinRaw(
    String tableExpression, [
    List bindings = const [],
    String type = SqlJoin.inner,
    Function(JoinClause)? on,
  ]) {
    final tableExpr = QueryExpression(tableExpression);

    final join = JoinClause(type, tableExpr, this);
    if (on != null) {
      on(join);
    }

    this.joinsProp.add(join);

    // The table expression's placeholders come before the conditions'.
    if (bindings.isNotEmpty) {
      this.addBinding(bindings, 'join');
    }
    if (join.bindingsLocal.isNotEmpty) {
      this.addBinding(join.bindingsLocal, 'join');
    }

    return this;
  }

  /// Inserts [values] in one statement:
  /// `INSERT INTO table (...) VALUES (...), (...), ...`.
  ///
  /// The columns are the keys of every row, in the order they first appear;
  /// a row without one of them binds null. A [QueryExpression] value is
  /// inlined. Returns the driver's [PDOResults] (empty, with no rows
  /// affected, for an empty [values]). One statement is limited by the
  /// database's parameter limit (65535 on PostgreSQL); [copyInto] splits
  /// large loads.
  Future<dynamic> insertMany(List<Map<String, dynamic>> values) async {
    if (values.isEmpty) {
      return PDOResults(<Map<String, dynamic>>[], 0);
    }
    final table = grammar.wrapTable(fromProp);
    final columns = <String>{for (final row in values) ...row.keys}.toList();
    final columnsSql = grammar.columnize(columns);
    // Row by row, in the order of the columns.
    final rowsSql = <String>[];
    final bindings = <dynamic>[];
    for (final row in values) {
      final parameters = <String>[];
      for (final column in columns) {
        final value = row[column];
        parameters.add(grammar.parameter(value));
        bindings.add(value);
      }
      rowsSql.add('(${parameters.join(', ')})');
    }
    final sql = 'INSERT INTO $table ($columnsSql) VALUES ${rowsSql.join(', ')}';
    return connection.insert(sql, this.cleanBindings(bindings));
  }

  /// Adds an amount to several columns at once
  /// (`update ... set a = a + 1, b = b + 2`), also setting the [extra]
  /// columns, and returns the number of affected rows.
  Future<int> incrementEach(Map<String, num> columns,
      [Map<String, dynamic> extra = const {}]) {
    return this.update({
      for (final entry in columns.entries)
        entry.key:
            QueryExpression('${this.grammar.wrap(entry.key)} + ${entry.value}'),
      ...extra,
    });
  }

  /// Subtracts an amount from several columns at once
  /// (`update ... set a = a - 1, b = b - 2`), also setting the [extra]
  /// columns, and returns the number of affected rows.
  Future<int> decrementEach(Map<String, num> columns,
      [Map<String, dynamic> extra = const {}]) {
    return this.update({
      for (final entry in columns.entries)
        entry.key:
            QueryExpression('${this.grammar.wrap(entry.key)} - ${entry.value}'),
      ...extra,
    });
  }

  /// Returns the SQL with its bindings inlined, for logs and debugging only
  /// (never execute it: escaping is best-effort, dialect-aware).
  String toRawSql() {
    final bindings = this.connection.prepareBindings(
        List<dynamic>.of(this.cleanBindings(this.getBindings())));
    return this
        .grammar
        .substituteBindingsIntoRawSql(this.toSql(), List<dynamic>.of(bindings));
  }

  /// Prints [toRawSql] and returns the builder.
  QueryBuilder dumpRawSql() {
    print(this.toRawSql());
    return this;
  }

  /// Returns an independent copy of the query: its clauses, bindings,
  /// pending insert clauses and [afterQuery] callbacks.
  QueryBuilder clone() {
    final newQuery = this.newQuery();

    newQuery.columnsProp = columnsProp != null ? [...columnsProp!] : null;
    newQuery.fromProp = fromProp;
    newQuery.joinsProp = joinsProp.map((join) => join.clone()).toList();

    newQuery.wheresProp =
        wheresProp.map((where) => Map<String, dynamic>.from(where)).toList();
    newQuery.groupsProp = [...groupsProp];
    newQuery.havingsProp =
        havingsProp.map((having) => Map<String, dynamic>.from(having)).toList();
    newQuery.ordersProp =
        ordersProp.map((order) => Map<String, dynamic>.from(order)).toList();
    newQuery.limitProp = limitProp;
    newQuery.offsetProp = offsetProp;
    newQuery.unionsProp =
        unionsProp.map((union) => Map<String, dynamic>.from(union)).toList();
    newQuery.unionLimit = unionLimit;
    newQuery.unionOffset = unionOffset;
    newQuery.unionOrdersProp = unionOrdersProp
        .map((order) => Map<String, dynamic>.from(order))
        .toList();
    newQuery.lockProp = lockProp;
    newQuery.distinctProp = distinctProp;
    newQuery.distinctOnProp =
        distinctOnProp != null ? [...distinctOnProp!] : null;

    newQuery.expressionsProp = expressionsProp
        .map((expression) => Map<String, dynamic>.from(expression))
        .toList();

    newQuery.recursionLimitProp = recursionLimitProp;

    newQuery.aggregateProp = aggregateProp != null
        ? Map<String, dynamic>.from(aggregateProp!)
        : null;
    newQuery.useWritePdoProp = useWritePdoProp;
    // OnConflictClause is immutable.
    newQuery.onConflictProp = onConflictProp;
    newQuery.returningProp = returningProp != null ? [...returningProp!] : null;
    newQuery.afterQueryCallbacks.addAll(afterQueryCallbacks);

    newQuery.bindings = {
      'select': [...bindings['select']!],
      'from': [...bindings['from']!],
      'join': [...bindings['join']!],
      'where': [...bindings['where']!],
      'groupBy': [...bindings['groupBy']!],
      'having': [...bindings['having']!],
      'order': [...bindings['order']!],
      'union': [...bindings['union']!],
      'unionOrder': [...bindings['unionOrder']!],
      'expressions': [...bindings['expressions']!],
    };

    return newQuery;
  }

  /// Calls the builder method named [methodName] (PHP's `__call`); only
  /// `select`, `from` and `where` are supported, anything else throws.
  dynamic callMethod(
    String methodName,
    List<dynamic> positionalArguments, [
    Map<Symbol, dynamic> namedArguments = const <Symbol, dynamic>{},
  ]) {
    switch (methodName) {
      case 'select':
        return select(positionalArguments[0]);
      case 'from':
        return from(positionalArguments[0]);
      case 'where':
        if (positionalArguments.length == 1) {
          return Function.apply(where, positionalArguments[0] as List?);
        } else if (positionalArguments.length == 2) {
          return where(positionalArguments[0], positionalArguments[1]);
        } else if (positionalArguments.length == 3) {
          return where(positionalArguments[0], positionalArguments[1],
              positionalArguments[2]);
        } else if (positionalArguments.length == 4) {
          return where(positionalArguments[0], positionalArguments[1],
              positionalArguments[2], positionalArguments[3] as String);
        }
        break;
      default:
        throw Exception("method '$methodName' not exist in QueryBuilder class");
    }
  }
}
