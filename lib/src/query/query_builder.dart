import 'dart:async';
import 'dart:convert';

import 'package:eloquent/src/connection_interface.dart';
import 'package:eloquent/src/driver/driver_access.dart';
import 'package:eloquent/src/contracts/pagination/default_length_aware_paginator.dart';
import 'package:eloquent/src/contracts/pagination/default_paginator.dart';
import 'package:eloquent/src/contracts/pagination/length_aware_paginator.dart';
import 'package:eloquent/src/contracts/pagination/pagination_utils.dart';

import 'package:eloquent/src/query/cursor_pagination.dart';
import 'package:eloquent/src/query/expression.dart';
import 'package:eloquent/src/query/grammars/query_grammar.dart';
import 'package:eloquent/src/query/join_clause.dart';
import 'package:eloquent/src/query/on_conflict_clause.dart';
import 'package:eloquent/src/query/processors/processor.dart';
import 'package:eloquent/src/query/query_lock.dart';
import 'package:eloquent/src/exceptions/records_not_found_exception.dart';
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

  /// Isaque
  /// I added this method to map a String to a property/attribute of the QueryBuilder Class
  /// this allows reading the property/attribute of the QueryBuilder Class based on the property name
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
    // return propertyName;
  }

  /// The database connection instance.
  late ConnectionInterface connection;

  /// The database query grammar instance.
  late QueryGrammar grammar;

  /// The database query post processor instance.
  late Processor processor;

  /// The current query value bindings.
  Map<String, dynamic> bindings = {
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

  /// The columns that should be returned.
  ///
  /// Property of the QueryBuilder class that stores the columns of the table to be returned
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

  /// Indicates whether row locking is being used.
  dynamic lockProp;

  /// The field backups currently in use.
  Map<String, dynamic> backups = {}; // Para orders, limit, offset, columns

  /// The binding backups currently in use.
  Map<String, dynamic> bindingBackups = {}; // Para as chaves 'order' e 'select'

  /// All of the available clause operators.
  final List<String> _operators = List<String>.from(SqlOperator.defaults);

  /// Whether use write pdo for select.
  bool useWritePdoProp = false;

  /// Pending `ON CONFLICT` clause applied to the next low-level [insert].
  ///
  /// Set via [onConflict]/[doUpdate]/[doNothing]. Consumed by [insert].
  OnConflictClause? onConflictProp;

  /// Columns for a `RETURNING` clause on insert/update/delete/upsert.
  ///
  /// Set via [returning]. When non-null the write returns the affected rows
  /// instead of an affected-row count.
  List<dynamic>? returningProp;

  /// Create a new query builder instance.
  ///
  /// [connection] The database connection instance.
  /// [grammar] The database query grammar instance.
  /// [processor] The database query post processor instance.
  QueryBuilder(this.connection, this.grammar, this.processor);

  /// Add a common table expression to the query.
  ///
  /// [name] The name of the CTE.
  /// [query] `Function`|`QueryBuilder`|`String` The query to be used.
  /// [columns] `List`|`null` The columns to be selected.
  /// [recursive] `bool` Whether the CTE is recursive.
  /// Returns the QueryBuilder instance.
  QueryBuilder withExpression(String name, dynamic query,
      [dynamic columns, bool recursive = false, bool materialized = false]) {
    // createSub retorna [sql, bindings]
    final sub = this.createSub(query);
    final sql = sub[0];
    final bindings = sub[1];
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

  /// Add a recursive common table expression to the query.
  ///
  /// [name] The name of the CTE.
  /// [query] `Function`|`QueryBuilder`|`String` The query to be used.
  /// [columns] `List`|`null` The columns to be selected.
  /// Returns the QueryBuilder instance.
  QueryBuilder withRecursiveExpression(String name, query,
      [columns = null, bool materialized = false]) {
    return this.withExpression(name, query, columns, true, materialized);
  }

  /// Add a **MATERIALIZED** common table expression to the query.
  /// (Implied non-recursive)
  ///
  /// [name] The name of the CTE.
  /// [query] `Function`|`QueryBuilder`|`String` The query to be used.
  /// [columns] `List`|`null` The columns to be selected.
  /// Returns the QueryBuilder instance.
  QueryBuilder withMaterializedExpression(String name, dynamic query,
      [dynamic columns]) {
    final sub = this.createSub(query);
    final sql = sub[0];
    final bindings = sub[1];
    this.expressionsProp.add({
      'name': name,
      'query': sql, // The SQL of the subquery
      'columns': columns,
      'recursive': false, // Materialized implies non-recursive in simple form
      'materialized': true, // THE NEW FLAG!
    });
    this.addBinding(bindings, 'expressions');
    return this;
  }

  /// Set the recursion limit of the query.
  ///
  /// [value] The recursion limit.
  /// Returns the QueryBuilder instance.
  QueryBuilder recursionLimit(int value) {
    this.recursionLimitProp = value;
    return this;
  }

  /// Insert new records into the table using a subquery.
  ///
  /// [columns] The columns to insert into.
  /// [query] `Function`|`QueryBuilder`|`String` The subquery.
  /// Returns the result of the insert.
  Future<dynamic> insertUsing(columns, query) async {
    final sub = this.createSub(query);
    final sql = sub[0];
    final subBindings = sub[1];

    // Gets bindings from CTEs (expressions), if any
    final List<dynamic> exprBindings = bindings['expressions'] ?? <dynamic>[];

    // Merges: first expressions bindings, then subquery bindings
    final List<dynamic> mergedBindings = [
      ...exprBindings,
      ...subBindings,
    ];

    final res = await this.connection.insert(
        this.grammar.compileInsertUsing(this, columns, sql),
        this.cleanBindings(mergedBindings));
    return res;
  }

  /// Set the columns to be selected.
  ///
  /// [columnsP] `List`|`dynamic` The columns to select. Defaults to `['*']`.
  /// Returns the QueryBuilder instance.
  ///
  /// [columnsP] is a column, a list of columns, or a map
  /// `{alias: column-or-subquery}`; a subquery (`QueryBuilder` or
  /// `Function(QueryBuilder)`) becomes `(subquery) as alias`. Replaces the
  /// previous select list and its bindings.
  ///
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

  /// Add a subselect expression to the query.
  ///
  /// [query] `Function`|`QueryBuilder`|`String` The subquery.
  /// [alias] The alias for the subquery.
  /// Returns the QueryBuilder instance.
  QueryBuilder selectSub(dynamic query, String alias) {
    final res = this.createSub(query);
    final newQuery = res[0];
    final bindings = res[1];

    return this.selectRaw(
        '(' + newQuery + ') as ' + this.grammar.wrap(alias), bindings);
  }

  /// Add a new "raw" select expression to the query.
  ///
  /// [expression] The raw expression.
  /// [bindingsP] The bindings for the expression.
  /// Returns the QueryBuilder instance.
  QueryBuilder selectRaw(String expression, [List? bindingsP = const []]) {
    this.addSelect(QueryExpression(expression));

    if (bindingsP != null) {
      this.addBinding(bindingsP, 'select');
    }

    return this;
  }

  /// Add a raw from clause to the query.
  ///
  /// [expression] The raw expression.
  /// [bindingsP] The bindings for the expression.
  /// Returns the QueryBuilder instance.
  ///
  /// Example:
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

  /// Creates a subquery and parse it.
  ///
  /// [query] `Function`|`QueryBuilder`|`String` The subquery.
  /// Returns a List containing `[String query, List Bindings]`.
  List createSub(dynamic query) {
    // If the given query is a Closure, we will execute it while passing in a new
    // query instance to the Closure. This will give the developer a chance to
    // format and work with the query before we cast it to a raw SQL string.

    if (query is Function) {
      final callback = query;
      callback(query = this.forSubQuery());
    }

    final result = this.parseSub(query);

    return result;
  }

  /// Parse the subquery into SQL and bindings.
  ///
  /// [query] The subquery (`QueryBuilder`|`String`|`QueryExpression`).
  /// Returns a List containing `[String query, List Bindings]`.
  List parseSub(dynamic query) {
    if (query is QueryBuilder) {
      return [query.toSql(), query.getBindings()];
    } else if (query is String) {
      return [query, []];
    } else if (query is QueryExpression) {
      // added to handle lateral join
      // If it is a QueryExpression, get the value (raw SQL)
      // and assume there are no bindings associated *with this expression* here.
      // Bindings for the raw expression must be added separately if necessary.
      return [query.getValue(), []];
    } else {
      throw ArgumentError.value(query, 'query',
          'Expected a QueryBuilder, String, or QueryExpression.');
    }
  }

  /// Add a new select column to the query.
  ///
  /// [columnP] `QueryExpression`|`List`|`dynamic` The column(s) to add.
  /// Returns the QueryBuilder instance.
  ///
  /// Adds columns to the select list. A map `{alias: subquery}` adds
  /// `(subquery) as alias`; when nothing was selected yet the table's columns
  /// (`table.*`) are kept, as in Laravel.
  ///
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

  /// Force the query to only return distinct results.
  ///
  /// Returns the QueryBuilder instance.
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

  /// Set the table which the query is targeting.
  ///
  /// [tableP] `QueryExpression`|`String` The table to target.
  /// Returns the QueryBuilder instance.
  ///
  /// [tableP] is a table name or a subquery (`QueryBuilder` or
  /// `Function(QueryBuilder)`, which requires [as]).
  ///
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

  /// Add a join clause to the query.
  ///
  /// [table] `String`|`QueryExpression` The name of the table to join.
  /// [one] `String`|`Function(JoinClause)` The first column or a callback.
  /// [operator] `String` The operator (e.g. '=', 'in').
  /// [two] `String`|`null` The second column.
  /// [type] `String` The type of join (e.g. 'inner', 'left').
  /// [where] `bool` Whether to use a where clause.
  /// Returns the QueryBuilder instance.
  QueryBuilder join(dynamic table, dynamic one,
      [String? operator,
      dynamic two = null,
      String type = SqlJoin.inner,
      bool where = false]) {
    // If the first "column" of the join is really a Closure instance the developer
    // is trying to build a join with a complex "on" clause containing more than
    // one condition, so we'll add the join and call a Closure with the query.
    if (one is Function) {
      final join = JoinClause(type, table, this);
      one(join);
      this.joinsProp.add(join);
      this.addBinding(join.bindingsLocal, 'join');
    }
// If the column is simply a string, we can assume the join simply has a basic
// "on" clause with a single condition. So we will just build the join with
// this simple join clauses attached to it. There is not a join callback.
    else {
      final join = JoinClause(type, table, this);
      this.joinsProp.add(join.on(one, operator, two, SqlBool.and, where));
      this.addBinding(join.bindingsLocal, 'join');
    }

    return this;
  }

  /// Add a "join where" clause to the query.
  ///
  /// [table] The table to join.
  /// [one] The first column.
  /// [operator] The operator.
  /// [two] The second column.
  /// [type] The join type.
  /// Returns the QueryBuilder instance.
  QueryBuilder joinWhere(String table, one, operator, two,
      [type = SqlJoin.inner]) {
    return this.join(table, one, operator, two, type, true);
  }

  /// Add a subquery join clause to the query.
  ///
  /// [query] `QueryBuilder`|`String` The subquery.
  /// [alias] The alias for the subquery.
  /// [first] The first column.
  /// [operator] The operator.
  /// [second] The second column.
  /// [type] The join type.
  /// [where] Whether to use a where clause.
  /// Returns the QueryBuilder instance.
  ///
  /// Example:
  /// ```dart
  ///
  /// var subQuery = db.table('public.clientes')
  ///  .selectRaw('clientes_grupos.numero_cliente as numero_cliente, json_agg(row_to_json(grupos.*)) as grupos')
  ///  .join('public.clientes_grupos','clientes_grupos.numero_cliente','=','clientes.numero')
  ///  .join('public.grupos','grupos.numero','=','clientes_grupos.numero_grupo')
  ///  .groupBy('numero_cliente');
  ///
  ///  var map = await db
  ///    .table('clientes')
  ///    .selectRaw('clientes.*')
  ///    .fromRaw('(SELECT * FROM public.clientes) AS clientes')
  ///    .joinSub(subQuery, 'grupos',  (JoinClause join) {
  ///        join.on('grupos.numero_cliente', '=', 'clientes.numero');
  ///    })
  ///    .limit(1)
  ///    .first();
  ///
  /// ```
  QueryBuilder joinSub(dynamic query, alias, dynamic first,
      [String? operator, dynamic second, type = SqlJoin.inner, where = false]) {
    final res = this.createSub(query);

    final newQuery = res[0];
    final bindings = res[1];

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
    return this.crossJoin(QueryExpression(
        '(${res[0]}) as ${this.grammar.wrapTable(alias)}'));
  }

  /// Add a left join to the query.
  ///
  /// [table] The table to join.
  /// [first] The first column.
  /// [operator] The operator.
  /// [second] The second column.
  /// Returns the QueryBuilder instance.
  QueryBuilder leftJoin(String table, first,
      [String? operator, dynamic second]) {
    return this.join(table, first, operator, second, SqlJoin.left);
  }

  /// Add a "left join where" clause to the query.
  ///
  /// [table] The table to join.
  /// [one] The first column.
  /// [operator] The operator.
  /// [two] The second column.
  /// Returns the QueryBuilder instance.
  QueryBuilder leftJoinWhere(
      String table, dynamic one, String operator, dynamic two) {
    return this.joinWhere(table, one, operator, two, SqlJoin.left);
  }

  /// Add a right join to the query.
  ///
  /// [table] The table to join.
  /// [first] The first column.
  /// [operator] The operator.
  /// [second] The second column.
  /// Returns the QueryBuilder instance.
  QueryBuilder rightJoin(String table, dynamic first, String operator,
      [dynamic second]) {
    return this.join(table, first, operator, second, SqlJoin.right);
  }

  /// Add a "right join where" clause to the query.
  ///
  /// [table] The table to join.
  /// [one] The first column.
  /// [operator] The operator.
  /// [two] The second column.
  /// Returns the QueryBuilder instance.
  QueryBuilder rightJoinWhere(
      String table, dynamic one, String operator, dynamic two) {
    return this.joinWhere(table, one, operator, two, SqlJoin.right);
  }

  /// Add a cross join to the query.
  ///
  /// [table] The table to join.
  /// [first] The first column.
  /// [operator] The operator.
  /// [second] The second column.
  /// Returns the QueryBuilder instance.
  QueryBuilder crossJoin(dynamic table,
      [dynamic first, String? operator, dynamic second]) {
    if (first != null) {
      // If a conditional join is passed, delegate to the join method with type 'cross'
      return this.join(table, first, operator, second, SqlJoin.cross);
    }
    // Otherwise, adds a JoinClause of type 'cross' without ON clause
    this.joinsProp.add(JoinClause(SqlJoin.cross, table, this));
    return this;
  }

  /// Apply the [callback] only if [condition] is true.
  /// Returns the QueryBuilder itself for chaining (fluent interface).
  ///
  /// Runs [callback] when [condition] is truthy (not null, false, 0, '' or an
  /// empty collection), otherwise [otherwise]. A callback that takes two
  /// parameters also receives the value: `when(nome, (q, n) => q.where(...))`.
  /// [condition] may be a function returning the value.
  ///
  QueryBuilder when(dynamic condition, Function callback,
      [Function? otherwise]) {
    final value =
        condition is dynamic Function() ? condition() : condition;
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
    final value =
        condition is dynamic Function() ? condition() : condition;
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

  /// Add a basic where clause to the query.
  ///
  /// [column] `String`|`Map`|`Function(QueryBuilder)` The column, map of conditions, or nested callback.
  /// [operator] `String` The operator (e.g. '=', '<').
  /// [value] The value to compare.
  /// [boolean] The boolean connector ('and' or 'or').
  /// Returns the QueryBuilder instance.
  ///
  /// Example:
  /// ```dart
  ///  query.where((QueryBuilder qw1) {
  ///         for (var i = 0; i < processos.length; i++) {
  ///           var proc = processos[i];
  ///           if (i == 0) {
  ///             qw1.where((QueryBuilder q) {
  ///               q.where('sw_processo.cod_processo', '=', proc.keys.first);
  ///               q.where('sw_processo.ano_exercicio', '=', proc.values.first);
  ///             });
  ///           } else {
  ///             qw1.orWhere((QueryBuilder q) {
  ///               q.where('sw_processo.cod_processo', '=', proc.keys.first);
  ///               q.where('sw_processo.ano_exercicio', '=', proc.values.first);
  ///             });
  ///           }
  ///         }
  /// ```
  ///
  /// Called with two arguments (`where('status', 'ativo')`) the second one is
  /// the value and the operator is `=`, as in Laravel. A `null` value becomes
  /// `is null` for `=` and `is not null` for `<>`/`!=`; any other operator with
  /// `null` throws [ArgumentError] instead of silently changing the filter.
  QueryBuilder where(dynamic column,
      [dynamic operator, dynamic value = _absent, String boolean = SqlBool.and]) {
    // Two-argument form: the "operator" slot holds the value.
    if (identical(value, _absent)) {
      if (column is Map || column is Function) {
        value = null;
      } else {
        value = operator;
        operator = SqlOperator.equals;
      }
    }

    // If the column is an array, we will assume it is an array of key-value pairs
    // and can add them each as a where clause. We will maintain the boolean we
    // received when the method was called and pass it into the nested where.
    if (column is Map) {
      return this.whereNested((query) {
        for (var entry in column.entries) {
          query.where(entry.key, SqlOperator.equals, entry.value);
        }
      }, boolean);
    }

    // If the columns is actually a Closure instance, we will assume the developer
    // wants to begin a nested where statement which is wrapped in parenthesis.
    // We'll add that Closure to the query then return back out immediately.
    if (column is Function) {
      return this.whereNested(column, boolean);
    }

    // If the value is a Closure, it means the developer is performing an entire
    // sub-select within the query and we will need to compile the sub-select
    // within the where clause to get the appropriate query record results.
    if (operator != null && operator is! String) {
      throw ArgumentError.value(operator, 'operator',
          'Expected an SQL operator such as "=", ">" or "like".');
    }

    if (value is Function) {
      return this.whereSub(column, operator, value, boolean);
    }

    // `= null` means "is null" and `<> null` / `!= null` means "is not null".
    // Any other comparison with null matches nothing in SQL, so it is an error.
    if (value == null) {
      final op = (operator as String?)?.trim().toLowerCase();
      if (op == null || op == SqlOperator.equals || op == '==') {
        return this.whereNull(column, boolean, false);
      }
      if (op == '<>' || op == '!=') {
        return this.whereNull(column, boolean, true);
      }
      throw ArgumentError.value(
          value,
          'value',
          'Operator "$operator" cannot be compared with null; '
              'use whereNull/whereNotNull.');
    }

    // Now that we are working with just a simple query we can put the elements
    // in our array and add the query binding to our array of bindings that
    // will be bound to each SQL statements when it is finally executed.
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

  QueryBuilder orWhere(dynamic column,
      [dynamic operator, dynamic value = _absent]) {
    return this.where(column, operator, value, SqlBool.or);
  }

  /// Adds a flexible "WHERE" clause to the query.
  ///
  /// This method attempts to emulate the behavior of Laravel's `where` method, where:
  ///
  /// - If the first parameter is a `Map`, it assumes the map contains key/value pairs and
  ///   delegates to a nested WHERE clause (where each key is compared using the '=' operator).
  /// - If the first parameter is a function receiving a `QueryBuilder`, it invokes that function
  ///   to build a nested WHERE clause.
  /// - If called with 2 arguments (e.g., `whereFlex('email', 'test@example.com')`),
  ///   the method interprets the second parameter as the value and implicitly assumes the '=' operator.
  /// - If called with 3 arguments (e.g., `whereFlex('age', '>', 18)`), the second parameter
  ///   is interpreted as the operator and the third as the value.
  /// - If the value is a Function (Closure) receiving a `QueryBuilder`, the clause is treated as a subquery.
  /// - If the value is `null`, the method internally invokes `whereNull`, provided the operator is
  ///   '=', '==', '!=' or '<>'. Otherwise, if the operator is not compatible with null values,
  ///   it is expected to throw an exception (ArgumentError).
  ///
  /// **Limitations and Problematic Scenarios**:
  ///
  /// 1. **Argument count detection**:
  ///    Unlike PHP (which uses `func_num_args()`), in Dart optional parameters always
  ///    receive a value (even if it's the default value). Thus, there is no native way to differentiate
  ///    a call with 2 arguments from a call with 3 arguments exactly.
  ///    The method uses a helper function (_countNonDefaultArguments) as a heuristic to try
  ///    to infer how many arguments were explicitly passed, but this approach may fail in ambiguous
  ///    cases.
  ///
  /// 2. **Null value usage**:
  ///    For example, if the user calls:
  ///    ```dart
  ///    qbFlex.whereFlex('deleted_at', '=', null);
  ///    ```
  ///    it is expected that the method interprets this as a "where deleted_at is null" clause.
  ///    However, due to the heuristic used, the method might interpret this call as if it had
  ///    been made with 2 arguments – causing the '=' operator to be considered as the value, which
  ///    will result in the generated SQL:
  ///    ```sql
  ///    select * from "users" where "deleted_at" = ?
  ///    ```
  ///    with a binding whose value is '=' instead of `null`.
  ///
  /// 3. **Invalid operators with null**:
  ///    If an operator other than '=', '==', '!=' or '<>' is used when explicitly passing a null value,
  ///    it is expected that the method throws an exception. However, if the method interprets the call as having
  ///    only 2 parameters, this validation will not occur and the generated SQL will not match the developer's
  ///    intention.
  ///
  /// **Expected usage example (no issues):**
  ///
  /// ```dart
  /// // 2 arguments interpretation: '=' operator is inferred
  /// qbFlex.whereFlex('email', 'test@example.com');
  /// // Generates: where "email" = ?
  /// // Binding: ['test@example.com']
  ///
  /// // Call with 3 arguments for valid operators:
  /// qbFlex.whereFlex('age', '>', 18);
  /// // Generates: where "age" > ?
  /// // Binding: [18]
  /// ```
  ///
  /// **Problematic scenario:**
  ///
  /// ```dart
  /// // The intention is that this code generates a "where deleted_at is null" clause
  /// // but, due to the heuristic, it might produce:
  /// qbFlex.whereFlex('deleted_at', '=', null);
  /// // Generates: where "deleted_at" = ?
  /// // Binding: ['=']   <-- incorrect binding, because the '=' operator was interpreted as value
  /// ```
  ///
  /// Due to these intrinsic limitations of the Dart language (especially the difficulty of precisely detecting
  /// the number of passed arguments), it is possible that the `whereFlex` functionality may not
  /// behave as expected in all scenarios, so caution is recommended when using it in cases
  /// where null values and operators need to be differentiated precisely.
  ///
  /// **Return:**
  /// Returns the current `QueryBuilder` instance to allow method chaining.
  QueryBuilder whereFlex(dynamic column,
      [dynamic operator, // Kept as dynamic
      dynamic value,
      String boolean = SqlBool.and]) {
    // Case 1: Map
    if (column is Map) {
      return this.whereNested((query) {
        column.forEach((k, v) {
          query.where(k, SqlOperator.equals, v);
        }); // Use normal where here
      }, boolean);
    }

    // Case 2: Function as first argument
    if (column is Function(QueryBuilder)) {
      return this.whereNested(column, boolean);
    }

    // --- Refined Logic to Determine Operator and Value ---
    String? finalOperator;
    dynamic finalValue;

    // Checks if the SECOND argument (operator) WAS provided
    if (operator != null) {
      // Checks if the THIRD argument (value) was also provided
      if (value != null) {
        // Scenario: where('column', 'op', 'val')
        // The second argument MUST be a valid String operator
        if (operator is String && isValidOperator(operator)) {
          finalOperator = operator;
          finalValue = value;
        } else {
          throw ArgumentError(
              'When 3 arguments are provided, the second must be a valid string operator. Got type ${operator.runtimeType} ("$operator")');
        }
      } else {
        // Scenario: where('column', 'something') - 'something' can be operator or value
        // Checks if 'something' (passed as operator) is a VALID String operator
        if (operator is String && isValidOperator(operator)) {
          // It is a valid operator! Treat as where('column', 'op'). The value is implicitly null.
          finalOperator = operator;
          finalValue = null;
          // The subsequent validation (invalidOperatorAndValue) will handle if op + null is valid
        } else {
          // NOT a valid operator. Treat as where('column', 'value').
          finalOperator = SqlOperator.equals; // Implicit operator
          finalValue = operator; // The second argument was the value
        }
      }
    } else {
      // Scenario where('column') - Second argument (operator) is null.
      // Treat as where('column', '=', null), which will be caught by the null logic below.
      finalOperator = SqlOperator.equals;
      finalValue = null;
    }
    // --- End of Refined Logic ---

    // Case 3: Final value is Function (whereSub)
    if (finalValue is Function(QueryBuilder)) {
      // It is crucial that 'finalOperator' is a valid operator here.
      // The logic above must ensure this or have thrown an exception.
      // If finalOperator is null here, something is wrong, use '=' as safe fallback.
      return this.whereSub(column, finalOperator, finalValue, boolean); //?? '='
    }

    // Case 4: Final value is null (whereNull / whereNotNull)
    if (finalValue == null) {
      bool not = (finalOperator == SqlOperator.notEquals ||
          finalOperator == SqlOperator.notEqualsSql);
      if (finalOperator == SqlOperator.equals ||
          finalOperator == SqlOperator.doubleEquals ||
          not) {
        return this.whereNull(column, boolean, not);
      }
      // If not an (in)equality operator, the validation below MUST fail.
    }

    // Final validation: Checks for illegal combinations
    if (this.invalidOperatorAndValue(finalOperator, finalValue)) {
      // If this validation fails, it means the logic above did not handle
      // correctly or the user provided an invalid combination (e.g., '>', null)
      throw ArgumentError(
          'Illegal operator "$finalOperator" and value combination ($finalValue). Operator must be "=" or "!=" or "<>" if value is null.');
    }

    // Case 5: Basic WHERE Clause
    const type = SqlWhereType.basic;
    this.wheresProp.add({
      'type': type,
      'column': column,
      'operator': finalOperator, // Definitely not null here
      'value': finalValue,
      'boolean': boolean
    });

    if (!(finalValue is QueryExpression)) {
      this.addBinding(finalValue, 'where');
    }

    return this;
  }

  // --- Manter orWhereFlex, isValidOperator, invalidOperatorAndValue como estão ---
  QueryBuilder orWhereFlex(dynamic column, [dynamic operator, dynamic value]) {
    return this.whereFlex(column, operator, value, SqlBool.or);
  }

  bool isValidOperator(String? op) {
    if (op == null) return false;
    final allOperators = {..._operators, ...grammar.getOperators()}
        .map((o) => o.toString().toLowerCase())
        .toSet();
    return allOperators.contains(op.toLowerCase());
  }

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

  QueryBuilder whereSubQueryValue(String column, Function(QueryBuilder) closure,
      [String boolean = SqlBool.and]) {
    return this.where(column, SqlOperator.equals, closure, boolean);
  }

  /// Add a "where" clause comparing two columns to the query.
  ///
  /// [first] `String`|`List`|`Map` The first column or array of conditions.
  /// [operator] `String`|`null` The operator.
  /// [second] `String`|`null` The second column.
  /// [boolean] `String` The boolean connector.
  /// Returns the QueryBuilder instance.
  QueryBuilder whereColumn(dynamic first,
      [String? operator, dynamic second, String boolean = SqlBool.and]) {
    // If "first" is an array (List or Map), we assume it is a set of conditions
    // and delegate the addition of conditions to the addArrayOfWheres method.
    if (first is List || first is Map) {
      return this.addArrayOfWheres(first, boolean, 'whereColumn');
    }

    // Checks if the provided operator is valid.
    // If the operator is not found in the list of valid operators of the class (_operators)
    // or in the grammar's operators list (grammar.getOperators()),
    // we assume the developer is shortening the usage of the '=' operator.
    if (operator == null ||
        !(this._operators.contains(operator.toLowerCase()) ||
            this.grammar.getOperators().contains(operator.toLowerCase()))) {
      second = operator;
      operator = SqlOperator.equals;
    }

    // Sets the 'where' clause type to 'Column'
    const type = SqlWhereType.column;

    // Adds the clause to the conditions list (wheresProp)
    this.wheresProp.add({
      'type': type,
      'first': first,
      'operator': operator,
      'second': second,
      'boolean': boolean
    });

    return this;
  }

  /// Add an "or where" clause comparing two columns to the query.
  ///
  /// orWhereColumn('first_name', 'last_name') => OR first_name = last_name
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

  QueryBuilder addArrayOfWheres(dynamic column, String boolean,
      [String method = 'where']) {
    // Uses whereNested to group conditions
    return this.whereNested((QueryBuilder query) {
      // If "column" is a Map (associative array of conditions)
      if (column is Map) {
        column.forEach((key, value) {
          // If the key is numeric and the value is a list,
          // we assume the list contains the parameters to call the 'where' method dynamically.
          if (key is int && value is List) {
            Function.apply(_arrayWhereMethod(query, method), value);
          } else if (method == 'whereColumn') {
            // {'first': 'second'}: both sides are columns.
            query.whereColumn(key, SqlOperator.equals, value);
          } else {
            // Otherwise, treats the key as column name and the value as the value to be compared.
            query.where(key, SqlOperator.equals, value);
          }
        });
      }
      // If "column" is a list, iterates over each item
      else if (column is List) {
        for (var item in column) {
          if (item is List) {
            Function.apply(_arrayWhereMethod(query, method), item);
          } else if (item is Map) {
            // If the item is a map, iterates over each key and value
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

  /// Add a raw where clause to the query.
  ///
  /// [sql] `String` The raw SQL.
  /// [bindings] `List` The bindings.
  /// [boolean] `String` The boolean connector.
  /// Returns the QueryBuilder instance.
  // ------------------------------------------------- whereAny / All / None / Not

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
      _whereColumnsGroup(
          columns, operator, value, SqlBool.or, '$boolean not');

  QueryBuilder orWhereNone(List columns, dynamic operator,
          [dynamic value = _absent]) =>
      _whereColumnsGroup(columns, operator, value, SqlBool.or, 'or not');

  QueryBuilder _whereColumnsGroup(List columns, dynamic operator,
      dynamic value, String inner, String boolean) {
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
          [dynamic operator, dynamic value = _absent,
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
  QueryBuilder whereInTuple(List<String> columns, Iterable<List<Object?>> tuples,
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

  QueryBuilder whereRaw(String sql,
      [List bindings = const [], boolean = SqlBool.and]) {
    const type = SqlWhereType.raw;
    this.wheresProp.add({'type': type, 'sql': sql, 'boolean': boolean});
    this.addBinding(bindings, 'where');
    return this;
  }

  /// Add a raw or where clause to the query.
  ///
  /// [sql] `String` The raw SQL.
  /// [bindings] `List` The bindings.
  /// Returns the QueryBuilder instance.
  QueryBuilder orWhereRaw(String sql, [List bindings = const []]) {
    return this.whereRaw(sql, bindings, SqlBool.or);
  }

  /// Add a where between statement to the query.
  ///
  /// [column] `String` The column.
  /// [values] `List` The values.
  /// [boolean] `String` The boolean connector.
  /// [not] `bool` Whether it is a NOT BETWEEN.
  /// Returns the QueryBuilder instance.
  QueryBuilder whereBetween(String column,
      [List? values, String boolean = SqlBool.and, bool not = false]) {
    const type = SqlWhereType.between;

    this
        .wheresProp
        .add({'column': column, 'type': type, 'boolean': boolean, 'not': not});

    this.addBinding(values, 'where');

    return this;
  }

  ///
  /// Add an or where between statement to the query.
  ///
  ///
  QueryBuilder orWhereBetween(String column, List values) {
    return this.whereBetween(column, values, SqlBool.or);
  }

  /// Add a where not between statement to the query.
  ///
  /// [column] `String` The column.
  /// [values] `List` The values.
  /// [boolean] `String` The boolean connector.
  /// Returns the QueryBuilder instance.
  QueryBuilder whereNotBetween(column, List values, [boolean = SqlBool.and]) {
    return this.whereBetween(column, values, boolean, true);
  }

  /// Add an or where not between statement to the query.
  ///
  /// [column] `String` The column.
  /// [values] `List` The values.
  /// Returns the QueryBuilder instance.
  QueryBuilder orWhereNotBetween(String column, List values) {
    return this.whereNotBetween(column, values, SqlBool.or);
  }

  /// Add a nested where statement to the query.
  ///
  /// [callback] `Function` The callback for the nested query.
  /// [boolean] `String` The boolean connector.
  /// Returns the QueryBuilder instance.
  QueryBuilder whereNested(Function callback, [String boolean = SqlBool.and]) {
    var query = this.forNestedWhere();

    callback(query);

    return this.addNestedWhereQuery(query, boolean);
  }

  /// Create a new query instance for nested where condition.
  ///
  /// Returns the new QueryBuilder instance.
  QueryBuilder forNestedWhere() {
    var query = this.newQuery();

    return query.from(this.fromProp);
  }

  /// Add another query builder as a nested where to the query builder.
  ///
  /// [query] `QueryBuilder` The nested query.
  /// [boolean] `String` The boolean connector.
  /// Returns the QueryBuilder instance.
  QueryBuilder addNestedWhereQuery(QueryBuilder query,
      [boolean = SqlBool.and]) {
    if (query.wheresProp.isNotEmpty) {
      const type = SqlWhereType.nested;

      this.wheresProp.add({'type': type, 'query': query, 'boolean': boolean});

      this.addBinding(query.getBindings(), 'where');
    }

    return this;
  }

  /// Add a full sub-select to the query.
  ///
  /// [column] `String` The column.
  /// [operator] `String`|`null` The operator.
  /// [callback] `Function` The callback.
  /// [boolean] `String` The boolean connector.
  /// Returns the QueryBuilder instance.
  QueryBuilder whereSub(
      String column, String? operator, Function callback, String boolean) {
    const type = SqlWhereType.sub;

    var query = this.newQuery();

    // Once we have the query instance we can simply execute it so it can add all
    // of the sub-select's conditions to itself, and then we can cache it off
    // in the array of where clauses for the "main" parent query instance.
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

  QueryBuilder whereSubFlex(
      String column, String? operator, Function callback, String boolean) {
    const type = SqlWhereType.sub;
    final query = this.forSubQuery(); // Use forSubQuery for consistency
    callback(query);

    // Ensures a default operator if it is null, although previous logic should prevent this
    operator ??= SqlOperator.equals;

    this.wheresProp.add({
      'type': type,
      'column': column,
      'operator': operator, // Final operator determined
      'query': query,
      'boolean': boolean
    });

    this.addBinding(query.getBindings(), 'where');
    return this;
  }

  /// Add an exists clause to the query.
  ///
  /// [callback] `Function` The callback.
  /// [boolean] `String` The boolean connector.
  /// [not] `bool` Whether it is a NOT EXISTS.
  /// Returns the QueryBuilder instance.
  ///
  /// Example:
  /// ```dart
  /// db.table('usuario as usuario')
  ///   .whereExists((q) {
  ///     q.selectRaw('1')
  ///      .from('administracao.usuario_organograma as uo_filtro')
  ///      .whereColumn('uo_filtro.numcgm', '=', 'usuario.numcgm')
  ///      .where('uo_filtro.id_organograma', '=', 10);
  ///   });
  /// ```
  /// Note: the callback receives a QueryBuilder, so use `from(...)` instead of
  /// `table(...)` inside the callback.
  QueryBuilder whereExists(Function callback,
      [String boolean = SqlBool.and, not = false]) {
    var type = not ? SqlWhereType.notExists : SqlWhereType.exists;

    var query = this.newQuery();

    // Similar to the sub-select clause, we will create a new query instance so
    // the developer may cleanly specify the entire exists query and we will
    // compile the whole thing in the grammar and insert it into the SQL.
    callback(query);

    this.wheresProp.add(
        {'type': type, 'operator': null, 'query': query, 'boolean': boolean});

    this.addBinding(query.getBindings(), 'where');

    return this;
  }

  /// Add an or exists clause to the query.
  ///
  /// [callback] `Function` The callback.
  /// [not] `bool` Whether it is a NOT EXISTS.
  /// Returns the QueryBuilder instance.
  ///
  /// Note: the callback receives a QueryBuilder, so use `from(...)` instead of
  /// `table(...)` inside the callback.
  QueryBuilder orWhereExists(Function callback, [bool not = false]) {
    return this.whereExists(callback, SqlBool.or, not);
  }

  /// Add a where not exists clause to the query.
  ///
  /// [callback] `Function` The callback.
  /// [boolean] `String` The boolean connector.
  /// Returns the QueryBuilder instance.
  ///
  /// Note: the callback receives a QueryBuilder, so use `from(...)` instead of
  /// `table(...)` inside the callback.
  QueryBuilder whereNotExists(Function callback,
      [String boolean = SqlBool.and]) {
    return this.whereExists(callback, boolean, true);
  }

  /// Add an or where not exists clause to the query.
  ///
  /// [callback] `Function` The callback.
  /// Returns the QueryBuilder instance.
  ///
  /// Note: the callback receives a QueryBuilder, so use `from(...)` instead of
  /// `table(...)` inside the callback.
  QueryBuilder orWhereNotExists(Function callback) {
    return this.orWhereExists(callback, true);
  }

  /// Add a "where in" clause to the query.
  ///
  /// [column] `String` The column.
  /// [values] `List`|`QueryBuilder`|`Function` The values.
  /// [boolean] `String` The boolean connector.
  /// [not] `bool` Whether it is a NOT IN.
  /// Returns the QueryBuilder instance.
  QueryBuilder whereIn(String column, dynamic values,
      [String boolean = SqlBool.and, bool not = false]) {
    var type = not ? SqlWhereType.notInList : SqlWhereType.inList;

    //static se refere ao instancia da propria class
    if (values is QueryBuilder) {
      return this.whereInExistingQuery(column, values, boolean, not);
    }

    // If the value of the where in clause is actually a Closure, we will assume that
    // the developer is using a full sub-select for this "in" statement, and will
    // execute those Closures, then we can re-construct the entire sub-selects.
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

  /// Add an "or where in" clause to the query.
  ///
  /// [column] `String` The column.
  /// [values] `dynamic` The values.
  /// Returns the QueryBuilder instance.
  QueryBuilder orWhereIn(String column, dynamic values) {
    return this.whereIn(column, values, SqlBool.or);
  }

  /// Add a "where not in" clause to the query.
  ///
  /// [column] `String` The column.
  /// [values] `dynamic` The values.
  /// [boolean] `String` The boolean connector.
  /// Returns the QueryBuilder instance.
  QueryBuilder whereNotIn(String column, values, [boolean = SqlBool.and]) {
    return this.whereIn(column, values, boolean, true);
  }

  /// Add an "or where not in" clause to the query.
  ///
  /// [column] `String` The column.
  /// [values] `dynamic` The values.
  /// Returns the QueryBuilder instance.
  QueryBuilder orWhereNotIn(column, values) {
    return this.whereNotIn(column, values, SqlBool.or);
  }

  ///
  /// Add a where in with a sub-select to the query.
  ///
  ///
  QueryBuilder whereInSub(
      String column, Function callback, String boolean, bool not) {
    final type = not ? SqlWhereType.notInSub : SqlWhereType.inSub;

    // To create the exists sub-select, we will actually create a query and call the
    // provided callback with the query so the developer may set any of the query
    // conditions they want for the in clause, then we'll put it in this array.
    final query = this.newQuery();
    callback(query);

    this.wheresProp.add(
        {'type': type, 'column': column, 'query': query, 'boolean': boolean});

    this.addBinding(query.getBindings(), 'where');

    return this;
  }

  ///
  /// Add a external sub-select to the query.
  ///
  ///
  QueryBuilder whereInExistingQuery(
      String column, QueryBuilder query, String boolean, bool not) {
    var type = not ? SqlWhereType.notInSub : SqlWhereType.inSub;

    this.wheresProp.add(
        {'type': type, 'column': column, 'query': query, 'boolean': boolean});

    this.addBinding(query.getBindings(), 'where');

    return this;
  }

  ///
  /// Add a "where null" clause to the query.
  ///
  ///
  QueryBuilder whereNull(String column,
      [String boolean = SqlBool.and, bool not = false]) {
    var type = not ? SqlWhereType.isNotNull : SqlWhereType.isNull;

    this.wheresProp.add({'type': type, 'column': column, 'boolean': boolean});

    return this;
  }

  ///
  /// Add an "or where null" clause to the query.
  ///
  ///
  QueryBuilder orWhereNull(String column) {
    return this.whereNull(column, SqlBool.or);
  }

  // --- PostgreSQL JSON / array / full-text helpers -------------------------

  /// Add a JSON containment clause: `("column")::jsonb @> ?`.
  ///
  /// [value] is JSON-encoded and bound. Use for jsonb columns and arrays, e.g.
  /// `whereJsonContains('tags', ['urgent'])` or
  /// `whereJsonContains('meta->roles', 'admin')`.
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

  /// Add a JSON array length comparison: `jsonb_array_length(("column")::jsonb) <op> ?`.
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

  QueryBuilder orWhereJsonLength(String column, String operator, dynamic value) =>
      this.whereJsonLength(column, operator, value, SqlBool.or);

  /// Add a PostgreSQL full-text search clause across one or more [columns].
  ///
  /// [options] may include `'language'` (default `'english'`) and `'mode'`
  /// (`'plain'` | `'phrase'` | `'websearch'`).
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
    // Add the whole List as a single binding (addBinding would spread it).
    this.bindings['where'].add(value);
    return this;
  }

  ///
  /// Add a "where not null" clause to the query.
  ///
  ///
  QueryBuilder whereNotNull(String column, [String boolean = SqlBool.and]) {
    return this.whereNull(column, boolean, true);
  }

  ///
  /// Add an "or where not null" clause to the query.
  ///
  ///
  QueryBuilder orWhereNotNull(String column) {
    return this.whereNotNull(column, SqlBool.or);
  }

  ///
  /// Add a "where date" statement to the query.
  ///
  ///
  QueryBuilder whereDate(String column, String? operator, DateTime? value,
      [String boolean = SqlBool.and]) {
    return this.addDateBasedWhere('Date', column, operator, value, boolean);
  }

  /// Add an "or where date" statement to the query.
  /// Basic: `orWhereDate('created_at', '=', someDate)`
  QueryBuilder orWhereDate(String column, String operator, DateTime? value) {
    return this.whereDate(column, operator, value, SqlBool.or);
  }

  /// Add a "where time" statement to the query.
  /// [column] Ex: 'created_at'
  /// [operator] Ex: '=', '<', '>'
  /// [value] Ex: '12:00:00' or a DateTime whose time matters
  /// [boolean] Whether it is 'and' or 'or'
  QueryBuilder whereTime(String column, String operator, dynamic value,
      [String boolean = SqlBool.and]) {
    // Assuming addDateBasedWhere('Time', ...) truncates/compares only the time part
    return this.addDateBasedWhere('Time', column, operator, value, boolean);
  }

  /// Add an "or where time" statement to the query.
  QueryBuilder orWhereTime(String column, String operator, dynamic value) {
    return this.whereTime(column, operator, value, SqlBool.or);
  }

  ///
  /// Add a "where day" statement to the query.
  ///
  ///
  QueryBuilder whereDay(String column, String operator, int value,
      [String boolean = SqlBool.and]) {
    return this.addDateBasedWhere('Day', column, operator, value, boolean);
  }

  ///
  /// Add a "where month" statement to the query.
  ///
  ///
  QueryBuilder whereMonth(String column, String operator, int value,
      [String boolean = SqlBool.and]) {
    return this.addDateBasedWhere('Month', column, operator, value, boolean);
  }

  ///
  /// Add a "where year" statement to the query.
  ///
  ///
  QueryBuilder whereYear(String column, String operator, int value,
      [String boolean = SqlBool.and]) {
    return this.addDateBasedWhere('Year', column, operator, value, boolean);
  }

  ///
  /// Add a date based (year, month, day) statement to the query.
  ///
  ///
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

  ///
  /// Handles dynamic "where" clauses to the query.
  ///
  ///
  ///
  /// Example: `whereFirstNameAndLastName('John', 'Doe')` will be translated to:
  /// ```dart
  /// where('first_name', '=', 'John', 'and')
  ///   .where('last_name', '=', 'Doe', 'and')
  /// ```
  ///
  /// The method expects the name to start with "where" and the rest to be composed
  /// of segments separated by "And" or "Or".
  QueryBuilder dynamicWhere(String method, List<dynamic> parameters) {
    // Removes the "where" prefix
    final finder = method.substring(5);

    // Processes the string, separating segments and connectors.
    // Uses a regex to capture "And" or "Or" when followed by an uppercase letter.
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

  ///
  /// Add a single dynamic where clause statement to the query.
  ///
  ///
  void addDynamic(
      String segment, String connector, List<dynamic> parameters, int index) {
    // Converts the segment from CamelCase to snake_case.
    final column = Utils.toSnakeCase(segment);
    // Adds the where clause using the "=" operator.
    // Here it is assumed that the where method is already implemented in the class.
    where(column, SqlOperator.equals, parameters[index], connector);
  }

  ///
  /// Add a "group by" clause to the query.
  ///
  ///
  ///
  /// [column] is a column name, a [QueryExpression] (`db.raw(...)`) or a list
  /// of them. Anything else throws (it used to be ignored silently).
  ///
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

  ///
  /// Add a raw "group by" clause, with optional bindings.
  ///
  /// ```dart
  /// db.table('t')
  ///     .selectRaw("date_trunc(?, created_at) as dia, count(*) as total", ['day'])
  ///     .groupByRaw('date_trunc(?, created_at)', ['day']);
  /// ```
  ///
  QueryBuilder groupByRaw(String sql, [List bindingsP = const []]) {
    this.groupsProp = [...this.groupsProp, QueryExpression(sql)];
    this.addBinding(bindingsP, 'groupBy');
    return this;
  }

  ///
  /// Add a "having" clause to the query.
  ///
  ///
  ///
  /// `having(column, value)` (two arguments) means `=`; a
  /// `Function(QueryBuilder)` column builds a nested group.
  ///
  QueryBuilder having(dynamic column,
      [dynamic operator, dynamic value = _absent, String boolean = SqlBool.and]) {
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

  ///
  /// Add a "or having" clause to the query.
  ///
  ///
  QueryBuilder orHaving(dynamic column,
      [dynamic operator, dynamic value = _absent]) {
    return this.having(column, operator, value, SqlBool.or);
  }

  /// A parenthesized group of having clauses built by [callback].
  QueryBuilder havingNested(Function callback,
      [String boolean = SqlBool.and]) {
    final query = this.forNestedWhere();
    callback(query);
    if (query.havingsProp.isNotEmpty) {
      this.havingsProp.add({'type': 'Nested', 'query': query, 'boolean': boolean});
      this.addBinding(query.bindings['having'], 'having');
    }
    return this;
  }

  /// `having column between ? and ?`.
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

  /// `having column is null` ([columns] is a column or a list of them).
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

  QueryBuilder havingNotNull(dynamic columns,
          [String boolean = SqlBool.and]) =>
      this.havingNull(columns, boolean, true);

  QueryBuilder orHavingNotNull(dynamic columns) =>
      this.havingNull(columns, SqlBool.or, true);

  /// Add a raw "having" clause to the query.
  ///
  /// [sql] is the raw SQL expression.
  /// [bindings] are the values to be bound to the query.
  /// [boolean] indicates the logical connector of the clause (default is "and").
  /// Returns the current QueryBuilder instance for chaining.
  QueryBuilder havingRaw(String sql,
      [List bindings = const [], String boolean = SqlBool.and]) {
    const type = 'raw';

    // Adds a record to havingsProp with the necessary info
    this.havingsProp.add({
      'type': type,
      'sql': sql,
      'boolean': boolean,
    });

    // Adds binding values to 'having' section
    this.addBinding(bindings, 'having');

    return this;
  }

  /// Add a raw "having" clause with "or" connector to the query.
  ///
  /// [sql] is the raw SQL expression.
  /// [bindings] are the values to be bound to the query.
  QueryBuilder orHavingRaw(String sql, [List bindings = const []]) {
    return this.havingRaw(sql, bindings, SqlBool.or);
  }

  ///
  /// Add an "order by" clause to the query.
  ///
  ///
  ///
  /// [column] is a column, a [QueryExpression] or a subquery (`QueryBuilder`
  /// or `Function(QueryBuilder)`). [direction] must be `asc` or `desc` (any
  /// other value used to become `desc` silently).
  ///
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
        throw ArgumentError.value(target, name,
            'Expected a column, db.raw(...) or a list of them.');
      }
    }
    return this;
  }

  /// `order by column desc`.
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

  /// [reorder] by [column] descending.
  QueryBuilder reorderDesc(dynamic column) {
    return this.reorder(column, SqlSort.desc);
  }

  ///
  /// Add an "order by" clause for a timestamp to the query.
  ///
  ///
  QueryBuilder latest([String column = 'created_at']) {
    return this.orderBy(column, SqlSort.desc);
  }

  ///
  /// Add an "order by" clause for a timestamp to the query.
  ///
  ///
  QueryBuilder oldest([String column = 'created_at']) {
    return this.orderBy(column, SqlSort.asc);
  }

  /// Put the query's results in random order.
  ///
  /// [seed] can be used in some DBMSs to generate "seeded random".
  QueryBuilder inRandomOrder([String seed = '']) {
    // grammar.compileRandom(seed) would return something like "RAND()" or "RANDOM()"
    final randomExpression = this.grammar.compileRandom(seed);
    return this.orderByRaw(randomExpression);
  }

  ///
  /// Add a raw "order by" clause to the query.
  ///
  ///
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

  ///
  /// Set the "offset" value of the query.
  ///
  ///
  QueryBuilder offset(int value) {
    var v = value < 0 ? 0 : value;
    if (this.unionsProp.isNotEmpty) {
      this.unionOffset = v;
    } else {
      this.offsetProp = v;
    }

    return this;
  }

  ///
  /// Alias to set the "offset" value of the query.
  ///
  ///
  QueryBuilder skip(int value) {
    return this.offset(value);
  }

  ///
  /// Set the "limit" value of the query.
  ///
  ///
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

  ///
  /// Alias to set the "limit" value of the query.
  ///
  ///
  QueryBuilder take(int value) {
    return this.limit(value);
  }

  ///
  /// Set the limit and offset for a given page.
  ///
  ///
  QueryBuilder forPage(int page, [int perPage = 15]) {
    return this.skip((page - 1) * perPage).take(perPage);
  }

  /// Constrain the query to the next "page" of results after a given ID.
  ///
  /// [perPage]: quantos registros buscar
  /// [lastId]: valor do ID a partir do qual buscar
  /// [column]: nome da coluna ID
  QueryBuilder forPageAfterId([
    int perPage = 15,
    dynamic lastId = 0,
    String column = 'id',
  ]) {
    // 1. Remove qualquer ordering que já exista pela mesma coluna
    this.ordersProp = this.ordersProp.where((order) {
      return order['column'] != column;
    }).toList();
    // 2. Adiciona where(column, '>', lastId) (null: first page, no filter)
    if (lastId != null) {
      this.where(column, SqlOperator.greater, lastId);
    }
    // 3. Ordena pela coluna asc
    this.orderBy(column, SqlSort.asc);
    // 4. Limita a [perPage]
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

  ///
  /// Add a union statement to the query.
  ///
  ///
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

  ///
  /// Add a union all statement to the query.
  ///
  ///
  QueryBuilder unionAll(dynamic query) {
    return this.union(query, true);
  }

  ///
  /// Lock the selected rows in the table.
  ///
  /// [value] is `true` (`FOR UPDATE`), `false` (shared lock), a [QueryLock],
  /// or a raw SQL string used verbatim (for example `'for no key update'`).
  ///
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

  ///
  /// Lock the selected rows in the table for updating.
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
  ///
  QueryBuilder lockForUpdate(
      {bool skipLocked = false, bool noWait = false, List<String>? of}) {
    if (!skipLocked && !noWait && (of == null || of.isEmpty)) {
      return this.lock(true);
    }
    return this.lock(QueryLock(
        skipLocked: skipLocked, noWait: noWait, of: of ?? const <String>[]));
  }

  ///
  /// Share lock the selected rows in the table.
  ///
  /// Accepts the same modifiers as [lockForUpdate].
  ///
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

  ///
  /// Add `SKIP LOCKED` to the current lock; without a lock it implies
  /// `FOR UPDATE`, so `skipLocked()` alone yields `for update skip locked`.
  ///
  QueryBuilder skipLocked() {
    return this.lock(_currentQueryLock().copyWith(skipLocked: true));
  }

  ///
  /// Add `NOWAIT` to the current lock; without a lock it implies
  /// `FOR UPDATE`.
  ///
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

  ///
  /// Get the SQL representation of the query.
  ///
  ///
  String toSql() {
    return this.grammar.compileSelect(this);
  }

  ///
  /// Execute a query for a single record by ID.
  ///
  ///
  Future<Map<String, dynamic>?> find(int id,
      [List<String> columns = const ['*']]) {
    return this.where('id', SqlOperator.equals, id).first(columns);
  }

  ///
  /// Get a single column's value from the first result of a query.
  ///
  ///
  /// Returns the value of [column] in the first row, or `null` when there is
  /// no row. `'t.col'` and `'col as alias'` are accepted.
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

  /// The only row of the query: throws [RecordsNotFoundException] when there
  /// is none and [MultipleRecordsFoundException] when there is more than one.
  Future<Map<String, dynamic>> sole([List<String> columns = const ['*']]) async {
    final rows = await this.clone().take(2).get(columns);
    if (rows.isEmpty) {
      throw RecordsNotFoundException();
    }
    if (rows.length > 1) {
      throw MultipleRecordsFoundException(rows.length);
    }
    return rows.first;
  }

  /// The value of [column] in the only row of the query (see [sole]).
  Future<dynamic> soleValue(String column) async {
    return _valueFromRow(await this.sole([column]), column);
  }

  /// The first row, or [RecordsNotFoundException] when there is none.
  Future<Map<String, dynamic>> firstOrFail(
      [List<String> columns = const ['*']]) async {
    final row = await this.first(columns);
    if (row == null) {
      throw RecordsNotFoundException();
    }
    return row;
  }

  /// The row with `id = id`, or the result of [callback] when there is none.
  Future<dynamic> findOr(dynamic id, FutureOr<dynamic> Function() callback,
      [List<String> columns = const ['*']]) async {
    final row =
        await this.where('id', SqlOperator.equals, id).first(columns);
    return row ?? await callback();
  }

  ///
  /// Execute the query and get the first result.
  ///
  /// [columns] columns
  /// `Return` Map<String,dynamic>
  ///
  Future<Map<String, dynamic>?> first(
      [List<String> columns = const ['*'], int? timeoutInSeconds]) async {
    final results = await this.take(1).get(columns, timeoutInSeconds);
    return results.isNotEmpty ? results.first : null;
  }

  ///
  /// Execute the query as a "select" statement.
  ///
  ///
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

    final resultRunSelect = await this.runSelect(timeoutInSeconds);
    var results = this.processor.processSelect(this, resultRunSelect);

    if (!hadColumns) {
      this.columnsProp = null;
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

  ///
  /// Run the query as a "select" statement against the connection.
  ///
  ///
  Future<List<Map<String, dynamic>>> runSelect([int? timeoutInSeconds]) async {
    final sqlStr = this.toSql();

    final bid = this.getBindings();

    final com = this.connection;

    final results =
        await com.select(sqlStr, bid, !this.useWritePdoProp, timeoutInSeconds);

    return results;
  }

  ///
  /// Stream the query results row-by-row using a server-side cursor.
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

  ///
  /// Alias for [cursor] — lazily stream rows without loading them all in memory.
  ///
  Stream<Map<String, dynamic>> lazy([int? fetchSize]) => this.cursor(fetchSize);

  ///
  /// Direct, driver-specific access (bulk COPY, pipelining, LISTEN/NOTIFY, raw
  /// connection). Returns `null` when the active driver has no such support.
  ///
  /// ```dart
  /// final drv = db.table('t').driver();
  /// if (drv != null && drv.supportsCopy) {
  ///   await drv.copyInRows('temp_location', ['id', 'city'], rows);
  /// }
  /// ```
  DriverAccess? driver() => this.connection.driver();

  ///
  /// Paginate the given query into a simple paginator.
  ///
  ///
  Future<LengthAwarePaginator> paginate({
    int perPage = 15,
    List<String> columns = const ['*'],
    String pageName = 'page',
    int? page,
  }) async {
    // If the page is not provided, resolves the current page.
    page ??= PaginationUtils.resolveCurrentPage(pageName);

    // Gets total records for pagination.
    int total = await getCountForPagination(columns);

    // If there are records, gets results for requested page; otherwise returns empty.
    // A clone keeps limit/offset of the page off this builder.
    List<Map<String, dynamic>> results =
        total > 0 ? await clone().forPage(page, perPage).get(columns) : [];

    // Returns LengthAwarePaginator with results and metadata.
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
      final values = [for (final (column, _) in orders) position.valueOf(column)];
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

  ///
  /// Get a paginator only supporting simple next and previous links.
  ///
  /// This is more efficient on larger data-sets, etc.
  ///
  ///
  /// Get a paginator only supporting simple next and previous links.
  /// More efficient on large datasets as it doesn't do count(*).
  Future<DefaultPaginator> simplePaginate({
    int perPage = 15,
    List<String> columns = const ['*'],
    String pageName = 'page',
    int? page,
  }) async {
    // 1. Determines current page
    page ??= PaginationUtils.resolveCurrentPage(pageName);

    // 2. Loads (perPage + 1) results to detect if there's a next page
    final results = await this
        .clone()
        .skip((page - 1) * perPage)
        .take(perPage + 1)
        .get(columns);

    // 3. If more records than `perPage` came back, there are more pages
    bool hasMorePages = results.length > perPage;

    // If 1 extra came back, remove it (we only want to display 'perPage' items)
    List<Map<String, dynamic>> pageItems = results;
    if (hasMorePages) {
      pageItems = results.sublist(0, perPage);
    }

    // 4. Assembles paginator
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

  ///
  /// Get the count of the total records for the paginator.
  ///
  ///
  /// Returns total count of records for pagination.
  Future<int> getCountForPagination(
      [List<String> columns = const ['*']]) async {
    // Grouped/distinct/union queries: count their rows in the database
    // instead of fetching every aggregated row.
    if (_needsCountSubquery(clearSelectAliases(columns))) {
      return _countUsingSubquery(forPagination: true);
    }

    backupFieldsForCount();

    // Sets aggregation for count, removing aliases.
    aggregateProp = {
      'function': 'count',
      'columns': clearSelectAliases(columns)
    };

    // Executes query (in this case, count query). The fields are restored
    // even when it fails, so the builder can still be used.
    final List<Map<String, dynamic>> results;
    try {
      results = await get();
    } finally {
      aggregateProp = null;
      restoreFieldsForCount();
    }

    // Expects result to have an 'aggregate' key.
    if (results.isNotEmpty && results.first.containsKey('aggregate')) {
      return _aggregateToInt(results.first['aggregate']);
    }

    return 0;
  }

  ///
  /// Backup some fields for the pagination count.
  ///
  ///
  /// Backs up fields used in pagination count.
  void backupFieldsForCount() {
    // Backup of query fields.
    backups['orders'] = ordersProp;
    backups['limit'] = limitProp;
    backups['offset'] = offsetProp;
    backups['columns'] = columnsProp;

    // Sets query fields to null (or empty lists) for count.
    ordersProp = [];
    limitProp = null;
    offsetProp = null;
    columnsProp = null;

    // Backup of bindings for 'order' and 'select'.
    bindingBackups['order'] = bindings['order'];
    bindingBackups['select'] = bindings['select'];

    // Clears 'order' and 'select' bindings so they don't interfere with count.
    bindings['order'] = [];
    bindings['select'] = [];
  }

  ///
  /// Remove the column aliases since they will break count queries.
  ///
  ///
  /// Removes column aliases to prevent issues in count.
  /// Example: "users.name as user_name" becomes "users.name".
  List<String> clearSelectAliases(List<String> columns) {
    return columns.map((column) {
      final aliasPos = column.toLowerCase().indexOf(' as ');
      return aliasPos != -1 ? column.substring(0, aliasPos) : column;
    }).toList();
  }

  ///
  /// Restore some fields after the pagination count.
  ///
  ///
  /// Restores fields modified for pagination count.
  void restoreFieldsForCount() {
    ordersProp = backups['orders'];
    limitProp = backups['limit'];
    offsetProp = backups['offset'];
    columnsProp = backups['columns'];

    bindings['order'] = bindingBackups['order'];
    bindings['select'] = bindingBackups['select'];

    backups.clear();
    bindingBackups.clear();
  }

  /// Chunk the results of the query into blocks of [count] items each,
  /// calling [callback] for each block.
  ///
  /// The callback receives (list of results, page number).
  /// Returns false if interrupted early, or true if iterated completely.
  Future<bool> chunk(
    int count,
    FutureOr<bool> Function(List<Map<String, dynamic>> chunk, int page)
        callback,
  ) async {
    int page = 1;

    while (true) {
      // Loads the next block
      final results = await this.forPage(page, count).get();
      final countResults = results.length;

      if (countResults == 0) {
        // No more records
        break;
      }

      // Executes the callback; if it returns false, we stop the loop
      final cbResult = await callback(results, page);
      if (cbResult == false) {
        return false;
      }

      page++;

      // If less than "count", nothing more to fetch
      if (countResults < count) {
        break;
      }
    }

    return true;
  }

  /// Chunk the results of a query by comparing numeric IDs.
  ///
  /// [count]: how many records per "block"
  /// [callback]: receives the block list and must return bool
  /// [column]: name of the ID column, defaults to 'id'
  /// [alias]: if the field has a different alias, e.g., 'users.id as user_id'.
  ///
  /// Usage example:
  ///   await query.chunkById(100, (chunk) async { ... }, 'id');
  Future<bool> chunkById(
    int count,
    FutureOr<bool> Function(List<Map<String, dynamic>> chunk) callback, {
    String column = 'id',
    String? alias,
  }) async {
    return _chunkById(count, callback, column, alias, descending: false);
  }

  /// [chunkById] in descending order of [column].
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

  /// Calls [callback] for every row, reading [count] rows at a time by id.
  /// Returning `false` stops the iteration.
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
  /// (keyset pagination). Works on every driver; memory stays bounded.
  Stream<Map<String, dynamic>> lazyById(
      [int chunkSize = 1000, String column = 'id', String? alias]) {
    return _lazyById(chunkSize, column, alias, descending: false);
  }

  /// [lazyById] in descending order of [column].
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

  /// Maps every row with [callback], reading [count] rows at a time.
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

  /// Execute a callback over each item while chunking.
  ///
  /// [callback] is called for each individual item. If it returns false, it stops.
  /// [count] is the block size for chunking.
  /// Returns true if completed, or false if interrupted early.
  Future<bool> each(
    FutureOr<bool> Function(Map<String, dynamic> row, int index) callback, [
    int count = 1000,
  ]) async {
    // (Optional) in Laravel, it requires orderBy to be defined before each()
    int globalIndex = 0; // General counter, across chunks
    return await this.chunk(count, (chunkRows, page) async {
      for (int i = 0; i < chunkRows.length; i++) {
        final row = chunkRows[i];
        // callback receives (row, global or local index)
        final cbResult = await callback(row, globalIndex);
        if (cbResult == false) {
          return false; // Interrupted chunk and return false
        }
        globalIndex++;
      }
      return true; // continue to next chunk
    });
  }

  ///
  /// Get an array with the values of a given column.
  ///
  ///
  Future<dynamic> pluck(String column, [String? key]) async {
    var results = await this.get(key == null ? [column] : [column, key]);

    // If the columns are qualified with a table or have an alias, we cannot use
    // those directly in the "pluck" operations since the results from the DB
    // are only keyed by the column itself. We'll strip the table out here.
    // return Utils.array_pluck(
    //     results, this.stripTableForPluck(column), this.stripTableForPluck(key));

    return Arr.pluck(
        results, this.stripTableForPluck(column), this.stripTableForPluck(key));
  }

  ///
  /// Alias for the "pluck" method.
  ///
  ///
  ///
  /// Strip off the table name or alias from a column identifier.
  ///
  ///
  dynamic stripTableForPluck(column) {
    return column == null ? column : column.split(RegExp(r'\.| ')).last;
  }

  /// Concatenate values of a given column as a string.
  ///
  /// In Laravel, `implode(column, glue)` combines values into a single string.
  /// Here, it returns the concatenated string.
  Future<String> implode(String column, [String glue = '']) async {
    // 1. Gets list of column values using pluck
    final dynamic result = await this.pluck(column);
    // 2. If pluck returns a list, converts each item to string and joins
    if (result is List) {
      return result.map((item) => item?.toString() ?? '').join(glue);
    }
    // 3. If not a list (or if pluck isn't complete yet), returns empty
    return '';
  }

  ///
  /// Determine if any rows exist for the current query.
  ///
  ///
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

  /// `true` when a row exists, otherwise the result of [callback].
  Future<dynamic> existsOr(FutureOr<dynamic> Function() callback) async =>
      await this.exists() ? true : await callback();

  /// `true` when no row exists, otherwise the result of [callback].
  Future<dynamic> doesntExistOr(FutureOr<dynamic> Function() callback) async =>
      await this.doesntExist() ? true : await callback();

  ///
  /// Retrieve the "count" result of the query.
  ///
  ///
  /// Counts the rows the query returns ([CountMode.rows], the default). With
  /// `groupBy`, `having`, `union` or `distinct` (over the selected columns) it
  /// counts the rows of the whole query through a subquery, instead of the
  /// first group's count. Pass [CountMode.laravel] for Laravel's semantics.
  ///
  /// ```dart
  /// await db.table('t').groupBy('status').count();          // groups
  /// await db.table('t').groupBy('status')
  ///     .count('*', CountMode.laravel);                       // 1st group's rows
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
    final allColumns = columns.isEmpty || (columns.length == 1 && columns.first == '*');
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

  ///
  /// Retrieve the minimum value of a given column.
  ///
  ///
  Future<num?> min(String column) async {
    final result = await this.aggregate("min", [column]);
    return result is String ? num.tryParse(result) : result;
  }

  ///
  /// Retrieve the maximum value of a given column.
  ///
  ///
  Future<num?> max(String column) async {
    final result = await this.aggregate("max", [column]);
    return result is String ? num.tryParse(result) : result;
  }

  ///
  /// Retrieve the sum of the values of a given column.
  ///
  ///
  Future<num?> sum(String column) async {
    final result = await this.aggregate('sum', [column]);
    return result is String ? num.tryParse(result) : result;
  }

  ///
  /// Retrieve the average of the values of a given column.
  ///
  ///
  Future<num?> avg(String column) async {
    final result = await this.aggregate('avg', [column]);
    return result is String ? num.tryParse(result) : result;
  }

  ///
  /// Alias for the "avg" method.
  ///
  ///
  Future<num?> average(String column) async {
    return await this.avg(column);
  }

  ///
  /// Execute an aggregate function on the database.
  ///
  ///
  Future<dynamic> aggregate(String function,
      [List<String> columnsP = const <String>['*']]) async {
    this.aggregateProp = {'function': function, 'columns': columnsP};

    List<dynamic>? cols =
        this.columnsProp != null ? [...this.columnsProp!] : null;
    var previousColumns = cols;

    // We will also back up the select bindings since the select clause will be
    // removed when performing the aggregate function. Once the query is run
    // we will add the bindings back onto this query so they can get used.
    // ignore: unused_local_variable
    var previousSelectBindings = [...(this.bindings['select'] as List)];

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
      var result = Utils.map_change_key_case_sd(results[0]);
      return result['aggregate'];
    }
    return null;
  }

  /// Execute a numeric aggregate function on the database.
  ///
  /// [function] Can be "count", "sum", "avg", "min" or "max".
  /// [columns] List of columns (default ['*']).
  /// Returns a [num] value (int or double).
  Future<num> numericAggregate(String function,
      [List<String> columns = const ['*']]) async {
    // Calls aggregate method to get raw result
    final dynamic result = await this.aggregate(function, columns);
    // If no result, returns 0
    if (result == null) {
      return 0;
    }
    // If already int or double, returns directly
    if (result is int || result is double) {
      return result;
    }
    // Converts to string to check if it has decimal point
    final String resultStr = result.toString();
    // If no decimal point, parse as int
    if (!resultStr.contains('.')) {
      return int.tryParse(resultStr) ?? 0;
    }
    // Otherwise, convert to double
    return double.tryParse(resultStr) ?? 0.0;
  }

  ///
  /// Insert a new record into the database.
  ///
  /// [values]  values Map<String, dynamic>
  /// Return bool
  ///
  Future<dynamic> insert(Map<String, dynamic> values, [Duration? timeout]) {
    // Since every insert gets treated like a batch insert, we will make sure the
    // bindings are structured in a way that is convenient for building these
    // inserts statements by verifying the elements are actually an array.
    final conflict = this.onConflictProp;
    final returning = this.returningProp;

    if (conflict == null && returning == null) {
      final bindings =
          this.cleanBindings(values.values.toList(growable: false));
      final sql = this.grammar.compileInsert(this, values);
      // Once we have compiled the insert statement's SQL we can execute it on
      // the connection and return a result as a boolean success indicator as
      // that is the same type of result returned by the raw connection.
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
    return this.connection
        .insert(sql, this.cleanBindings(bindings), _timeoutSeconds(timeout));
  }

  /// Set an `ON CONFLICT` target for the next low-level [insert].
  ///
  /// Provide the conflict columns (`onConflict(['ano'])`) or a named
  /// constraint (`onConflict.constraint`). Chain [doUpdate] or [doNothing]
  /// to define the action. Example (eliminates the need for explicit locks):
  ///
  /// ```dart
  /// final rows = await db.table('processos_sequences')
  ///   .onConflict(['ano'])
  ///   .doUpdate({'last_id': db.raw('processos_sequences.last_id + 1')})
  ///   .returning(['last_id'])
  ///   .insert({'ano': 2026, 'last_id': 1});
  /// final seq = rows.first['last_id'];
  /// ```
  QueryBuilder onConflict([List<String> columns = const [], String? constraint]) {
    this.onConflictProp = OnConflictClause(
      columns: columns,
      constraint: constraint,
    );
    return this;
  }

  /// Turn a pending [onConflict] into `DO UPDATE SET ...`.
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

  /// Turn a pending [onConflict] into `DO NOTHING`.
  QueryBuilder doNothing() {
    final current = this.onConflictProp ?? const OnConflictClause();
    this.onConflictProp = current.copyWith(doNothing: true);
    return this;
  }

  /// Request a `RETURNING` clause on the next write (insert/update/delete/upsert).
  ///
  /// When set, the write returns the affected rows (a `List<Map>`), mirroring
  /// PL/pgSQL's `RETURNING ... INTO` — the returned column can be read in Dart.
  QueryBuilder returning([List<dynamic> columns = const ['*']]) {
    this.returningProp = columns.isEmpty ? ['*'] : columns;
    return this;
  }

  /// Insert records, ignoring rows that violate a unique/primary constraint.
  ///
  /// PostgreSQL/SQLite: `INSERT ... ON CONFLICT DO NOTHING`.
  /// MySQL: `INSERT IGNORE`.
  /// Returns the number of rows actually inserted.
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

  /// Insert or update records atomically (`UPSERT`).
  ///
  /// [values] is a single map or a list of maps (all must share the same keys).
  /// [uniqueBy] are the conflict-target columns.
  /// [update] are the columns to update on conflict; when omitted, every
  /// non-[uniqueBy] column is updated with the value that would have been
  /// inserted. Values in [update] may be [QueryExpression]s.
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

  /// Normalize a single map or list of maps into a list of row maps.
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

  ///
  /// Insert a new record and get the value of the primary key.
  ///
  ///
  Future<dynamic> insertGetId(Map<String, dynamic> keyValues,
      [String sequence = 'id']) async {
    final sql = this.grammar.compileInsertGetId(this, keyValues, sequence);
    final values = this.cleanBindings(keyValues.values.toList());
    return await this.processor.processInsertGetId(this, sql, values, sequence);
  }

  ///
  /// Update a record in the database.
  ///
  /// [keyValues] Map
  /// Return int
  ///
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
    final sql = 'insert into $table ($columnList) select * from unnest($arrays)';
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
        final text = value
            .toString()
            .replaceAll(r'\', r'\\')
            .replaceAll('"', r'\"');
        buffer.write('"$text"');
      }
    }
    buffer.write('}');
    return buffer.toString();
  }

  /// The next number of [column] in the rows of this query (its where
  /// clauses are the scope): `coalesce(max(column), start - 1) + 1`, e.g.
  /// `db.table('andamento').where('cod_processo', p).nextValue('cod_andamento')`.
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
      final key = '${query.fromProp}|$column|${query.grammar.compileWheres(query)}|'
          '${query.getBindings().join('|')}';
      await this.connection.select(
          'select pg_advisory_xact_lock(hashtextextended(?, 0))', [key], false);
    }
    final max = await query.max(column);
    return max == null ? start : max.toInt() + 1;
  }

  /// Laravel's updateFrom: an update whose joins become the `FROM` list of
  /// `update ... from ...` (PostgreSQL), their conditions part of the WHERE.
  /// [update] already compiles joins this way here (and as `update ... join`
  /// on MySQL), so both methods give the same SQL; only inner joins.
  Future<int> updateFrom(Map<String, dynamic> keyValues, [Duration? timeout]) =>
      this.update(keyValues, timeout);

  Future<int> update(Map<String, dynamic> keyValues, [Duration? timeout]) {
    final sql = this.grammar.compileUpdate(this, keyValues);
    // Each dialect orders CTE/join/SET/where bindings like its SQL.
    final bindings = this.grammar.prepareBindingsForUpdate(this, keyValues);
    return this.connection.update(
        sql, this.cleanBindings(bindings), _timeoutSeconds(timeout));
  }

  /// [Duration] → whole seconds for the driver (rounded up; null = default).
  static int? _timeoutSeconds(Duration? timeout) {
    if (timeout == null) return null;
    final ms = timeout.inMilliseconds;
    return ms <= 0 ? 0 : (ms + 999) ~/ 1000;
  }

  /// Insert or update a record matching the [attributes], and fill it with [values].
  ///
  /// If no record matches [attributes]:
  ///   -> executes insert(attributes + values).
  /// Else:
  ///   -> updates the first matching record.
  ///
  /// Returns `true` on success, `false` if fails (or no changes).
  Future<bool> updateOrInsert(
    Map<String, dynamic> attributes, [
    Map<String, dynamic> values = const {},
  ]) async {
    // 1. Checks if any record exists with provided attributes. The wheres are
    // added once and reused by the update below.
    this.where(attributes);
    final bool recordExists = await this.exists();

    if (!recordExists) {
      // 2. If not exists, executes insert
      final inserted = await this.insert({
        ...attributes,
        ...values,
      });

      // Insert return value can vary (bool, int, etc.),
      // depending on ConnectionInterface implementation. Adjust as needed:
      if (inserted is bool) {
        return inserted; // true or false
      } else if (inserted is num) {
        return inserted > 0; // if it is row count
      }
      return inserted != null; // simple fallback
    } else {
      // 3. If exists, updates only 1 record (nothing to update: done).
      if (values.isEmpty) return true;
      final int affectedRows = await this.limit(1).update(values);

      // 4. Converts number of affected rows to bool
      return affectedRows > 0;
    }
  }

  /// Increment a column's value by a given amount.
  ///
  /// [column] Name of the column to increment.
  /// [amount] Value to add to the column.
  /// [extra]  Additional values that can be updated in the same update.
  /// Returns the number of affected rows (usually int).
  Future<int> increment(String column,
      [num amount = 1, Map<String, dynamic> extra = const {}]) async {
    // 2. Wrap column name to ensure escaping (e.g. `"table"."column"`)
    final wrapped = this.grammar.wrap(column);
    // 3. Builds columns map, creating expression "<column> + <amount>"
    //    and merging with extra columns:
    final Map<String, dynamic> columnsToUpdate = {
      ...extra,
      column: this.raw('$wrapped + $amount'),
    };
    // 4. Calls update(...) passing calculated columns
    final int affected = await this.update(columnsToUpdate);
    // 5. Returns number of affected rows (depends on update implementation)
    return affected;
  }

  /// Decrement a column's value by a given amount.
  ///
  /// [column] Name of the column to decrement.
  /// [amount] Value to subtract from the column.
  /// [extra]  Additional values that can be updated in the same update.
  /// Returns the number of affected rows (usually int).
  Future<int> decrement(String column,
      [num amount = 1, Map<String, dynamic> extra = const {}]) async {
    // 2. Wrap column name to ensure escaping (e.g. `"table"."column"`)
    final wrapped = this.grammar.wrap(column);

    // 3. Builds columns map, creating expression "<column> - <amount>"
    //    and merging with extra columns:
    final Map<String, dynamic> columnsToUpdate = {
      ...extra,
      column: this.raw('$wrapped - $amount'),
    };

    // 4. Calls update(...) passing calculated columns
    final int affected = await this.update(columnsToUpdate);

    // 5. Returns number of affected rows (depends on update implementation)
    return affected;
  }

  ///
  /// Delete a record from the database.
  ///
  ///
  Future<int> delete([dynamic id, Duration? timeout]) {
    // If an ID is passed to the method, we will set the where clause to check
    // the ID to allow developers to simply and quickly remove a single row
    // from their database without manually specifying the where clauses.
    if (id != null) {
      this.where('id', SqlOperator.equals, id);
    }

    var sql = this.grammar.compileDelete(this);
    final bindings = this.grammar.prepareBindingsForDelete(this);

    return this.connection.delete(
        sql, this.cleanBindings(bindings), _timeoutSeconds(timeout));
  }

  ///
  /// Run a truncate statement on the table.
  ///
  ///
  Future<void> truncate() async {
    for (var entry in this.grammar.compileTruncate(this).entries) {
      final sql = entry.key;
      final bindings = entry.value;

      await this.connection.statement(sql, bindings);
    }
  }

  ///
  /// Get a new instance of the query builder.
  ///
  ///
  QueryBuilder newQuery() {
    return QueryBuilder(this.connection, this.grammar, this.processor);
  }

  ///
  /// Create a new query instance for a sub-query.
  ///
  ///
  QueryBuilder forSubQuery() {
    return this.newQuery();
  }

  ///
  /// Merge an array of where clauses and bindings.
  ///
  ///
  void mergeWheres(List<Map<String, dynamic>> wheresP, bindingsP) {
    // Merges WHERE clauses
    this.wheresProp.addAll(wheresP);
    // Merges bindings of type 'where'
    this.bindings['where'].addAll(bindingsP);
  }

  ///
  /// Remove all of the expressions from a list of bindings.
  ///
  ///
  List cleanBindings(List bindings) {
    for (final binding in bindings) {
      if (binding is QueryExpression) {
        return Utils.array_filter(bindings, (binding) {
          return !(binding is QueryExpression);
        });
      }
    }

    return bindings;
  }

  ///
  /// Create a raw database expression.
  ///
  ///
  QueryExpression raw(dynamic value) {
    return this.connection.raw(value);
  }

  ///
  /// Get the current query value bindings in a flattened array.
  ///
  ///
  List getBindings() {
    var result = <dynamic>[]; // Use typed list

    // 1. Adds CTE bindings ('expressions') FIRST
    if (bindings['expressions'] is List &&
        bindings['expressions']!.isNotEmpty) {
      result.addAll(bindings['expressions']!);
    }

    if (this.bindings['select'] != null) {
      result.addAll(this.bindings['select']);
    }
    if (bindings['from'] is List && bindings['from']!.isNotEmpty) {
      // Added for 'fromRaw'
      result.addAll(bindings['from']!);
    }
    if (this.bindings['join'] != null) {
      result.addAll(this.bindings['join']);
    }
    if (this.bindings['where'] != null) {
      result.addAll(this.bindings['where']);
    }
    if (this.bindings['groupBy'] != null) {
      result.addAll(this.bindings['groupBy']);
    }
    if (this.bindings['having'] != null) {
      result.addAll(this.bindings['having']);
    }
    if (this.bindings['order'] != null) {
      result.addAll(this.bindings['order']);
    }
    if (this.bindings['union'] != null) {
      result.addAll(this.bindings['union']);
    }
    if (this.bindings['unionOrder'] != null) {
      result.addAll(this.bindings['unionOrder']);
    }

    return result;
  }

  ///
  /// Get the raw array of bindings.
  ///
  ///
  Map<String, dynamic> getRawBindings() {
    return this.bindings;
  }

  ///
  /// Set the bindings on the query builder.
  ///
  ///
  ///
  QueryBuilder setBindings(Map<String, dynamic> bindingsP, [type = 'where']) {
    if (!bindings.containsKey(type)) {
      throw ArgumentError.value(type, 'type', 'Invalid binding type.');
    }
    bindings[type] = bindingsP;
    return this;
  }

  ///
  /// Add a binding to the query.
  ///
  /// [value]  dynamic
  /// [type]  String
  ///
  ///
  QueryBuilder addBinding(dynamic value, [String type = 'where']) {
    if (!this.bindings.containsKey(type)) {
      throw ArgumentError.value(type, 'type', 'Invalid binding type.');
    }

    final target = this.bindings[type];
    if (value is List) {
      target.addAll(value);
    } else {
      target.add(value);
    }

    return this;
  }

  ///
  /// Merge an array of bindings into our bindings.
  ///
  ///
  QueryBuilder mergeBindings(QueryBuilder query) {
    query.bindings.forEach((key, value) {
      bindings.putIfAbsent(key, () => []).addAll(value);
    });
    return this;
  }

  ///
  /// Get the database connection instance.
  ///
  ///
  ConnectionInterface getConnection() {
    return this.connection;
  }

  ///
  /// Get the database query processor instance.
  ///
  ///
  Processor getProcessor() {
    return this.processor;
  }

  ///
  /// Get the query grammar instance.
  ///
  ///
  QueryGrammar getGrammar() {
    return this.grammar;
  }

  ///
  /// Use the write pdo for query.
  ///
  ///
  QueryBuilder useWritePdo() {
    this.useWritePdoProp = true;
    return this;
  }

  /// Adds an INNER JOIN LATERAL to the query.
  ///
  /// [subquery] can be a QueryBuilder, a Closure (Function) or a raw SQL String.
  /// [alias] is the mandatory alias for the lateral subquery.
  /// [onCallback] is a function receiving a JoinClause to define ON conditions.
  /// Often for LATERAL JOIN, the condition is `ON TRUE`.
  QueryBuilder joinLateral(
      dynamic subquery, String alias, Function(JoinClause) onCallback) {
    return _addLateralJoin(SqlJoin.inner, subquery, alias, onCallback);
  }

  /// Adds a LEFT JOIN LATERAL to the query.
  ///
  /// [subquery] can be a QueryBuilder, a Closure (Function) or a raw SQL String.
  /// [alias] is the mandatory alias for the lateral subquery.
  /// [onCallback] is a function receiving a JoinClause to define ON conditions.
  /// Often for LATERAL JOIN, the condition is `ON TRUE`.
  QueryBuilder leftJoinLateral(
      dynamic subquery, String alias, Function(JoinClause) onCallback) {
    return _addLateralJoin(SqlJoin.left, subquery, alias, onCallback);
  }

  /// Helper method to add lateral joins.
  QueryBuilder _addLateralJoin(String type, dynamic subquery, String alias,
      Function(JoinClause) onCallback) {
    // Creates subquery and gets SQL + bindings
    final res = createSub(subquery);

    final sql = res[0];
    final bindings = res[1];

    // Creates expression for subquery ( "(subquery) as alias" )
    final expression = QueryExpression('($sql) as ${grammar.wrapTable(alias)}');

    // Adds subquery bindings to 'join' type
    addBinding(bindings, 'join');

    // Creates JoinClause, marking as lateral
    final join = JoinClause(type, expression, this, true);

    // Applies ON conditions using provided callback
    onCallback(join);

    // Adds configured JoinClause to main query joins list
    joinsProp.add(join);

    // Adds ON clause bindings to 'join' type
    addBinding(join.bindingsLocal, 'join');

    return this;
  }

  /// Adds a JOIN with raw "table/expression" (no wrap) and optionally
  /// allows declaring ON conditions via callback.
  ///
  /// Examples:
  ///   // Simple JOIN, no ON (useful with ON TRUE or NATURAL, etc.)
  ///   qb.joinRaw('(select * from foo) as f');
  QueryBuilder joinRaw(
    String tableExpression, [
    List bindings = const [],
    String type = SqlJoin.inner,
    Function(JoinClause)? on,
  ]) {
    // Keeps raw expression, no wrap/escape
    final tableExpr = QueryExpression(tableExpression);

    // Creates JoinClause and pushes to query
    final join = JoinClause(type, tableExpr, this);
    this.joinsProp.add(join);

    // Bindings associated with join "table"/expression
    if (bindings.isNotEmpty) {
      this.addBinding(bindings, 'join');
    }

    // Allows configuring ON via callback (including onRaw)
    if (on != null) {
      on(join);
      if (join.bindingsLocal.isNotEmpty) {
        this.addBinding(join.bindingsLocal, 'join');
      }
    }

    return this;
  }

  /// Executes an optimized "batch insert", generating a single SQL statement
  /// with multiple values. Ex: INSERT INTO table (...) VALUES (...), (...), (...)
  ///
  /// [values] is a list of maps, where each map represents a row to be inserted.
  ///
  /// **Important:** All maps in the list must have exactly the same keys.
  /// Point of Attention: The Parameter Limit (Bind Limit)
  /// SQLite: The old default was 999 variables. Modern versions allow more, but there are still limits.
  /// PostgreSQL: The protocol supports up to ~65,535 parameters (2 bytes unsigned integer).
  /// SQL Server: Around 2,100 parameters.
  Future<dynamic> insertMany(List<Map<String, dynamic>> values) async {
    // 1. If list is empty, nothing to do.
    if (values.isEmpty) {
      return;
    }
    // 2. Gets table name from QueryBuilder.
    final table = grammar.wrapTable(fromProp);
    // 3. Gets column names from first item in list.
    //    Assumes all maps have same keys.
    final columns = values.first.keys.toList();
    final columnsSql = grammar.columnize(columns);
    // 4. Prepares placeholders string (?, ?, ?) for a single row.
    final singleRowPlaceholders =
        '(${List.filled(columns.length, '?').join(', ')})';
    // 5. Creates placeholders string for all rows, comma separated.
    //    Ex: (?, ?), (?, ?), (?, ?)
    final allPlaceholders =
        List.filled(values.length, singleRowPlaceholders).join(', ');
    // 6. Builds final SQL statement.
    final sql = 'INSERT INTO $table ($columnsSql) VALUES $allPlaceholders';
    // 7. Flattens map list into single values list for bindings,
    //    ensuring values order corresponds to columns order.
    final bindings = <dynamic>[];
    for (final row in values) {
      for (final column in columns) {
        bindings.add(row[column]);
      }
    }
    // 8. Executes insertion using QueryBuilder connection.
    //    Connection `insert` method executes raw query.
    await connection.insert(sql, bindings);
  }

  ///
  /// Clone the query without the given properties.
  ///
  ///
  /// `update ... set a = a + 1, b = b + 2` for several columns at once.
  Future<int> incrementEach(Map<String, num> columns,
      [Map<String, dynamic> extra = const {}]) {
    return this.update({
      for (final entry in columns.entries)
        entry.key: QueryExpression(
            '${this.grammar.wrap(entry.key)} + ${entry.value}'),
      ...extra,
    });
  }

  /// `update ... set a = a - 1, b = b - 2` for several columns at once.
  Future<int> decrementEach(Map<String, num> columns,
      [Map<String, dynamic> extra = const {}]) {
    return this.update({
      for (final entry in columns.entries)
        entry.key: QueryExpression(
            '${this.grammar.wrap(entry.key)} - ${entry.value}'),
      ...extra,
    });
  }

  /// The SQL with its bindings inlined, for logs and debugging only (never
  /// execute it: escaping is best-effort, dialect-aware).
  String toRawSql() {
    final bindings = this.connection.prepareBindings(
        List<dynamic>.of(this.cleanBindings(this.getBindings())));
    return this.grammar.substituteBindingsIntoRawSql(
        this.toSql(), List<dynamic>.of(bindings as List));
  }

  /// Prints [toRawSql] and returns the builder.
  QueryBuilder dumpRawSql() {
    print(this.toRawSql());
    return this;
  }

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

    newQuery.aggregateProp =
        aggregateProp != null ? Map<String, dynamic>.from(aggregateProp!) : null;
    newQuery.useWritePdoProp = useWritePdoProp;
    // OnConflictClause is immutable.
    newQuery.onConflictProp = onConflictProp;
    newQuery.returningProp =
        returningProp != null ? [...returningProp!] : null;
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

  ///
  /// Handle dynamic method calls into the method.
  /// equivalent to __call
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
          return Function.apply(where, positionalArguments[0]);
        } else if (positionalArguments.length == 2) {
          return where(positionalArguments[0], positionalArguments[1]);
        } else if (positionalArguments.length == 3) {
          return where(positionalArguments[0], positionalArguments[1],
              positionalArguments[2]);
        } else if (positionalArguments.length == 4) {
          return where(positionalArguments[0], positionalArguments[1],
              positionalArguments[2], positionalArguments[3]);
        }
        break;
      default:
        throw Exception("method '$methodName' not exist in QueryBuilder class");
    }
  }
}
