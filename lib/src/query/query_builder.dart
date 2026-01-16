import 'dart:async';

import 'package:eloquent/src/connection.dart';
import 'package:eloquent/src/connection_interface.dart';
import 'package:eloquent/src/contracts/pagination/default_length_aware_paginator.dart';
import 'package:eloquent/src/contracts/pagination/default_paginator.dart';
import 'package:eloquent/src/contracts/pagination/length_aware_paginator.dart';
import 'package:eloquent/src/contracts/pagination/pagination_utils.dart';

import 'package:eloquent/src/query/expression.dart';
import 'package:eloquent/src/query/grammars/query_grammar.dart';
import 'package:eloquent/src/query/join_clause.dart';
import 'package:eloquent/src/query/processors/processor.dart';
import 'package:eloquent/src/support/arr.dart';
import 'package:eloquent/src/utils/utils.dart';

import '../exceptions/invalid_argument_exception.dart';

class QueryBuilder {
  /**
     * The common table expressions.
     *
     * @var array
     */
  List<Map<String, dynamic>> expressionsProp = [];

  /**
     * The recursion limit.
     *
     * @var int
     */
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
        print('QueryBuilder@getProperty propertyName');
        return propertyName;
    }
    // return propertyName;
  }

  ///
  /// The database connection instance.
  ///
  /// @var \Illuminate\Database\Connection
  ///
  late ConnectionInterface connection;

  ///
  /// The database query grammar instance.
  ///
  /// @var \Illuminate\Database\Query\Grammars\Grammar
  ///
  late QueryGrammar grammar;

  ///
  /// The database query post processor instance.
  ///
  /// @var \Illuminate\Database\Query\Processors\Processor
  ///
  late Processor processor;

  ///
  /// The current query value bindings.
  ///
  /// @var array
  ///
  Map<String, dynamic> bindings = {
    'select': [],
    'from': [],
    'join': [],
    'where': [],
    'having': [],
    'order': [],
    'union': [],
    'expressions': [],
  };

  ///
  /// An aggregate function and column to be run.
  ///
  /// @var array
  ///
  Map<String, dynamic>? aggregateProp;

  ///
  /// The columns that should be returned.
  /// Property of the QueryBuilder class that stores the columns of the table to be returned
  /// @var array
  ///
  List<dynamic>? columnsProp;

  List<dynamic>? getColumns() {
    return columnsProp;
  }

  void setColumns(List<dynamic>? cols) {
    columnsProp = cols;
  }

  ///
  /// Indicates if the query returns distinct results.
  ///
  /// @var bool
  ///
  bool distinctProp = false;

  ///
  /// The table which the query is targeting.
  ///
  /// @var string | QueryExpression
  ///
  dynamic fromProp;

  ///
  /// The table joins for the query.
  ///
  /// @var array
  ///
  List<JoinClause> joinsProp = [];

  ///
  /// The where constraints for the query.
  ///
  /// @var array
  ///
  List<Map<String, dynamic>> wheresProp = [];

  ///
  /// The groupings for the query.
  ///
  /// @var array
  ///
  List groupsProp = [];

  ///
  /// The having constraints for the query.
  ///
  /// @var array
  ///
  List<Map<String, dynamic>> havingsProp = [];

  ///
  /// The orderings for the query.
  ///
  /// @var array
  ///
  List<Map<String, dynamic>> ordersProp = [];

  ///
  /// The maximum number of records to return.
  ///
  /// @var int
  ///
  int? limitProp;

  ///
  /// The number of records to skip.
  ///
  /// @var int
  ///
  int? offsetProp;

  ///
  /// The query union statements.
  ///
  /// @var array
  ///
  List<Map<String, dynamic>> unionsProp = [];

  ///
  /// The maximum number of union records to return.
  ///
  /// @var int
  ///
  int? unionLimit;

  ///
  /// The number of union records to skip.
  ///
  /// @var int
  ///
  int? unionOffset;

  ///
  /// The orderings for the union query.
  ///
  /// @var array
  ///
  List<Map<String, dynamic>> unionOrdersProp = [];

  ///
  /// Indicates whether row locking is being used.
  ///
  /// @var string|bool
  ///
  dynamic lockProp;

  ///
  /// The field backups currently in use.
  ///
  /// @var array
  ///
  Map<String, dynamic> backups = {}; // Para orders, limit, offset, columns

  ///
  /// The binding backups currently in use.
  ///
  /// @var array
  ///
  Map<String, dynamic> bindingBackups = {}; // Para as chaves 'order' e 'select'

  ///
  /// All of the available clause operators.
  ///
  /// @var array
  ///
  List _operators = [
    '=',
    '<',
    '>',
    '<=',
    '>=',
    '<>',
    '!=',
    'in',
    'like',
    'like binary',
    'not like',
    'between',
    'ilike',
    '&',
    '|',
    '^',
    '<<',
    '>>',
    'rlike',
    'regexp',
    'not regexp',
    '~',
    '~///',
    '!~',
    '!~///',
    'similar to',
    'not similar to'
  ];

  ///
  /// Whether use write pdo for select.
  ///
  /// @var bool
  ///
  bool useWritePdoProp = false;

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
  QueryBuilder select([dynamic columnsP = const ['*']]) {
    if (columnsP is List) {
      this.columnsProp = columnsP;
    } else if (columnsP != null) {
      this.columnsProp = [columnsP];
    } else {
      this.columnsProp = const ['*'];
    }
    return this;
  }

  /// Add a subselect expression to the query.
  ///
  /// [query] `Function`|`QueryBuilder`|`String` The subquery.
  /// [alias] The alias for the subquery.
  /// Returns the QueryBuilder instance.
  QueryBuilder selectSub(dynamic query, String alias) {
    // var bindings;
    // if (query is Function) {
    //   var callback = query;
    //   callback(query = this.newQuery());
    // }

    // if (query is QueryBuilder) {
    //   bindings = query.getBindings();
    //   query = query.toSql();
    // } else if (Utils.is_string(query)) {
    //   bindings = [];
    // } else {
    //   throw InvalidArgumentException();
    // }

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
  /// [$bindings] The bindings for the expression.
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
  QueryBuilder fromRaw(String expression, [List? $bindings = const []]) {
    this.fromProp = QueryExpression(expression);
    this.addBinding($bindings, 'from');
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
      throw InvalidArgumentException();
    }
  }

  /// Add a new select column to the query.
  ///
  /// [columnP] `QueryExpression`|`List`|`dynamic` The column(s) to add.
  /// Returns the QueryBuilder instance.
  QueryBuilder addSelect(dynamic columnP) {
    //var column = is_array(column) ? column : func_get_args();
    var col = columnP is List ? columnP : [columnP];
    this.columnsProp = Utils.array_merge(columnsProp, col);
    return this;
  }

  /// Force the query to only return distinct results.
  ///
  /// Returns the QueryBuilder instance.
  QueryBuilder distinct() {
    this.distinctProp = true;

    return this;
  }

  /// Set the table which the query is targeting.
  ///
  /// [tableP] `QueryExpression`|`String` The table to target.
  /// Returns the QueryBuilder instance.
  QueryBuilder from(dynamic tableP) {
    this.fromProp = tableP;
    return this;
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
      String type = 'inner',
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
      this.joinsProp.add(join.on(one, operator, two, 'and', where));
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
  QueryBuilder joinWhere(String table, one, operator, two, [type = 'inner']) {
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
      [String? operator, dynamic second, type = 'inner', where = false]) {
    final res = this.createSub(query);

    final newQuery = res[0];
    final bindings = res[1];

    final expression = '(' + newQuery + ') as ' + this.grammar.wrap(alias);

    this.addBinding(bindings, 'join');

    return this.join(
        QueryExpression(expression), first, operator, second, type, where);
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
    return this.join(table, first, operator, second, 'left');
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
    return this.joinWhere(table, one, operator, two, 'left');
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
    return this.join(table, first, operator, second, 'right');
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
    return this.joinWhere(table, one, operator, two, 'right');
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
      return this.join(table, first, operator, second, 'cross');
    }
    // Otherwise, adds a JoinClause of type 'cross' without ON clause
    this.joinsProp.add(JoinClause('cross', table, this));
    return this;
  }

  /// Apply the [callback] only if [condition] is true.
  /// Returns the QueryBuilder itself for chaining (fluent interface).
  QueryBuilder when(dynamic condition, Function(QueryBuilder) callback) {
    // If condition is "truthy" (not null/false/0/''), calls the callback
    if (condition != null && condition != false) {
      callback(this);
    }
    return this;
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
  QueryBuilder where(dynamic column,
      [String? operator, dynamic value, String boolean = 'and']) {
    // If the column is an array, we will assume it is an array of key-value pairs
    // and can add them each as a where clause. We will maintain the boolean we
    // received when the method was called and pass it into the nested where.
    if (column is Map) {
      return this.whereNested((query) {
        for (var entry in column.entries) {
          query.where(entry.key, '=', entry.value);
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
    if (value is Function) {
      return this.whereSub(column, operator, value, boolean);
    }

    // If the value is "null", we will just assume the developer wants to add a
    // where null clause to the query. So, we will allow a short-cut here to
    // that method for convenience so the developer doesn't have to check.
    if (value == null) {
      return this.whereNull(column, boolean, operator != '=');
    }

    // Now that we are working with just a simple query we can put the elements
    // in our array and add the query binding to our array of bindings that
    // will be bound to each SQL statements when it is finally executed.
    final type = 'Basic';

    this.wheresProp.add({
      'type': type,
      'column': column,
      'operator': operator,
      'value': value,
      'boolean': boolean
    });

    if (!(value is QueryExpression)) {
      this.addBinding(value, 'where');
    }

    return this;
  }

  QueryBuilder orWhere(dynamic column, [String? operator, dynamic value]) {
    return this.where(column, operator, value, 'or');
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
  ///   it is expected to throw an exception (InvalidArgumentException).
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
      String boolean = 'and']) {
    // Case 1: Map
    if (column is Map) {
      return this.whereNested((query) {
        column.forEach((k, v) {
          query.where(k, '=', v);
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
          throw InvalidArgumentException(
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
          finalOperator = '='; // Implicit operator
          finalValue = operator; // The second argument was the value
        }
      }
    } else {
      // Scenario where('column') - Second argument (operator) is null.
      // Treat as where('column', '=', null), which will be caught by the null logic below.
      finalOperator = '=';
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
      bool not = (finalOperator == '!=' || finalOperator == '<>');
      if (finalOperator == '=' || finalOperator == '==' || not) {
        return this.whereNull(column, boolean, not);
      }
      // If not an (in)equality operator, the validation below MUST fail.
    }

    // Final validation: Checks for illegal combinations
    if (this.invalidOperatorAndValue(finalOperator, finalValue)) {
      // If this validation fails, it means the logic above did not handle
      // correctly or the user provided an invalid combination (e.g., '>', null)
      throw InvalidArgumentException(
          'Illegal operator "$finalOperator" and value combination ($finalValue). Operator must be "=" or "!=" or "<>" if value is null.');
    }

    // Case 5: Basic WHERE Clause
    final type = 'Basic';
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
    return this.whereFlex(column, operator, value, 'or');
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
      bool isValidNullOp = (operator == '=' ||
          operator == '==' ||
          operator == '!=' ||
          operator == '<>');
      return !isValidNullOp;
    }
    return false;
  }

  QueryBuilder whereSubQueryValue(String column, Function(QueryBuilder) closure,
      [String boolean = 'and']) {
    return this.where(column, '=', closure, boolean);
  }

  /// Add a "where" clause comparing two columns to the query.
  ///
  /// [first] `String`|`List`|`Map` The first column or array of conditions.
  /// [operator] `String`|`null` The operator.
  /// [second] `String`|`null` The second column.
  /// [boolean] `String` The boolean connector.
  /// Returns the QueryBuilder instance.
  QueryBuilder whereColumn(dynamic first,
      [String? operator, dynamic second, String boolean = 'and']) {
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
        !(Utils.in_array(operator.toLowerCase(), this._operators) ||
            Utils.in_array(
                operator.toLowerCase(), this.grammar.getOperators()))) {
      second = operator;
      operator = '=';
    }

    // Sets the 'where' clause type to 'Column'
    var type = 'Column';

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
    return this.whereColumn(first, operator, second, 'or');
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
            if (method == 'where') {
              Function.apply(query.where, value);
            } else if (method == 'orWhere') {
              Function.apply(query.orWhere, value);
            } else {
              // If the method is not recognized, defaults to 'where' method.
              Function.apply(query.where, value);
            }
          } else {
            // Otherwise, treats the key as column name and the value as the value to be compared.
            query.where(key, '=', value);
          }
        });
      }
      // If "column" is a list, iterates over each item
      else if (column is List) {
        for (var item in column) {
          if (item is List) {
            if (method == 'where') {
              Function.apply(query.where, item);
            } else if (method == 'orWhere') {
              Function.apply(query.orWhere, item);
            } else {
              Function.apply(query.where, item);
            }
          } else if (item is Map) {
            // If the item is a map, iterates over each key and value
            item.forEach((key, value) {
              query.where(key, '=', value);
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
  QueryBuilder whereRaw(String sql,
      [List bindings = const [], boolean = 'and']) {
    final type = 'raw';
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
    return this.whereRaw(sql, bindings, 'or');
  }

  /// Add a where between statement to the query.
  ///
  /// [column] `String` The column.
  /// [values] `List` The values.
  /// [boolean] `String` The boolean connector.
  /// [not] `bool` Whether it is a NOT BETWEEN.
  /// Returns the QueryBuilder instance.
  QueryBuilder whereBetween(String column,
      [List? values, String boolean = 'and', bool not = false]) {
    final type = 'between';

    this
        .wheresProp
        .add({'column': column, 'type': type, 'boolean': boolean, 'not': not});

    this.addBinding(values, 'where');

    return this;
  }

  ///
  /// Add an or where between statement to the query.
  ///
  /// @param  String  $column
  /// @param  array   $values
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder orWhereBetween(String column, List values) {
    return this.whereBetween(column, values, 'or');
  }

  /// Add a where not between statement to the query.
  ///
  /// [column] `String` The column.
  /// [values] `List` The values.
  /// [boolean] `String` The boolean connector.
  /// Returns the QueryBuilder instance.
  QueryBuilder whereNotBetween(column, List values, [boolean = 'and']) {
    return this.whereBetween(column, values, boolean, true);
  }

  /// Add an or where not between statement to the query.
  ///
  /// [column] `String` The column.
  /// [values] `List` The values.
  /// Returns the QueryBuilder instance.
  QueryBuilder orWhereNotBetween(String column, List values) {
    return this.whereNotBetween(column, values, 'or');
  }

  /// Add a nested where statement to the query.
  ///
  /// [callback] `Function` The callback for the nested query.
  /// [boolean] `String` The boolean connector.
  /// Returns the QueryBuilder instance.
  QueryBuilder whereNested(Function callback, [String boolean = 'and']) {
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
  QueryBuilder addNestedWhereQuery(QueryBuilder query, [boolean = 'and']) {
    if (Utils.count(query.wheresProp) != 0) {
      var type = 'Nested';

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
    var type = 'Sub';

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
    final type = 'Sub';
    final query = this.forSubQuery(); // Use forSubQuery for consistency
    callback(query);

    // Ensures a default operator if it is null, although previous logic should prevent this
    operator ??= '=';

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
  QueryBuilder whereExists(Function callback,
      [String boolean = 'and', not = false]) {
    var type = not ? 'NotExists' : 'Exists';

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
  QueryBuilder orWhereExists(Function callback, [bool not = false]) {
    return this.whereExists(callback, 'or', not);
  }

  /// Add a where not exists clause to the query.
  ///
  /// [callback] `Function` The callback.
  /// [boolean] `String` The boolean connector.
  /// Returns the QueryBuilder instance.
  QueryBuilder whereNotExists(Function callback, [String boolean = 'and']) {
    return this.whereExists(callback, boolean, true);
  }

  /// Add an or where not exists clause to the query.
  ///
  /// [callback] `Function` The callback.
  /// Returns the QueryBuilder instance.
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
      [String boolean = 'and', bool not = false]) {
    var type = not ? 'NotIn' : 'In';

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

    // if (values is Arrayable) {
    //     $values = $values->toArray();
    // }

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
    return this.whereIn(column, values, 'or');
  }

  /// Add a "where not in" clause to the query.
  ///
  /// [column] `String` The column.
  /// [values] `dynamic` The values.
  /// [boolean] `String` The boolean connector.
  /// Returns the QueryBuilder instance.
  QueryBuilder whereNotIn(String column, values, [boolean = 'and']) {
    return this.whereIn(column, values, boolean, true);
  }

  /// Add an "or where not in" clause to the query.
  ///
  /// [column] `String` The column.
  /// [values] `dynamic` The values.
  /// Returns the QueryBuilder instance.
  QueryBuilder orWhereNotIn(column, values) {
    return this.whereNotIn(column, values, 'or');
  }

  ///
  /// Add a where in with a sub-select to the query.
  ///
  /// @param  String   $column
  /// @param  \Closure $callback
  /// @param  String   $boolean
  /// @param  bool     $not
  /// @return $this
  ///
  QueryBuilder whereInSub(
      String column, Function callback, String boolean, bool not) {
    final type = not ? 'NotInSub' : 'InSub';

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
  /// @param  String   $column
  /// @param  \Illuminate\Database\Query\Builder|static  $query
  /// @param  String   $boolean
  /// @param  bool     $not
  /// @return $this
  ///
  QueryBuilder whereInExistingQuery(
      String column, QueryBuilder query, String boolean, bool not) {
    var type = not ? 'NotInSub' : 'InSub';

    this.wheresProp.add(
        {'type': type, 'column': column, 'query': query, 'boolean': boolean});

    this.addBinding(query.getBindings(), 'where');

    return this;
  }

  ///
  /// Add a "where null" clause to the query.
  ///
  /// @param  String  $column
  /// @param  String  $boolean
  /// @param  bool    $not
  /// @return $this
  ///
  QueryBuilder whereNull(String column,
      [String boolean = 'and', bool not = false]) {
    var type = not ? 'NotNull' : 'Null';

    this.wheresProp.add({'type': type, 'column': column, 'boolean': boolean});

    return this;
  }

  ///
  /// Add an "or where null" clause to the query.
  ///
  /// @param  String  $column
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder orWhereNull(String column) {
    return this.whereNull(column, 'or');
  }

  ///
  /// Add a "where not null" clause to the query.
  ///
  /// @param  String  $column
  /// @param  String  $boolean
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder whereNotNull(String column, [String boolean = 'and']) {
    return this.whereNull(column, boolean, true);
  }

  ///
  /// Add an "or where not null" clause to the query.
  ///
  /// @param  String  $column
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder orWhereNotNull(String column) {
    return this.whereNotNull(column, 'or');
  }

  ///
  /// Add a "where date" statement to the query.
  ///
  /// @param  String  $column
  /// @param  String   $operator
  /// @param   DateTime?  $value
  /// @param  String   $boolean
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder whereDate(String column, String? operator, DateTime? value,
      [String boolean = 'and']) {
    return this.addDateBasedWhere('Date', column, operator, value, boolean);
  }

  /// Add an "or where date" statement to the query.
  /// Basic: `orWhereDate('created_at', '=', someDate)`
  QueryBuilder orWhereDate(String column, String operator, DateTime? value) {
    return this.whereDate(column, operator, value, 'or');
  }

  /// Add a "where time" statement to the query.
  /// [column] Ex: 'created_at'
  /// [operator] Ex: '=', '<', '>'
  /// [value] Ex: '12:00:00' or a DateTime whose time matters
  /// [boolean] Whether it is 'and' or 'or'
  QueryBuilder whereTime(String column, String operator, dynamic value,
      [String boolean = 'and']) {
    // Assuming addDateBasedWhere('Time', ...) truncates/compares only the time part
    return this.addDateBasedWhere('Time', column, operator, value, boolean);
  }

  /// Add an "or where time" statement to the query.
  QueryBuilder orWhereTime(String column, String operator, dynamic value) {
    return this.whereTime(column, operator, value, 'or');
  }

  ///
  /// Add a "where day" statement to the query.
  ///
  /// @param  String  $column
  /// @param  String   $operator
  /// @param  int   $value
  /// @param  String   $boolean
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder whereDay(String column, String operator, int value,
      [String boolean = 'and']) {
    return this.addDateBasedWhere('Day', column, operator, value, boolean);
  }

  ///
  /// Add a "where month" statement to the query.
  ///
  /// @param  String  $column
  /// @param  String   $operator
  /// @param  int   $value
  /// @param  String   $boolean
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder whereMonth(String column, String operator, int value,
      [String boolean = 'and']) {
    return this.addDateBasedWhere('Month', column, operator, value, boolean);
  }

  ///
  /// Add a "where year" statement to the query.
  ///
  /// @param  String  $column
  /// @param  String   $operator
  /// @param  int   $value
  /// @param  String   $boolean
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder whereYear(String column, String operator, int value,
      [String boolean = 'and']) {
    return this.addDateBasedWhere('Year', column, operator, value, boolean);
  }

  ///
  /// Add a date based (year, month, day) statement to the query.
  ///
  /// @param  String  $type
  /// @param  String  $column
  /// @param  String  $operator
  /// @param  dynamic  $value
  /// @param  String  $boolean
  /// @return $this
  ///
  QueryBuilder addDateBasedWhere(
      String type, String column, String? operator, dynamic value,
      [String boolean = 'and']) {
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
  /// @param  String  $method
  /// @param  String  $parameters
  /// @return $this
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

    String connector = 'and';
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
  /// @param  String  $segment
  /// @param  String  $connector
  /// @param  array   $parameters
  /// @param  int     $index
  /// @return void
  ///
  void addDynamic(
      String segment, String connector, List<dynamic> parameters, int index) {
    // Converts the segment from CamelCase to snake_case.
    final column = Utils.toSnakeCase(segment);
    // Adds the where clause using the "=" operator.
    // Here it is assumed that the where method is already implemented in the class.
    where(column, '=', parameters[index], connector);
  }

  ///
  /// Add a "group by" clause to the query.
  ///
  /// @param  array|string  $column,...
  /// @return $this
  ///
  QueryBuilder groupBy(dynamic column) {
    // for(func_get_args() as $arg) {
    //     this.groupsProp = array_merge((array) this.groupsProp, is_array($arg) ? $arg : [$arg]);
    // }
    if (Utils.is_array(column)) {
      this.groupsProp = Utils.array_merge(this.groupsProp, column);
    } else if (Utils.is_string(column)) {
      this.groupsProp = Utils.array_merge(this.groupsProp, [column]);
    }

    return this;
  }

  ///
  /// Add a "having" clause to the query.
  ///
  /// @param  String  $column
  /// @param  String  $operator
  /// @param  String  $value
  /// @param  String  $boolean
  /// @return $this
  ///
  QueryBuilder having(dynamic column,
      [String? operator, dynamic value, String boolean = 'and']) {
    var type = 'basic';

    this.havingsProp.add({
      'type': type,
      'column': column,
      'operator': operator,
      'value': value,
      'boolean': boolean
    });

    if (!(value is QueryExpression)) {
      this.addBinding(value, 'having');
    }

    return this;
  }

  ///
  /// Add a "or having" clause to the query.
  ///
  /// @param  String  $column
  /// @param  String  $operator
  /// @param  String  $value
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder orHaving(String column, [String? operator, dynamic value]) {
    return this.having(column, operator, value, 'or');
  }

  /// Add a raw "having" clause to the query.
  ///
  /// [sql] is the raw SQL expression.
  /// [bindings] are the values to be bound to the query.
  /// [boolean] indicates the logical connector of the clause (default is "and").
  /// Returns the current QueryBuilder instance for chaining.
  QueryBuilder havingRaw(String sql,
      [List bindings = const [], String boolean = 'and']) {
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
    return this.havingRaw(sql, bindings, 'or');
  }

  ///
  /// Add an "order by" clause to the query.
  ///
  /// @param  String  $column
  /// @param  String  $direction
  /// @return $this
  ///
  QueryBuilder orderBy(String column, [String direction = 'asc']) {
    //var property = this.unions.isNotEmpty ? 'unionOrders' : 'orders';
    var _direction = Utils.strtolower(direction) == 'asc' ? 'asc' : 'desc';

    //this.{$property}[] = compact('column', 'direction');
    var map = {'column': column, 'direction': _direction};
    if (this.unionsProp.isNotEmpty) {
      this.unionOrdersProp.add(map);
    } else {
      this.ordersProp.add(map);
    }

    return this;
  }

  ///
  /// Add an "order by" clause for a timestamp to the query.
  ///
  /// @param  String  $column
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder latest([String column = 'created_at']) {
    return this.orderBy(column, 'desc');
  }

  ///
  /// Add an "order by" clause for a timestamp to the query.
  ///
  /// @param  String  $column
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder oldest([String column = 'created_at']) {
    return this.orderBy(column, 'asc');
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
  /// @param  String  $sql
  /// @param  array  $bindings
  /// @return $this
  ///
  QueryBuilder orderByRaw(String sql, [bindings = const []]) {
    // $property = this.unions ? 'unionOrders' : 'orders';
    var type = 'raw';
    // this.{$property}[] = compact('type', 'sql');
    var map = {'type': type, 'sql': sql};
    if (this.unionsProp.isNotEmpty) {
      this.unionOrdersProp.add(map);
    } else {
      this.ordersProp.add(map);
    }

    this.addBinding(bindings, 'order');

    return this;
  }

  ///
  /// Set the "offset" value of the query.
  ///
  /// @param  int  $value
  /// @return $this
  ///
  QueryBuilder offset(int value) {
    // $property = this.unions ? 'unionOffset' : 'offset';

    //this.$property = max(0, $value);
    var v = Utils.int_max(0, value);
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
  /// @param  int  $value
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder skip(int value) {
    return this.offset(value);
  }

  ///
  /// Set the "limit" value of the query.
  ///
  /// @param  int  $value
  /// @return $this
  ///
  QueryBuilder limit(int value) {
    //$property = this.unions ? 'unionLimit' : 'limit';

    if (value >= 0) {
      //this.$property = $value;

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
  /// @param  int  $value
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder take(int value) {
    return this.limit(value);
  }

  ///
  /// Set the limit and offset for a given page.
  ///
  /// @param  int  $page
  /// @param  int  $perPage
  /// @return \Illuminate\Database\Query\Builder|static
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
    // 2. Adiciona where(column, '>', lastId)
    this.where(column, '>', lastId);
    // 3. Ordena pela coluna asc
    this.orderBy(column, 'asc');
    // 4. Limita a [perPage]
    this.take(perPage);
    return this;
  }

  ///
  /// Add a union statement to the query.
  ///
  /// @param  \Illuminate\Database\Query\Builder|\Closure  $query
  /// @param  bool  $all
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder union(dynamic queryP, [bool all = false]) {
    if (queryP is Function) {
      var query = this.newQuery();
      queryP(query);
    }

    this.unionsProp.add({'query': queryP, 'all': all});

    this.addBinding(queryP.getBindings(), 'union');

    return this;
  }

  ///
  /// Add a union all statement to the query.
  ///
  /// @param  \Illuminate\Database\Query\Builder|\Closure  $query
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  dynamic unionAll($query) {
    return this.union($query, true);
  }

  ///
  /// Lock the selected rows in the table.
  ///
  /// @param  bool  $value
  /// @return $this
  ///
  QueryBuilder lock([bool value = true]) {
    this.lockProp = value;

    if (this.lockProp) {
      this.useWritePdo();
    }

    return this;
  }

  ///
  /// Lock the selected rows in the table for updating.
  ///
  /// @return \Illuminate\Database\Query\Builder
  ///
  QueryBuilder lockForUpdate() {
    return this.lock(true);
  }

  ///
  /// Share lock the selected rows in the table.
  ///
  /// @return \Illuminate\Database\Query\Builder
  ///
  QueryBuilder sharedLock() {
    return this.lock(false);
  }

  ///
  /// Get the SQL representation of the query.
  ///
  /// @return string
  ///
  String toSql() {
    return this.grammar.compileSelect(this);
  }

  ///
  /// Execute a query for a single record by ID.
  ///
  /// @param  int    $id
  /// @param  array  $columns
  /// @return mixed|static
  ///
  Future<Map<String, dynamic>?> find(int id,
      [List<String> columns = const ['*']]) {
    return this.where('id', '=', id).first(columns);
  }

  ///
  /// Get a single column's value from the first result of a query.
  ///
  /// @param  String  $column
  /// @return mixed
  ///
  Future<dynamic> value(String column) async {
    final result = await this.first([column]);
    return result;
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
  /// @param  array  $columns
  /// @return array|static[]
  ///
  Future<List<Map<String, dynamic>>> get(
      [List<String> columnsP = const ['*'], int? timeoutInSeconds]) async {
    var original = this.columnsProp != null ? [...this.columnsProp!] : null;

    if (Utils.is_null(original)) {
      this.columnsProp = columnsP;
    }

    final resultRunSelect = await this.runSelect(timeoutInSeconds);

    final results = this.processor.processSelect(this, resultRunSelect);
    this.columnsProp = original;
    return results;
  }

  ///
  /// Run the query as a "select" statement against the connection.
  ///
  /// @return array
  ///
  Future<List<Map<String, dynamic>>> runSelect([int? timeoutInSeconds]) async {
    final sqlStr = this.toSql();

    final bid = this.getBindings();

    final com = this.connection;

    final results = await com.select(sqlStr, bid, !this.useWritePdoProp);

    return results;
  }

  ///
  /// Paginate the given query into a simple paginator.
  ///
  /// @param  int  $perPage
  /// @param  array  $columns
  /// @param  String  $pageName
  /// @param  int|null  $page
  /// @return \Illuminate\Contracts\Pagination\LengthAwarePaginator
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
    List<Map<String, dynamic>> results =
        total > 0 ? await forPage(page, perPage).get(columns) : [];

    // Returns LengthAwarePaginator with results and metadata.
    return DefaultLengthAwarePaginator(results, total, perPage, page, {
      'path': PaginationUtils.resolveCurrentPath(),
      'pageName': pageName,
    });
  }

  ///
  /// Get a paginator only supporting simple next and previous links.
  ///
  /// This is more efficient on larger data-sets, etc.
  ///
  /// @param  int  $perPage
  /// @param  array  $columns
  /// @param  String  $pageName
  /// @return \Illuminate\Contracts\Pagination\Paginator
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
    this.skip((page - 1) * perPage).take(perPage + 1);
    final results = await this.get(columns);

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
  /// @param  array  $columns
  /// @return int
  ///
  /// Returns total count of records for pagination.
  Future<int> getCountForPagination(
      [List<String> columns = const ['*']]) async {
    backupFieldsForCount();

    // Sets aggregation for count, removing aliases.
    aggregateProp = {
      'function': 'count',
      'columns': clearSelectAliases(columns)
    };

    // Executes query (in this case, count query).
    List<Map<String, dynamic>> results = await get();

    aggregateProp = null;

    restoreFieldsForCount();

    // If grouped, returns number of results (groups).
    if (groupsProp.isNotEmpty) {
      return results.length;
    }

    // Otherwise, expects result to have an 'aggregate' key.
    if (results.isNotEmpty && results.first.containsKey('aggregate')) {
      var agg = results.first['aggregate'];
      if (agg is int) {
        return agg;
      } else if (agg is String) {
        return int.tryParse(agg) ?? 0;
      }
    }

    return 0;
  }

  ///
  /// Backup some fields for the pagination count.
  ///
  /// @return void
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
  /// @param  array  $columns
  /// @return array
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
  /// @return void
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
    alias ??= column;
    dynamic lastId = 0; // initial value

    while (true) {
      // Loads the next [count] records, where column > lastId
      final results = await this.forPageAfterId(count, lastId, column).get();
      final countResults = results.length;

      if (countResults == 0) {
        break;
      }

      // Calls the callback for this block
      final cbResult = await callback(results);
      if (cbResult == false) {
        return false;
      }

      // Gets the ID value of the last returned record
      final lastRow = results.last;
      final dynamic aliasValue = lastRow[alias];
      if (aliasValue == null) {
        // if we didn't find the ID value in the record, we stop
        break;
      }
      lastId = aliasValue;

      // If fewer records than "count" came back, nothing more
      if (countResults < count) {
        break;
      }
    }

    return true;
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
  /// @param  String  $column
  /// @param  String|null  $key
  /// @return array
  ///
  Future<dynamic> pluck(String column, [String? key]) async {
    var results =
        await this.get(Utils.is_null(key) ? [column] : [column, key!]);

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
  /// @param  String  $column
  /// @param  String|null  $key
  /// @return array
  ///
  /// @deprecated since version 5.2. Use the "pluck" method directly.
  ///
  // dynamic lists($column, $key = null)
  // {
  //     return this.pluck($column, $key);
  // }

  ///
  /// Strip off the table name or alias from a column identifier.
  ///
  /// @param  String  $column
  /// @return string|null
  ///
  dynamic stripTableForPluck(column) {
    return Utils.is_null(column) ? column : column.split(RegExp(r'\.| ')).last;
  }

  /// Concatenate values of a given column as a string.
  ///
  /// In Laravel, `implode($column, $glue)` combines values into a single string.
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
  /// @return bool
  ///
  Future<bool> exists() async {
    final sql = this.grammar.compileExists(this);

    final results =
        await this.connection.select(sql, getBindings(), useWritePdoProp);

    if (results.isNotEmpty && results.first.containsKey('exists')) {
      return results.first['exists'] == true;
    }

    return false;
  }

  ///
  /// Retrieve the "count" result of the query.
  ///
  /// @param  String|List<String>  columns
  /// @return int
  ///
  Future<int> count([dynamic columns = '*']) async {
    if (!Utils.is_array(columns)) {
      columns = <String>[columns];
    }
    //var cols = (columns as List).map((e) => e.toString()).toList();

    //__FUNCTION__	The function name, or {closure} for anonymous functions.
    //a constant __FUNCTION__  returns the current function name https://www.php.net/manual/en/language.constants.magic.php
    final result = await this.aggregate('count', columns);
    return result is int ? result : 0;
  }

  ///
  /// Retrieve the minimum value of a given column.
  ///
  /// @param  String  $column
  /// @return float|int
  ///
  Future<num?> min(String column) async {
    final result = await this.aggregate("min", [column]);
    return result is String ? num.tryParse(result) : result;
  }

  ///
  /// Retrieve the maximum value of a given column.
  ///
  /// @param  String  $column
  /// @return float|int
  ///
  Future<num?> max(String column) async {
    final result = await this.aggregate("max", [column]);
    return result is String ? num.tryParse(result) : result;
  }

  ///
  /// Retrieve the sum of the values of a given column.
  ///
  /// @param  String  $column
  /// @return float|int
  ///
  Future<num?> sum(String column) async {
    final result = await this.aggregate('sum', [column]);
    return result is String ? num.tryParse(result) : result;
  }

  ///
  /// Retrieve the average of the values of a given column.
  ///
  /// @param  String  $column
  /// @return float|int
  ///
  Future<num?> avg(String column) async {
    final result = await this.aggregate('avg', [column]);
    return result is String ? num.tryParse(result) : result;
  }

  ///
  /// Alias for the "avg" method.
  ///
  /// @param  String  $column
  /// @return float|int
  ///
  Future<num?> average(String column) async {
    return await this.avg(column);
  }

  ///
  /// Execute an aggregate function on the database.
  ///
  /// @param  String  $function
  /// @param  array   $columns
  /// @return float|int
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

    var results = await this.get(columnsP);

    // Once we have executed the query, we will reset the aggregate property so
    // that more select queries can be executed against the database without
    // the aggregate value getting in the way when the grammar builds it.
    this.aggregateProp = null;
    this.columnsProp = previousColumns;
    this.bindings['select'] = previousSelectBindings;

    if (results.isNotEmpty) {
      var result = Utils.map_change_key_case_sd(results[0]);
      return result['aggregate'];
    }
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
    // if (empty($values)) {
    //     return true;
    // }

    // Since every insert gets treated like a batch insert, we will make sure the
    // bindings are structured in a way that is convenient for building these
    // inserts statements by verifying the elements are actually an array.
    // if (! Utils.is_map(values)) {
    //     values = [values];
    // }

    // Since every insert gets treated like a batch insert, we will make sure the
    // bindings are structured in a way that is convenient for building these
    // inserts statements by verifying the elements are actually an array.

    // for (var entry in values.entries) {
    //   var key =entry.key;
    //   var value=entry.value;
    //    // ksort($value);
    //     values[key] = value;
    // }

    // We'll treat every insert like a batch insert so we can easily insert each
    // of the records into the database consistently. This will make it much
    // easier on the grammars to just handle one type of record insertion.
    var bindings = [];
    for (var entry in values.entries) {
      var value = entry.value;
      bindings.add(value);
    }
    var sql = this.grammar.compileInsert(this, values);
    // Once we have compiled the insert statement's SQL we can execute it on the
    // connection and return a result as a boolean success indicator as that
    // is the same type of result returned by the raw connection instance.
    bindings = this.cleanBindings(bindings);
    return this.connection.insert(sql, bindings);
  }

  ///
  /// Insert a new record and get the value of the primary key.
  ///
  /// @param  array   $values
  /// @param  String  $sequence
  /// @return int
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
  Future<dynamic> update(Map<String, dynamic> keyValues,
      [Duration? timeout = Connection.defaultTimeout]) {
    var curentBindings = this.getBindings();
    var values = keyValues.values.toList();
    var mergedBindings = Utils.array_merge(values, curentBindings);

    final sql = this.grammar.compileUpdate(this, keyValues);
    return this.connection.update(sql, this.cleanBindings(mergedBindings));
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
    // 1. Checks if any record exists with provided attributes
    final bool recordExists = await this.where(attributes).exists();

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
      // 3. If exists, updates only 1 record
      final int affectedRows =
          await this.where(attributes).limit(1).update(values);

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
  /// @param  mixed  $id
  /// @return int
  ///
  Future<int> delete(
      [dynamic id, Duration? timeout = Connection.defaultTimeout]) {
    // If an ID is passed to the method, we will set the where clause to check
    // the ID to allow developers to simply and quickly remove a single row
    // from their database without manually specifying the where clauses.
    if (!Utils.is_null(id)) {
      this.where('id', '=', id);
    }

    var sql = this.grammar.compileDelete(this);

    return this.connection.delete(sql, this.getBindings());
  }

  ///
  /// Run a truncate statement on the table.
  ///
  /// @return void
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
  /// @return \Illuminate\Database\Query\Builder
  ///
  QueryBuilder newQuery() {
    return QueryBuilder(this.connection, this.grammar, this.processor);
  }

  ///
  /// Create a new query instance for a sub-query.
  ///
  /// @return \Illuminate\Database\Query\Builder
  ///
  QueryBuilder forSubQuery() {
    return this.newQuery();
  }

  ///
  /// Merge an array of where clauses and bindings.
  ///
  /// @param  array  $wheres
  /// @param  array  $bindings
  /// @return void
  ///
  void mergeWheres(List<Map<String, dynamic>> wheresP, bindingsP) {
    // this.wheresProp = Utils.array_merge_ms(this.wheresProp, wheresP);
    // this
    //     .bindings['where']
    //     .add(Utils.array_merge(this.bindings['where'], bindingsP));

    // Merges WHERE clauses
    this.wheresProp.addAll(wheresP);
    // Merges bindings of type 'where'
    this.bindings['where'].addAll(bindings);
  }

  ///
  /// Remove all of the expressions from a list of bindings.
  ///
  /// @param  array  $bindings
  /// @return array
  ///
  List cleanBindings(List bindings) {
    return Utils.array_filter(bindings, (binding) {
      return !(binding is QueryExpression);
    });
  }

  ///
  /// Create a raw database expression.
  ///
  /// @param  mixed  $value
  /// @return \Illuminate\Database\Query\Expression
  ///
  QueryExpression raw(dynamic value) {
    return this.connection.raw(value);
  }

  ///
  /// Get the current query value bindings in a flattened array.
  ///
  /// @return array
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
    if (this.bindings['having'] != null) {
      result.addAll(this.bindings['having']);
    }
    if (this.bindings['order'] != null) {
      result.addAll(this.bindings['order']);
    }
    if (this.bindings['union'] != null) {
      result.addAll(this.bindings['union']);
    }

    return result;
  }

  ///
  /// Get the raw array of bindings.
  ///
  /// @return array
  ///
  Map<String, dynamic> getRawBindings() {
    return this.bindings;
  }

  ///
  /// Set the bindings on the query builder.
  ///
  /// @param  array   $bindings
  /// @param  String  $type
  /// @return $this
  ///
  /// @throws \InvalidArgumentException
  ///
  QueryBuilder setBindings(Map<String, dynamic> bindingsP, [type = 'where']) {
    if (!bindings.containsKey(type)) {
      throw InvalidArgumentException('Invalid binding type: $type.');
    }
    bindings[type] = bindingsP;
    return this;
  }

  ///
  /// Add a binding to the query.
  ///
  /// [value]  dynamic
  /// [type]  String
  /// @return $this
  ///
  /// @throws \InvalidArgumentException
  ///
  QueryBuilder addBinding(dynamic value, [String type = 'where']) {
    if (!Utils.map_key_exists(type, this.bindings)) {
      throw InvalidArgumentException("Invalid binding type: $type.");
    }

    if (Utils.is_array(value)) {
      this.bindings[type] = Utils.array_merge(this.bindings[type], value);
    } else {
      this.bindings[type].add(value);
    }

    return this;
  }

  ///
  /// Merge an array of bindings into our bindings.
  ///
  /// @param  \Illuminate\Database\Query\Builder  $query
  /// @return $this
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
  /// @return \Illuminate\Database\ConnectionInterface
  ///
  ConnectionInterface getConnection() {
    return this.connection;
  }

  ///
  /// Get the database query processor instance.
  ///
  /// @return \Illuminate\Database\Query\Processors\Processor
  ///
  Processor getProcessor() {
    return this.processor;
  }

  ///
  /// Get the query grammar instance.
  ///
  /// @return \Illuminate\Database\Query\Grammars\Grammar
  ///
  QueryGrammar getGrammar() {
    return this.grammar;
  }

  ///
  /// Use the write pdo for query.
  ///
  /// @return $this
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
    return _addLateralJoin('inner', subquery, alias, onCallback);
  }

  /// Adds a LEFT JOIN LATERAL to the query.
  ///
  /// [subquery] can be a QueryBuilder, a Closure (Function) or a raw SQL String.
  /// [alias] is the mandatory alias for the lateral subquery.
  /// [onCallback] is a function receiving a JoinClause to define ON conditions.
  /// Often for LATERAL JOIN, the condition is `ON TRUE`.
  QueryBuilder leftJoinLateral(
      dynamic subquery, String alias, Function(JoinClause) onCallback) {
    return _addLateralJoin('left', subquery, alias, onCallback);
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
    String type = 'inner',
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
  /// @return static
  ///
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

    newQuery.expressionsProp = expressionsProp
        .map((expression) => Map<String, dynamic>.from(expression))
        .toList();

    newQuery.recursionLimitProp = recursionLimitProp;

    newQuery.bindings = {
      'select': [...bindings['select']!],
      'from': [...bindings['from']!],
      'join': [...bindings['join']!],
      'where': [...bindings['where']!],
      'having': [...bindings['having']!],
      'order': [...bindings['order']!],
      'union': [...bindings['union']!],
      'expressions': [...bindings['expressions']!],
    };

    return newQuery;
  }

  ///
  /// Handle dynamic method calls into the method.
  ///
  /// @param  String  methodName
  /// @param  array   $parameters
  /// @return mixed
  ///
  /// @throws \BadMethodCallException
  ///
  // dynamic __call($method, $parameters)
  // {
  //     if (static::hasMacro($method)) {
  //         return this.macroCall($method, $parameters);
  //     }
  //     if (Str::startsWith($method, 'where')) {
  //         return this.dynamicWhere($method, $parameters);
  //     }
  //     $className = get_class($this);
  //     throw new BadMethodCallException("Call to undefined method {$className}::{$method}()");
  // }
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
