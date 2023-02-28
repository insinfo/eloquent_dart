import 'package:eloquent/eloquent.dart';

import '../join_clause.dart';

class QueryGrammar extends BaseGrammar {
  /// chama um determinado metodo com base no nome
  /// este metodo é para evitar reflexão dart:mirror
  dynamic callMethod(
    String methodName,
    List<dynamic> positionalArguments, [
    Map<Symbol, dynamic> namedArguments = const <Symbol, dynamic>{},
  ]) {
    switch (methodName.toLowerCase()) {
      case 'compilecolumns':
        return compileColumns(positionalArguments[0], positionalArguments[1]);
      case 'compilefrom':
        return compileFrom(positionalArguments[0], positionalArguments[1]);
      case 'compilewheres':
        return compileWheres(positionalArguments[0]);
      case 'compilelimit':
        return compileLimit(positionalArguments[0], positionalArguments[1]);
      case 'compileoffset':
        return compileOffset(positionalArguments[0], positionalArguments[1]);
      //
      case 'compilegroups':
        return compileGroups(positionalArguments[0], positionalArguments[1]);
      case 'compilehaving':
        return compileHaving(positionalArguments[0]);
      case 'compileorders':
        return compileOrders(positionalArguments[0], positionalArguments[1]);
      case 'compileaggregate':
        return compileAggregate(positionalArguments[0], positionalArguments[1]);
      case 'compilejoins':
        return compileJoins(positionalArguments[0], positionalArguments[1]);

      //wheres
      case 'wherenested':
        return whereNested(positionalArguments[0], positionalArguments[1]);
      case 'wheresub':
        return whereSub(positionalArguments[0], positionalArguments[1]);
     
      case 'wherebasic':
        return whereBasic(positionalArguments[0], positionalArguments[1]);
      case 'wherebetween':
        return whereBetween(positionalArguments[0], positionalArguments[1]);
      case 'whereexists':
        return whereExists(positionalArguments[0], positionalArguments[1]);
      case 'wherenotexists':
        return whereNotExists(positionalArguments[0], positionalArguments[1]);
      case 'wherein':
        return whereIn(positionalArguments[0], positionalArguments[1]);
      case 'wherenotin':
        return whereNotIn(positionalArguments[0], positionalArguments[1]);
      case 'whereinsub':
        return whereInSub(positionalArguments[0], positionalArguments[1]);
      case 'wherenotinsub':
        return whereNotInSub(positionalArguments[0], positionalArguments[1]);
      case 'wherenull':
        return whereNull(positionalArguments[0], positionalArguments[1]);
      case 'wherenotnull':
        return whereNotNull(positionalArguments[0], positionalArguments[1]);
      case 'wheredate':
        return whereDate(positionalArguments[0], positionalArguments[1]);
      case 'whereday':
        return whereDay(positionalArguments[0], positionalArguments[1]);
      case 'wheremonth':
        return whereMonth(positionalArguments[0], positionalArguments[1]);
      case 'whereyear':
        return whereYear(positionalArguments[0], positionalArguments[1]);
      case 'whereraw':
        return whereRaw(positionalArguments[0], positionalArguments[1]);

      default:
        throw Exception("method '$methodName' not exist in QueryGrammar class");
    }
  }

