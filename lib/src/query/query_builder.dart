import 'package:eloquent/src/connection_interface.dart';
import 'package:eloquent/src/query/expression.dart';
import 'package:eloquent/src/query/grammars/query_grammar.dart';
import 'package:eloquent/src/query/join_clause.dart';
import 'package:eloquent/src/query/processors/processor.dart';
import 'package:eloquent/src/utils/utils.dart';

import '../exceptions/invalid_argument_exception.dart';

class QueryBuilder {
  /// Isaque
  /// Eu adicionei este metodo para mapear uma String para uma propriedade/atributo da Class QueryBuilder
  /// isso permite ler a propriedade/atributo da Class QueryBuilder com base no nome da propriedade
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
      case 'unionOrders':
        return this.unionOrdersProp;
      case 'bindingBackups':
        return this.bindingBackups;
      case 'operators':
        return this._operators;
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
    'join': [],
    'where': [],
    'having': [],
    'order': [],
    'union': [],
  };

  ///
  /// An aggregate function and column to be run.
  ///
  /// @var array
  ///
  Map<String, dynamic>? aggregateProp;

  ///
  /// The columns that should be returned.
  /// Propriedade da class QueryBuilder que armazena as colunas da tabela a serem retornadas
  /// @var array
  ///
  List<String>? columnsProp;

  List<String>? getColumns() {
    return columnsProp;
  }

  void setColumns(List<String>? cols) {
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
  /// @var string
  ///
  late String fromProp;

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
  List backups = [];

  ///
  /// The binding backups currently in use.
  ///
  /// @var array
  ///
  List bindingBackups = [];

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

  ///
  /// Create a new query builder instance.
  ///
  /// @param  \Illuminate\Database\ConnectionInterface  $connection
  /// @param  \Illuminate\Database\Query\Grammars\Grammar  $grammar
  /// @param  \Illuminate\Database\Query\Processors\Processor  $processor
  ///
  QueryBuilder(this.connection, this.grammar, this.processor) {
    // this._grammar = grammarP;
    // this._processor = processorP;
    // this._connection = connectionP;
  }

  ///
  /// Set the columns to be selected.
  ///
  /// @param  array|mixed  $columns
  /// @return $this
  ///
  QueryBuilder select([List<String> columnsP = const ['*']]) {
    //this.columns = is_array($columns) ? $columns : func_get_args();
    this.columnsProp = columnsP;
    return this;
  }

  ///
  /// Add a new "raw" select expression to the query.
  ///
  /// @param  String  $expression
  /// @param  array   $bindings
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder selectRaw(String expression, [List? bindingsP = const []]) {
    //TODO checar QueryExpression(expression)
    this.addSelect(QueryExpression(expression));

    if (bindingsP != null) {
      this.addBinding(bindingsP, 'select');
    }

    return this;
  }

  ///
  /// Add a subselect expression to the query.
  ///
  /// @param  \Closure|\Illuminate\Database\Query\Builder|string $query
  /// @param  String  $as
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder selectSub(dynamic query, String $as) {
    var bindings;
    if (query is Function) {
      var callback = query;

      callback(query = this.newQuery());
    }

    if (query is QueryBuilder) {
      bindings = query.getBindings();

      query = query.toSql();
    } else if (Utils.is_string(query)) {
      bindings = [];
    } else {
      throw InvalidArgumentException();
    }

    return this
        .selectRaw('(' + query + ') as ' + this.grammar.wrap($as), bindings);
  }

  ///
  /// Add a new select column to the query.
  ///
  /// @param  array|mixed  $column
  /// @return $this
  ///
  QueryBuilder addSelect(dynamic columnP) {
    //var column = is_array(column) ? column : func_get_args();

    this.columnsProp = Utils.array_merge_sa(columnsProp, columnP);

    return this;
  }

  ///
  /// Force the query to only return distinct results.
  ///
  /// @return $this
  ///
  QueryBuilder distinct() {
    this.distinctProp = true;

    return this;
  }

  ///
  /// Set the table which the query is targeting.
  ///
  /// @param  String  $table
  /// @return $this
  ///
  QueryBuilder from(String tableP) {
    this.fromProp = tableP;
    return this;
  }

  ///
  /// Add a join clause to the query.
  ///
  /// [table] String name of table 
  /// [one]  String | Function(JoinClause)
  /// [operator] String  Example: '=', 'in', 'not in'
  /// @param  String  $two
  /// [type]  String  Example: 'inner', 'left'
  /// [where]  bool   
  /// `Return` this QueryBuilder
  ///
  QueryBuilder join(String table, dynamic one,
      [String? operator,
      dynamic two = null,
      String type = 'inner',
      bool where = false]) {
    // If the first "column" of the join is really a Closure instance the developer
    // is trying to build a join with a complex "on" clause containing more than
    // one condition, so we'll add the join and call a Closure with the query.
    if (one is Function) {
      var join = JoinClause(type, table);
      one(join);      
      this.joinsProp.add(join);
      this.addBinding(join.bindings, 'join');
    }
    // If the column is simply a string, we can assume the join simply has a basic
    // "on" clause with a single condition. So we will just build the join with
    // this simple join clauses attached to it. There is not a join callback.
    else {
      var join = new JoinClause(type, table);
      this.joinsProp.add(join.on(one, operator, two, 'and', where));
      this.addBinding(join.bindings, 'join');
    }

    return this;
  }

  ///
  /// Add a "join where" clause to the query.
  ///
  /// @param  String  $table
  /// @param  String  $one
  /// @param  String  $operator
  /// @param  String  $two
  /// @param  String  $type
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder joinWhere(String table, one, operator, two, [type = 'inner']) {
    return this.join(table, one, operator, two, type, true);
  }

  ///
  /// Add a left join to the query.
  ///
  /// @param  String  $table
  /// @param  String  $first
  /// @param  String  $operator
  /// @param  String  $second
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder leftJoin(String table, first,
      [String? operator, dynamic second]) {
    return this.join(table, first, operator, second, 'left');
  }

  ///
  /// Add a "join where" clause to the query.
  ///
  /// @param  String  $table
  /// @param  String  $one
  /// @param  String  $operator
  /// @param  String  $two
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder leftJoinWhere(
      String table, dynamic one, String operator, dynamic two) {
    return this.joinWhere(table, one, operator, two, 'left');
  }

  ///
  /// Add a right join to the query.
  ///
  /// @param  String  $table
  /// @param  String  $first
  /// @param  String  $operator
  /// @param  String  $second
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder rightJoin(String table, dynamic first, String operator,
      [dynamic second]) {
    return this.join(table, first, operator, second, 'right');
  }

  ///
  /// Add a "right join where" clause to the query.
  ///
  /// @param  String  $table
  /// @param  String  $one
  /// @param  String  $operator
  /// @param  String  $two
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder rightJoinWhere(
      String table, dynamic one, String operator, dynamic two) {
    return this.joinWhere(table, one, operator, two, 'right');
  }

  ///
  /// Add a basic where clause to the query.
  ///
  /// [column] String|Map|Function
  /// @param  String  $operator
  /// @param  mixed   $value
  /// @param  String  $boolean
  /// @return $this
  ///
  /// @throws \InvalidArgumentException
  ///
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

    // Here we will make some assumptions about the operator. If only 2 values are
    // passed to the method, we will assume that the operator is an equals sign
    // and keep going. Otherwise, we'll require the operator to be passed in.
    //  if (func_num_args() == 2) {
    //      list($value, $operator) = [$operator, '='];
    //  } else if (this.invalidOperatorAndValue($operator, $value)) {
    //      throw new InvalidArgumentException('Illegal operator and value combination.');
    //  }

    // If the columns is actually a Closure instance, we will assume the developer
    // wants to begin a nested where statement which is wrapped in parenthesis.
    // We'll add that Closure to the query then return back out immediately.
    if (column is Function) {
      return this.whereNested(column, boolean);
    }

    // If the given operator is not found in the list of valid operators we will
    // assume that the developer is just short-cutting the '=' operators and
    // we will set the operators to '=' and set the values appropriately.
    // if (! in_array(strtolower(operator), this._operators, true)) {
    //     list($value, $operator) = [$operator, '='];
    // }

    // If the value is a Closure, it means the developer is performing an entire
    // sub-select within the query and we will need to compile the sub-select
    // within the where clause to get the appropriate query record results.
    if (value is Function) {
      return this.whereSub(column, operator, value, boolean);
    }

    // If the value is "null", we will just assume the developer wants to add a
    // where null clause to the query. So, we will allow a short-cut here to
    // that method for convenience so the developer doesn't have to check.
    if (Utils.is_null(value)) {
      return this.whereNull(column, boolean, operator != '=');
    }

    // Now that we are working with just a simple query we can put the elements
    // in our array and add the query binding to our array of bindings that
    // will be bound to each SQL statements when it is finally executed.
    var type = 'Basic';

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

  ///
  /// Add an "or where" clause to the query.
  ///
  /// @param  String  $column
  /// @param  String  $operator
  /// @param  mixed   $value
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder orWhere(String column, [String? operator, dynamic value]) {
    return this.where(column, operator, value, 'or');
  }

  ///
  /// Determine if the given operator and value combination is legal.
  ///
  /// @param  String  $operator
  /// @param  mixed  $value
  /// @return bool
  ///
  bool invalidOperatorAndValue(String operator, dynamic value) {
    var isOperator = Utils.in_array(operator, this._operators);

    return isOperator && operator != '=' && Utils.is_null(value);
  }

  ///
  /// Add a raw where clause to the query.
  ///
  /// @param  String  $sql
  /// @param  array   $bindings
  /// @param  String  $boolean
  /// @return $this
  ///
  QueryBuilder whereRaw(String sql,
      [List bindings = const [], boolean = 'and']) {
    var type = 'raw';

    this.wheresProp.add({'type': type, 'sql': sql, 'boolean': boolean});

    this.addBinding(bindings, 'where');

    return this;
  }

  ///
  /// Add a raw or where clause to the query.
  ///
  /// @param  String  $sql
  /// @param  array   $bindings
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder orWhereRaw(String sql, [List bindings = const []]) {
    return this.whereRaw(sql, bindings, 'or');
  }

  ///
  /// Add a where between statement to the query.
  ///
  /// @param  String  $column
  /// @param  array   $values
  /// @param  String  $boolean
  /// @param  bool  $not
  /// @return $this
  ///
  QueryBuilder whereBetween(String column,
      [List? values, String boolean = 'and', bool not = false]) {
    var type = 'between';

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

  ///
  /// Add a where not between statement to the query.
  ///
  /// @param  String  $column
  /// @param  array   $values
  /// @param  String  $boolean
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder whereNotBetween(column, List values, [boolean = 'and']) {
    return this.whereBetween(column, values, boolean, true);
  }

  ///
  /// Add an or where not between statement to the query.
  ///
  /// @param  String  $column
  /// @param  array   $values
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder orWhereNotBetween(String column, List values) {
    return this.whereNotBetween(column, values, 'or');
  }

  ///
  /// Add a nested where statement to the query.
  ///
  /// @param  \Closure $callback
  /// @param  String   $boolean
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder whereNested(Function callback, [String boolean = 'and']) {
    var query = this.forNestedWhere();

    callback(query);

    return this.addNestedWhereQuery(query, boolean);
  }

  ///
  /// Create a new query instance for nested where condition.
  ///
  /// @return \Illuminate\Database\Query\Builder
  ///
  QueryBuilder forNestedWhere() {
    var query = this.newQuery();

    return query.from(this.fromProp);
  }

  ///
  /// Add another query builder as a nested where to the query builder.
  ///
  /// @param  \Illuminate\Database\Query\Builder|static $query
  /// @param  String  $boolean
  /// @return $this
  ///
  QueryBuilder addNestedWhereQuery(QueryBuilder query, [boolean = 'and']) {
    if (Utils.count(query.wheresProp) != 0) {
      var type = 'Nested';

      this.wheresProp.add({'type': type, 'query': query, 'boolean': boolean});

      this.addBinding(query.getBindings(), 'where');
    }

    return this;
  }

  ///
  /// Add a full sub-select to the query.
  ///
  /// @param  String   $column
  /// @param  String   $operator
  /// @param  \Closure $callback
  /// @param  String   $boolean
  /// @return $this
  ///
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

  ///
  /// Add an exists clause to the query.
  ///
  /// @param  \Closure $callback
  /// @param  String   $boolean
  /// @param  bool     $not
  /// @return $this
  ///
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

  ///
  /// Add an or exists clause to the query.
  ///
  /// @param  \Closure $callback
  /// @param  bool     $not
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder orWhereExists(Function callback, [bool not = false]) {
    return this.whereExists(callback, 'or', not);
  }

  ///
  /// Add a where not exists clause to the query.
  ///
  /// @param  \Closure $callback
  /// @param  String   $boolean
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder whereNotExists(Function callback, [String boolean = 'and']) {
    return this.whereExists(callback, boolean, true);
  }

  ///
  /// Add a where not exists clause to the query.
  ///
  /// @param  \Closure  $callback
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder orWhereNotExists(Function callback) {
    return this.orWhereExists(callback, true);
  }

  ///
  /// Add a "where in" clause to the query.
  ///
  /// @param  String  $column
  /// @param  mixed   $values
  /// @param  String  $boolean
  /// @param  bool    $not
  /// @return $this
  ///
  QueryBuilder whereIn(String column, dynamic values,
      [String boolean = 'and', bool not = false]) {
    var type = not ? 'NotIn' : 'In';
    //TODO check isso if (values is static) {
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

  ///
  /// Add an "or where in" clause to the query.
  ///
  /// @param  String  $column
  /// @param  mixed   $values
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder orWhereIn(String column, dynamic values) {
    return this.whereIn(column, values, 'or');
  }

  ///
  /// Add a "where not in" clause to the query.
  ///
  /// @param  String  $column
  /// @param  mixed   $values
  /// @param  String  $boolean
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder whereNotIn(String column, values, [boolean = 'and']) {
    return this.whereIn(column, values, boolean, true);
  }

  ///
  /// Add an "or where not in" clause to the query.
  ///
  /// @param  String  $column
  /// @param  mixed   $values
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder orWhereNotIn($column, $values) {
    return this.whereNotIn($column, $values, 'or');
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
    var type = not ? 'NotInSub' : 'InSub';

    // To create the exists sub-select, we will actually create a query and call the
    // provided callback with the query so the developer may set any of the query
    // conditions they want for the in clause, then we'll put it in this array.
    var query = this.newQuery();
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
  /// @param  int   $value
  /// @param  String   $boolean
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder whereDate(String column, String? operator, int value,
      [String boolean = 'and']) {
    return this.addDateBasedWhere('Date', column, operator, value, boolean);
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
  /// @param  int  $value
  /// @param  String  $boolean
  /// @return $this
  ///
  QueryBuilder addDateBasedWhere(
      String type, String column, String? operator, int value,
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
  // QueryBuilder dynamicWhere(String method, String parameters)
  // {
  //     var finder = Utils.substr(method, 5);

  //     var segments = preg_split('/(And|Or)(?=[A-Z])/', finder, -1, PREG_SPLIT_DELIM_CAPTURE);

  //     // The connector variable will determine which connector will be used for the
  //     // query condition. We will change it as we come across new boolean values
  //     // in the dynamic method strings, which could contain a number of these.
  //     $connector = 'and';

  //     $index = 0;

  //     foreach ($segments as $segment) {
  //         // If the segment is not a boolean connector, we can assume it is a column's name
  //         // and we will add it to the query as a new constraint as a where clause, then
  //         // we can keep iterating through the dynamic method string's segments again.
  //         if ($segment != 'And' && $segment != 'Or') {
  //             this.addDynamic($segment, $connector, $parameters, $index);

  //             $index++;
  //         }

  //         // Otherwise, we will store the connector so we know how the next where clause we
  //         // find in the query should be connected to the previous ones, meaning we will
  //         // have the proper boolean connector to connect the next where clause found.
  //         else {
  //             $connector = $segment;
  //         }
  //     }

  //     return this;
  // }

  ///
  /// Add a single dynamic where clause statement to the query.
  ///
  /// @param  String  $segment
  /// @param  String  $connector
  /// @param  array   $parameters
  /// @param  int     $index
  /// @return void
  ///
  // QueryBuilder addDynamic(segment, connector, parameters, index)
  // {
  //     // Once we have parsed out the columns and formatted the boolean operators we
  //     // are ready to add it to this query as a where clause just like any other
  //     // clause on the query. Then we'll increment the parameter index values.
  //     var boolean = Utils.strtolower(connector);

  //     this.where(Str::snake($segment), '=', $parameters[$index], $bool);
  // }

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
  QueryBuilder having(String column,
      [String? operator, dynamic value, String boolean = 'and']) {
    var type = 'basic';

    this.havingsProp.add({
      'type': type,
      'column': column,
      'operator': operator,
      'value': value,
      'boolean': boolean
    });

    if (!value is QueryExpression) {
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

  ///
  /// Add a raw having clause to the query.
  ///
  /// @param  String  $sql
  /// @param  array   $bindings
  /// @param  String  $boolean
  /// @return $this
  ///
  // dynamic havingRaw($sql, array $bindings = [], $boolean = 'and')
  // {
  //     $type = 'raw';

  //     this.havings[] = compact('type', 'sql', 'boolean');

  //     this.addBinding($bindings, 'having');

  //     return this;
  // }

  ///
  /// Add a raw or having clause to the query.
  ///
  /// @param  String  $sql
  /// @param  array   $bindings
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  // dynamic orHavingRaw($sql, array $bindings = [])
  // {
  //     return this.havingRaw($sql, $bindings, 'or');
  // }

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
    return this.skip((page - 1));

    /// $perPage)->take($perPage);
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
  QueryBuilder lock([value = true]) {
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
  dynamic find(int id, [List<String> columns = const ['*']]) {
    return this.where('id', '=', id).first(columns);
  }

  ///
  /// Get a single column's value from the first result of a query.
  ///
  /// @param  String  $column
  /// @return mixed
  ///
  Future<dynamic> value(String column) async {
    var result = await this.first([column]);

    return Utils.count(result) > 0 ? Utils.reset(result) : null;
  }

  ///
  /// Execute the query and get the first result.
  ///
  /// [columns] columns 
  /// `Return` Map<String,dynamic> or List<dynamic>
  ///
  Future<dynamic> first([List<String> columns = const ['*']]) async {
    var results = await this.take(1).get(columns);  
    return Utils.count(results) > 0 ? Utils.reset(results) : null;
  }

  ///
  /// Execute the query as a "select" statement.
  ///
  /// @param  array  $columns
  /// @return array|static[]
  ///
  Future<dynamic> get([List<String> columnsP = const ['*']]) async {
    var original = this.columnsProp != null ? [...this.columnsProp!] : null;

    if (Utils.is_null(original)) {
      this.columnsProp = columnsP;
    }

    var resultRunSelect = await this.runSelect();
    //print('query_builder@get $resultRunSelect');

    var results = this.processor.processSelect(this, resultRunSelect);
    this.columnsProp = original;
    return results;
  }

  ///
  /// Run the query as a "select" statement against the connection.
  ///
  /// @return array
  ///
  Future<dynamic> runSelect() async {
    var sqlStr = this.toSql();
    //print('QueryGrammar@runSelect sql: $sqlStr');
    var bid = this.getBindings();
    // print('QueryGrammar@runSelect getBindings: $bid');
    var com = this.connection;

    var results = await com.select(sqlStr, bid, !this.useWritePdoProp);
    // print('QueryGrammar@runSelect results: $results');
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
  // dynamic paginate([int perPage = 15, columns = const['*'], pageName = 'page', page = null])
  // {
  //     var page = $page ?: Paginator::resolveCurrentPage($pageName);

  //     $total = this.getCountForPagination($columns);

  //     $results = this.forPage($page, $perPage)->get($columns);

  //     return new LengthAwarePaginator($results, $total, $perPage, $page, [
  //         'path' => Paginator::resolveCurrentPath(),
  //         'pageName' => $pageName,
  //     ]);
  // }

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
  // dynamic simplePaginate($perPage = 15, $columns = ['///'], $pageName = 'page')
  // {
  //     $page = Paginator::resolveCurrentPage($pageName);

  //     this.skip(($page - 1) /// $perPage)->take($perPage + 1);

  //     return new Paginator(this.get($columns), $perPage, $page, [
  //         'path' => Paginator::resolveCurrentPath(),
  //         'pageName' => $pageName,
  //     ]);
  // }

  ///
  /// Get the count of the total records for the paginator.
  ///
  /// @param  array  $columns
  /// @return int
  ///
  // dynamic getCountForPagination($columns = ['///'])
  // {
  //     this.backupFieldsForCount();

  //     this.aggregate = ['function' => 'count', 'columns' => this.clearSelectAliases($columns)];

  //     $results = this.get();

  //     this.aggregate = null;

  //     this.restoreFieldsForCount();

  //     if (isset(this.groupsProp)) {
  //         return count($results);
  //     }

  //     return isset($results[0]) ? (int) array_change_key_case((array) $results[0])['aggregate'] : 0;
  // }

  ///
  /// Backup some fields for the pagination count.
  ///
  /// @return void
  ///
  // void backupFieldsForCount()
  // {
  //     for (['orders', 'limit', 'offset', 'columns'] as $field) {
  //         this.backups[$field] = this.{$field};

  //         this.{$field} = null;
  //     }

  //     for (['order', 'select'] as $key) {
  //         this.bindingBackups[$key] = this.bindings[$key];

  //         this.bindings[$key] = [];
  //     }
  // }

  ///
  /// Remove the column aliases since they will break count queries.
  ///
  /// @param  array  $columns
  /// @return array
  ///
  // dynamic clearSelectAliases( $columns)
  // {
  //     return array_map(function ($column) {
  //         return is_string($column) && ($aliasPosition = strpos(strtolower($column), ' as ')) != false
  //                 ? substr($column, 0, $aliasPosition) : $column;
  //     }, $columns);
  // }

  ///
  /// Restore some fields after the pagination count.
  ///
  /// @return void
  ///
  // protected function restoreFieldsForCount()
  // {
  //     foreach (['orders', 'limit', 'offset', 'columns'] as $field) {
  //         this.{$field} = this.backups[$field];
  //     }

  //     foreach (['order', 'select'] as $key) {
  //         this.bindings[$key] = this.bindingBackups[$key];
  //     }

  //     this.backups = [];
  //     this.bindingBackups = [];
  // }

  ///
  /// Chunk the results of the query.
  ///
  /// @param  int  $count
  /// @param  callable  $callback
  /// @return bool
  ///
  // dynamic chunk(int count, Function callback)
  // {
  //     $results = this.forPage($page = 1, $count)->get();

  //     while (count($results) > 0) {
  //         // On each chunk result set, we will pass them to the callback and then let the
  //         // developer take care of everything within the callback, which allows us to
  //         // keep the memory low for spinning through large result sets for working.
  //         if (call_user_func($callback, $results) === false) {
  //             return false;
  //         }

  //         $page++;

  //         $results = this.forPage($page, $count)->get();
  //     }

  //     return true;
  // }

  ///
  /// Get an array with the values of a given column.
  ///
  /// @param  String  $column
  /// @param  String|null  $key
  /// @return array
  ///
  dynamic pluck(String column, [String? key]) {
    var results = this.get(Utils.is_null(key) ? [column] : [column, key!]);

    // If the columns are qualified with a table or have an alias, we cannot use
    // those directly in the "pluck" operations since the results from the DB
    // are only keyed by the column itself. We'll strip the table out here.
    return Utils.array_pluck(results, this.stripeTableForPluck(column),
        this.stripeTableForPluck(key));
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
  dynamic stripeTableForPluck(column) {
    return Utils.is_null(column) ? column : column.split(RegExp(r'\.| ')).last;
  }

  ///
  /// Concatenate values of a given column as a string.
  ///
  /// @param  String  $column
  /// @param  String  $glue
  /// @return string
  ///
  // String implode(String column, [String glue = ''])
  // {
  //     return Utils.implode(glue, this.pluck($column));
  // }

  ///
  /// Determine if any rows exist for the current query.
  ///
  /// @return bool
  ///
  dynamic exists() {
    var sql = this.grammar.compileExists(this);

    dynamic results =
        this.connection.select(sql, this.getBindings(), this.useWritePdoProp);

    if (results[0] != null) {
      results = results[0];

      return results['exists'];
    }

    return false;
  }

  ///
  /// Retrieve the "count" result of the query.
  ///
  /// @param  String  $columns
  /// @return int
  ///
  Future<int> count([columns = '*']) async {
    if (!Utils.is_array(columns)) {
      columns = [columns];
    }
    //__FUNCTION__	The function name, or {closure} for anonymous functions.
    //a constant __FUNCTION__  retorna o nome da corrent função https://www.php.net/manual/en/language.constants.magic.php
    return await this.aggregate(count, columns);
  }

  ///
  /// Retrieve the minimum value of a given column.
  ///
  /// @param  String  $column
  /// @return float|int
  ///
  // dynamic min($column)
  // {
  //     return this.aggregate(__FUNCTION__, [$column]);
  // }

  ///
  /// Retrieve the maximum value of a given column.
  ///
  /// @param  String  $column
  /// @return float|int
  ///
  // dynamic max($column)
  // {
  //     return this.aggregate(__FUNCTION__, [$column]);
  // }

  ///
  /// Retrieve the sum of the values of a given column.
  ///
  /// @param  String  $column
  /// @return float|int
  ///
  // dynamic sum($column)
  // {
  //     $result = this.aggregate(__FUNCTION__, [$column]);

  //     return $result ?: 0;
  // }

  ///
  /// Retrieve the average of the values of a given column.
  ///
  /// @param  String  $column
  /// @return float|int
  ///
  // dynamic avg($column)
  // {
  //     return this.aggregate(__FUNCTION__, [$column]);
  // }

  ///
  /// Alias for the "avg" method.
  ///
  /// @param  String  $column
  /// @return float|int
  ///
  // dynamic average($column)
  // {
  //     return this.avg($column);
  // }

  ///
  /// Execute an aggregate function on the database.
  ///
  /// @param  String  $function
  /// @param  array   $columns
  /// @return float|int
  ///
  Future<dynamic> aggregate(function, [columnsP = const ['*']]) async {
    this.aggregateProp = {'function': function, 'columns': columnsP};

    var previousColumns = [...this.columnsProp!];

    // We will also back up the select bindings since the select clause will be
    // removed when performing the aggregate function. Once the query is run
    // we will add the bindings back onto this query so they can get used.
    // ignore: unused_local_variable
    var previousSelectBindings = {...(this.bindings['select'] as List)};

    this.bindings['select'] = [];

    var results = await this.get(columnsP);

    // Once we have executed the query, we will reset the aggregate property so
    // that more select queries can be executed against the database without
    // the aggregate value getting in the way when the grammar builds it.
    this.aggregateProp = null;

    this.columnsProp = previousColumns;

    this.bindings['select'] = previousSelectBindings;

    if (results[0] != null) {
      var result = Utils.map_change_key_case_sd(results[0]);

      return result['aggregate'];
    }
  }

  ///
  /// Insert a new record into the database.
  ///
  /// @param  Map  $values
  /// @return bool
  ///
  Future<dynamic> insert(Map<String, dynamic> values) {
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
      [String sequence = 'id']) {
    var sql = this.grammar.compileInsertGetId(this, keyValues, sequence);
    var values = this.cleanBindings(keyValues.values.toList());
    return this.processor.processInsertGetId(this, sql, values, sequence);
  }

  ///
  /// Update a record in the database.
  ///
  /// @param  array  $values
  /// @return int
  ///
  Future<dynamic> update(Map<String, dynamic> keyValues) {
    var curentBindings = this.getBindings();
    var values = keyValues.values.toList();    
    var bindings = Utils.array_merge(values, curentBindings); 
    var sql = this.grammar.compileUpdate(this, keyValues);
    return this.connection.update(sql, this.cleanBindings(bindings));
  }

  ///
  /// Increment a column's value by a given amount.
  ///
  /// @param  String  $column
  /// @param  int     $amount
  /// @param  array   $extra
  /// @return int
  ///
  // dynamic increment($column, $amount = 1, array $extra = [])
  // {
  //     $wrapped = this.grammar->wrap($column);

  //     $columns = array_merge([$column => this.raw("$wrapped + $amount")], $extra);

  //     return this.update($columns);
  // }

  ///
  /// Decrement a column's value by a given amount.
  ///
  /// @param  String  $column
  /// @param  int     $amount
  /// @param  array   $extra
  /// @return int
  ///
  // dynamic decrement($column, $amount = 1, array $extra = [])
  // {
  //     $wrapped = this.grammar->wrap($column);

  //     $columns = array_merge([$column => this.raw("$wrapped - $amount")], $extra);

  //     return this.update($columns);
  // }

  ///
  /// Delete a record from the database.
  ///
  /// @param  mixed  $id
  /// @return int
  ///
  Future<int> delete([dynamic id]) {
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
  void truncate() {
    for (var entry in this.grammar.compileTruncate(this).entries) {
      var sql = entry.key;
      var bindings = entry.value;
      this.connection.statement(sql, bindings);
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
  /// Merge an array of where clauses and bindings.
  ///
  /// @param  array  $wheres
  /// @param  array  $bindings
  /// @return void
  ///
  dynamic mergeWheres(List<Map<String, dynamic>> wheresP, bindingsP) {
    //TODO checar se a mesclagem esta correta
    this.wheresProp = Utils.array_merge_ms(this.wheresProp, wheresP);

    this
        .bindings['where']
        .add(Utils.array_merge(this.bindings['where'], bindingsP));
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
    // return array_flatten(this.bindings);

    //TODO verificar isso

    var result = [];
    if (this.bindings['select'] != null) {
      result.addAll(this.bindings['select']);
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
  dynamic getRawBindings() {
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
  dynamic setBindings(bindings, [type = 'where']) {
    if (!Utils.map_key_exists(type, this.bindings)) {
      throw InvalidArgumentException('Invalid binding type: $type.');
    }

    this.bindings[type] = bindings;

    return this;
  }

  ///
  /// Add a binding to the query.
  ///
  /// @param  mixed   $value
  /// @param  String  $type
  /// @return $this
  ///
  /// @throws \InvalidArgumentException
  ///
  QueryBuilder addBinding(dynamic value, [String type = 'where']) {
    if (!Utils.map_key_exists(type, this.bindings)) {
      throw InvalidArgumentException("Invalid binding type: $type.");
    }

    if (Utils.is_array(value)) {
      /// TODO: checar isso pois acho que é array em vez de Map ?
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
    //this.bindings = array_merge_recursive(this._bindings, query.bindings);
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

  ///
  /// Handle dynamic method calls into the method.
  ///
  /// @param  String  $method
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
}