  ///
  ///  The components that make up a select clause.
  ///
  ///  @var array
  ///
  List<String> selectComponents = [
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

  ///
  ///  Compile a select query into SQL.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @return String
  ///
  String compileSelect(QueryBuilder query) {
    var queryColumns = query.getColumns();
    var original = queryColumns != null ? [...queryColumns] : null;

    if (Utils.is_null(query.columnsProp)) {
      query.columnsProp = ['*'];
    }
    var compiledComps = compileComponents(query);
   // print('compileSelect compiledComps $compiledComps');
    var sql = Utils.trim(concatenate(compiledComps));
    // print('compileSelect sql $sql');

    query.setColumns(original);

    return sql;
  }

  ///
  ///  Compile the components necessary for a select clause.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @return array Map
  ///
  Map<String, dynamic> compileComponents(QueryBuilder query) {
    var sql = <String, dynamic>{};

    for (var component in this.selectComponents) {
      // To compile the query, we'll spin through each component of the query and
      // see if that component exists. If it does we'll just call the compiler
      // function for the component which is responsible for making the SQL.
      if (!Utils.is_null_or_empty(query.getProperty(component))) {
        final methodName = 'compile' + Utils.ucfirst(component);

        //print('QueryGrammar@compileComponents this: ${this}');
        //print('QueryGrammar@compileComponents property: ${component}');
        var extraParam = query.getProperty(component);
        //print('QueryGrammar@compileComponents extraParam $extraParam');

        //sql[component] = Utils.call_method(this, methodName, [query, extraParam]);
        sql[component] = callMethod(methodName, [query, extraParam]);
        // print('QueryGrammar@compileComponents methodName: $methodName');
        // print('QueryGrammar@compileComponents sql: $sql');
      }
    }

    return sql;
  }

  ///
  ///  Compile an aggregated select clause.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  query
  ///  @param  array Map aggregate
  ///  @return String
  ///
  String compileAggregate(QueryBuilder query, Map<String, dynamic> aggregate) {
    var column = columnize(aggregate['columns']);
    // print('compileAggregate aggregate: $aggregate');
    // print('compileAggregate column: $column');

    // If the query has a "distinct" constraint and we're not asking for all columns
    // we need to prepend "distinct" onto the column name so that the query takes
    // it into account when it performs the aggregating operations on the data.
    if (query.distinctProp && column != '*') {
      column = 'distinct ' + column;
    }

    return 'select ' + aggregate['function'] + '(' + column + ') as aggregate';
  }

  ///
  ///  Compile the "select *" portion of the query.
  ///
  ///  [query] QueryBuilder \Illuminate\Database\Query\Builder 
  ///  [columns] List<String> | List<dynamic> | List<QueryExpression> 
  ///  @return String|null
  ///
  String? compileColumns(QueryBuilder query, columns) {

    // If the query is actually performing an aggregating select, we will let that
    // compiler handle the building of the select clauses, as it will need some
    // more syntax that is best handled by that function to keep things neat.
    if (query.aggregateProp != null) {
      return null;
    }

    var select = query.distinctProp ? 'select distinct ' : 'select ';

    final result = select + this.columnize(columns);

    return result;
  }

  ///
  ///  Compile the "from" portion of the query.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  String  $table
  ///  @return String
  ///
  String compileFrom(QueryBuilder query, String table) {
    return 'from ' + this.wrapTable(table);
  }

  ///
  ///  Compile the "join" portions of the query.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $joins
  ///  @return String
  ///
  String compileJoins(QueryBuilder query, List<JoinClause> joins) {
    //print('compileJoins joins: $joins');
    var sql = [];

    for (var join in joins) {
      var table = this.wrapTable(join.table);

      // First we need to build all of the "on" clauses for the join. There may be many
      // of these clauses so we will need to iterate through each one and build them
      // separately, then we'll join them up into a single string when we're done.
      dynamic clauses = [];

      for (var clause in join.clauses) {
        clauses.add(this.compileJoinConstraint(clause));
      }

      // Once we have constructed the clauses, we'll need to take the boolean connector
      // off of the first clause as it obviously will not be required on that clause
      // because it leads the rest of the clauses, thus not requiring any boolean.
      clauses[0] = this.removeLeadingBoolean(clauses[0]);

      clauses = Utils.implode(' ', clauses);

      var type = join.type;

      // Once we have everything ready to go, we will just concatenate all the parts to
      // build the final join statement SQL for the query and we can then return the
      // final clause back to the callers as a single, stringified join statement.
      sql.add("$type join $table on $clauses");
    }

    return Utils.implode(' ', sql);
  }

  ///
  ///  Create a join clause constraint segment.
  ///
  ///  @param  array  $clause
  ///  @return String
  ///
  String compileJoinConstraint(Map<String, dynamic> clause) {
    if (clause['nested']) {
      return this.compileNestedJoinConstraint(clause);
    }

    var first = this.wrap(clause['first']);
    var second;
    if (clause['where']) {
      if (clause['operator'] == 'in' || clause['operator'] == 'not in') {
        second = '(' +
            Utils.implode(', ', Utils.array_fill(0, clause['second'], '?')) +
            ')';
      } else {
        second = '?';
      }
    } else {
      second = this.wrap(clause['second']);
    }

    return "${clause['boolean']} $first ${clause['operator']} $second";
  }

  ///
  ///  Create a nested join clause constraint segment.
  ///
  ///  @param  array  $clause
  ///  @return String
  ///
  String compileNestedJoinConstraint(dynamic clause) {
    // $clauses = [];

    // foreach ($clause['join']->clauses as $nestedClause) {
    //     $clauses[] = this.compileJoinConstraint($nestedClause);
    // }

    // $clauses[0] = this.removeLeadingBoolean($clauses[0]);

    // $clauses = implode(' ', $clauses);

    // return "{$clause['boolean']} ({$clauses})";
    return '';
  }

  ///
  ///  Compile the "where" portions of the query.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @return String
  ///
  String compileWheres(QueryBuilder query) {
    //print('QueryGrammar@compileWheres');
    var sql = <String>[];

    if (Utils.array_is_empty(query.wheresProp)) {
      return '';
    }

    // Each type of where clauses has its own compiler function which is responsible
    // for actually creating the where clauses SQL. This helps keep the code nice
    // and maintainable since each clause has a very small method that it uses.
    for (var where in query.wheresProp) {
      final methodName = "where${where['type']}";
      //print('QueryGrammar@compileWheres methodName: $methodName');
      //call whereBasic
      //sql.add(where['boolean'] +  ' ' +  Utils.call_method(this, methodName, [query, where]));

      sql.add(where['boolean'] + ' ' + callMethod(methodName, [query, where]));
    }

    // If we actually have some where clauses, we will strip off the first boolean
    // operator, which is added by the query builders for convenience so we can
    // avoid checking for the first clauses in each of the compilers methods.
    if (Utils.count(sql) > 0) {
      var sqlRe = Utils.implode(' ', sql);

      return 'where ' + removeLeadingBoolean(sqlRe);
    }

    return '';
  }

  ///
  ///  Compile a nested where clause.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $where
  ///  @return String
  ///
  String whereNested(QueryBuilder query, Map<String, dynamic> where) {
    var nested = where['query'];

    return '(' + Utils.substr(this.compileWheres(nested), 6) + ')';
  }

  ///
  ///  Compile a where condition with a sub-select.
  ///
  ///  @param  \Illuminate\Database\Query\Builder $query
  ///  @param  array   $where
  ///  @return String
  ///
  String whereSub(QueryBuilder query, Map<String, dynamic> where) {
    var select = this.compileSelect(where['query']);

    return this.wrap(where['column']) + ' ' + where['operator'] + " ($select)";
  }

  ///
  ///  Compile a basic where clause.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $where
  ///  @return String
  ///
  String whereBasic(QueryBuilder query, Map<String, dynamic> where) {
    var value = this.parameter(where['value']);

    return this.wrap(where['column']) + ' ' + where['operator'] + ' ' + value;
  }

  ///
  ///  Compile a "between" where clause.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $where
  ///  @return String
  ///
  String whereBetween(QueryBuilder query, Map<String, dynamic> where) {
    var between = where['not'] ? 'not between' : 'between';

    return this.wrap(where['column']) + ' ' + between + ' ? and ?';
  }

  ///
  ///  Compile a where exists clause.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $where
  ///  @return String
  ///
  String whereExists(QueryBuilder query, Map<String, dynamic> where) {
    return 'exists (' + compileSelect(where['query']) + ')';
  }

  ///
  ///  Compile a where exists clause.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $where
  ///  @return String
  ///
  String whereNotExists(QueryBuilder query, Map<String, dynamic> where) {
    return 'not exists (' + compileSelect(where['query']) + ')';
  }

  ///
  ///  Compile a "where in" clause.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $where
  ///  @return String
  ///
  String whereIn(QueryBuilder query, Map<String, dynamic> where) {
    //TODO checar isso  if (empty($where['values'])) {
    if (Utils.empty(where['values'])) {
      return '0 = 1';
    }
    //print('whereIn ${where['values'].runtimeType}' );
    List<dynamic> values = where['values'];
    

    var valuesString = this.parameterize(values);

    return this.wrap(where['column']) + ' in (' + valuesString + ')';
  }

  ///
  ///  Compile a "where not in" clause.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $where
  ///  @return String
  ///
  String whereNotIn(QueryBuilder query, Map<String, dynamic> where) {
    if (Utils.empty(where['values'])) {
      return '1 = 1';
    }

    var values = this.parameterize(where['values']);

    return this.wrap(where['column']) + ' not in (' + values + ')';
  }

  ///
  ///  Compile a where in sub-select clause.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $where
  ///  @return String
  ///
  String whereInSub(QueryBuilder query, Map<String, dynamic> where) {
    var select = this.compileSelect(where['query']);

    return this.wrap(where['column']) + ' in (' + select + ')';
  }

  ///
  ///  Compile a where not in sub-select clause.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $where
  ///  @return String
  ///
  String whereNotInSub(QueryBuilder query, Map<String, dynamic> where) {
    var select = this.compileSelect(where['query']);

    return this.wrap(where['column']) + ' not in (' + select + ')';
  }

  ///
  ///  Compile a "where null" clause.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $where
  ///  @return String
  ///
  String whereNull(QueryBuilder query, Map<String, dynamic> where) {
    return this.wrap(where['column']) + ' is null';
  }

  ///
  ///  Compile a "where not null" clause.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $where
  ///  @return String
  ///
  String whereNotNull(QueryBuilder query, Map<String, dynamic> where) {
    return this.wrap(where['column']) + ' is not null';
  }

  ///
  ///  Compile a "where date" clause.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $where
  ///  @return String
  ///
  String whereDate(QueryBuilder query, where) {
    return this.dateBasedWhere('date', query, where);
  }

  ///
  ///  Compile a "where day" clause.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $where
  ///  @return String
  ///
  String whereDay(QueryBuilder query, where) {
    return this.dateBasedWhere('day', query, where);
  }

  ///
  ///  Compile a "where month" clause.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $where
  ///  @return String
  ///
  String whereMonth(QueryBuilder query, where) {
    return this.dateBasedWhere('month', query, where);
  }

  ///
  ///  Compile a "where year" clause.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $where
  ///  @return String
  ///
  String whereYear(QueryBuilder query, where) {
    return this.dateBasedWhere('year', query, where);
  }

  ///
  ///  Compile a date based where clause.
  ///
  ///  @param  String  $type
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $where
  ///  @return String
  ///
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

  ///
  ///  Compile a raw where clause.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $where
  ///  @return String
  ///
  String whereRaw(QueryBuilder query, where) {
    return where['sql'];
  }

  ///
  ///  Compile the "group by" portions of the query.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $groups
  ///  @return String
  ///
  String compileGroups(QueryBuilder query, groups) {
    return 'group by ' + this.columnize(groups);
  }

  ///
  ///  Compile the "having" portions of the query.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $havings
  ///  @return String
  ///
  String compileHavings(
      QueryBuilder query, List<Map<String, dynamic>> havings) {
    //TODO implementar havings
    // var sql = implode(' ', array_map([$this, 'compileHaving'], $havings));
    // return 'having '+this.removeLeadingBoolean(sql);
    throw UnimplementedError();
  }

  ///
  ///  Compile a single having clause.
  ///
  ///  @param  array   $having
  ///  @return String
  ///
  String compileHaving(Map<String, dynamic> having) {
    // If the having clause is "raw", we can just return the clause straight away
    // without doing any more processing on it. Otherwise, we will compile the
    // clause into SQL based on the components that make it up from builder.
    if (having['type'] == 'raw') {
      return having['boolean'] + ' ' + having['sql'];
    }
    return this.compileBasicHaving(having);
  }

  ///
  ///  Compile a basic having clause.
  ///
  ///  @param  array   $having
  ///  @return String
  ///
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

  ///
  ///  Compile the "order by" portions of the query.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $orders
  ///  @return String
  ///
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

  ///
  ///  Compile the "limit" portions of the query.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  int  $limit
  ///  @return String
  ///
  String compileLimit(QueryBuilder query, int limit) {
    return 'limit $limit';
  }

  ///
  ///  Compile the "offset" portions of the query.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  int  $offset
  ///  @return String
  ///
  String compileOffset(QueryBuilder query, int offset) {
    return 'offset $offset';
  }

  ///
  ///  Compile the "union" queries attached to the main query.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @return String
  ///
  String compileUnions(QueryBuilder query) {
    var sql = '';

    // for(var union in query.unionsProp ) {
    //     sql += compileUnion(union);
    // }

    // if (isset($query->unionOrders)) {
    //     $sql .= ' '.this.compileOrders($query, $query->unionOrders);
    // }

    // if (isset($query->unionLimit)) {
    //     $sql .= ' '.this.compileLimit($query, $query->unionLimit);
    // }

    // if (isset($query->unionOffset)) {
    //     $sql .= ' '.this.compileOffset($query, $query->unionOffset);
    // }

    // return ltrim($sql);

    throw UnimplementedError();
  }

  ///
  ///  Compile a single union statement.
  ///
  ///  @param  array  $union
  ///  @return String
  ///
  String compileUnion(Map<String, dynamic> union) {
    var joiner = union['all'] ? ' union all ' : ' union ';

    return joiner + union['query'].toSql();
  }

  ///
  ///  Compile an exists statement into SQL.
  ///
  ///  @param \Illuminate\Database\Query\Builder $query
  ///  @return String
  ///
  String compileExists(QueryBuilder query) {
    var select = compileSelect(query);

    return "select exists($select) as {this.wrap('exists')}";
  }

  ///
  ///  Compile an insert statement into SQL.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param [values] List<Map<String,dynamic>> | Map<String,dynamic>
  ///  @return String
  ///
  String compileInsert(QueryBuilder query, Map<String, dynamic> values) {
    // Essentially we will force every insert to be treated as a batch insert which
    // simply makes creating the SQL easier for us since we can utilize the same
    // basic routine regardless of an amount of records given to us to insert.
    var table = this.wrapTable(query.fromProp);

    // if (!Utils.is_array(values)) {
    //   values = [values];
    // }
    var columns = this.columnize(values.keys.toList());
    // We need to build a list of parameter place-holders of values that are bound
    // to the query. Each insert should have the exact same amount of parameter
    // bindings so we will loop through the record and parameterize them all.
    var parameters = this.parameterize(values.values.toList());
    return "insert into $table ($columns) values ($parameters)";
  }

  ///
  ///  Compile an insert and get ID statement into SQL.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array   $values
  ///  @param  String  $sequence
  ///  @return String
  ///
  String compileInsertGetId(
      QueryBuilder query, Map<String, dynamic> values, String? sequence) {
    return this.compileInsert(query, values);
  }

  ///
  ///  Compile an update statement into SQL.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  array  $values
  ///  @return String
  ///
  String compileUpdate(QueryBuilder query, Map<String, dynamic> values) {
    var table = this.wrapTable(query.fromProp);

    // Each one of the columns in the update statements needs to be wrapped in the
    // keyword identifiers, also a place-holder needs to be created for each of
    // the values in the list of bindings so we can make the sets statements.
    dynamic columns = [];
    for (var entry in values.entries) {
      columns.add(this.wrap(entry.key) + ' = ' + this.parameter(entry.value));
    }
    columns = Utils.implode(', ', columns);
    // // If the query has any "join" clauses, we will setup the joins on the builder
    // // and compile them so we can attach them to this update, as update queries
    // // can get join statements to attach to other tables when they're needed.
    var joins = '';
    if (query.joinsProp.isNotEmpty) {
      joins = ' ' + this.compileJoins(query, query.joinsProp);
    }

    // // Of course, update queries may also be constrained by where clauses so we'll
    // // need to compile the where clauses and attach it to the query so only the
    // // intended records are updated by the SQL statements we generate to run.
    var where = this.compileWheres(query);
    return Utils.trim("update $table$joins set $columns $where");
  }

  ///
  ///  Compile a delete statement into SQL.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @return String
  ///
  String compileDelete(QueryBuilder query) {
    var table = this.wrapTable(query.fromProp);
    var where =
        Utils.is_array(query.wheresProp) ? this.compileWheres(query) : '';
    return Utils.trim("delete from $table " + where);
  }

  ///
  ///  Compile a truncate table statement into SQL.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @return array
  ///
  Map<String, dynamic> compileTruncate(QueryBuilder query) {
    return {'truncate ' + this.wrapTable(query.from): []};
  }

  ///
  ///  Compile the lock into SQL.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @param  bool|string  $value
  ///  @return String
  ///
  String compileLock(QueryBuilder query, dynamic value) {
    return Utils.is_string(value) ? value : '';
  }

  ///
  ///  Determine if the grammar supports savepoints.
  ///
  ///  @return bool
  ///
  bool supportsSavepoints() {
    return true;
  }

  ///
  ///  Compile the SQL statement to define a savepoint.
  ///
  ///  @param  String  $name
  ///  @return String
  ///
  String compileSavepoint(String name) {
    return 'SAVEPOINT ' + name;
  }

  ///
  ///  Compile the SQL statement to execute a savepoint rollback.
  ///
  ///  @param  String  $name
  ///  @return String
  ///
  String compileSavepointRollBack(String name) {
    return 'ROLLBACK TO SAVEPOINT ' + name;
  }

  ///
  ///  Concatenate an array of segments, removing empties and nulls
  ///
  ///  @param  array   $segments
  ///  @return String
  ///
  String concatenate(Map<String, dynamic> segments) {
    // return Utils.implode(' ', Utils.array_filter(segments,  (value) {
    //     return value != '';
    // }));

    return segments.values.where((value) => value != '' && value != null ).join(' ');
  }

  ///
  ///  Remove the leading boolean from a statement.
  ///
  ///  @param  String  $value
  ///  @return String
  ///
  String removeLeadingBoolean(String value) {
    //return preg_replace('/and |or /i', '', $value, 1);
    return value.replaceFirst(RegExp(r"and |or ", caseSensitive: true), '');
  }
}
