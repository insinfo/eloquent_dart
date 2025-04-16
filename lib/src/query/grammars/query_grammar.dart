import 'package:eloquent/eloquent.dart';

class QueryGrammar extends BaseGrammar {
  /// The grammar specific operators.
  List<String> operators = [];

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
      'compilerecursionLimit': (args) => compileRecursionLimit(args[0]),
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

  ///
  ///  The components that make up a select clause.
  ///
  ///  @var array
  ///
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

  /// Compila as Common Table Expressions (CTEs) para a query.
  ///
  /// Se não houver CTEs em [query.expressionsProp], retorna string vazia.
  /// Caso contrário, retorna algo como:
  /// `WITH RECURSIVE "cte1"(col1, col2) AS (…), "cte2" AS (…)`
  String compileExpressions(QueryBuilder query) {
    if (query.expressionsProp.isEmpty) {
      return '';
    }

    // Define se a cláusula RECURSIVE deve aparecer
    final recursive = recursiveKeyword(query.expressionsProp);

    // Monta cada CTE
    final List<String> statements = [];
    for (final expr in query.expressionsProp) {
      final name = expr['name'] as String;
      final sql = expr['query'] as String;
      final cols = expr['columns'] as List<String>?;

      // Se houver colunas, montar "(col1, col2) "
      final columnList =
          (cols != null && cols.isNotEmpty) ? '(${columnize(cols)})' : '';
      final separator = columnList.isNotEmpty
          ? ' '
          : ''; // Adiciona espaço só se houver colunas

      statements.add(
          '${wrapTable(name)}$separator$columnList as ($sql)'); // Usa 'as' minúsculo
    }

    // Junta todas as CTEs com vírgula e prépende WITH (+ RECURSIVE se necessário)
    return 'with $recursive${statements.join(', ')}';
  }

  /// Retorna 'RECURSIVE ' se alguma expressão em [expressions]
  /// tiver a flag 'recursive' = true, caso contrário retorna ''.
  String recursiveKeyword(List<Map<String, dynamic>> expressions) {
    final needsRecursive = expressions.any((e) => e['recursive'] == true);
    return needsRecursive ? 'recursive ' : '';
  }

  /**
     * Compile the recursion limit.
     *
     * @param \Illuminate\Database\Query\Builder $query
     * @return string
     */
  String compileRecursionLimit(QueryBuilder query) {
    if (query.recursionLimitProp == null) {
      return '';
    }
    return 'option (maxrecursion ${query.recursionLimitProp})';
  }

  /**
     * Compile an insert statement using a subquery into SQL.
     *
     * @param \Illuminate\Database\Query\Builder $query
     * @param array $columns
     * @param string $sql
     * @return string
     */
  String compileInsertUsing(QueryBuilder query, dynamic columns, String sql) {
    //final expressions = this.compileExpressions(query);
    //final recursionLimit = this.compileRecursionLimit(query);
    //return expressions + ' ' + ' ' + recursionLimit;
    // Obtém o nome da tabela alvo (já configurado no builder)
    final table = this.wrapTable(query.fromProp);
    // Formata a lista de colunas alvo
    final columnsSql = this.columnize(columns);
    // Monta a instrução INSERT INTO ... SELECT ...
    // O `sql` recebido já é o "SELECT ..." da subquery
    return 'insert into $table ($columnsSql) $sql';
  }

  ///
  ///  Compile a select query into SQL.
  ///
  ///  @param  QueryBuilder  $query
  ///  @return String
  ///
  String compileSelect(QueryBuilder query) {
    final queryColumns = query.getColumns();
    final original = queryColumns != null ? [...queryColumns] : null;

    if (Utils.is_null(query.columnsProp)) {
      query.columnsProp = ['*'];
    }
    final compiledComps = compileComponents(query);

    final sql = Utils.trim(concatenate(compiledComps));

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
    final sql = <String, dynamic>{};
    for (var component in this.selectComponents) {
      // To compile the query, we'll spin through each component of the query and
      // see if that component exists. If it does we'll just call the compiler
      // function for the component which is responsible for making the SQL.
      final proP = query.getProperty(component);
      var isProp = proP != null;
      if (proP is List) {
        isProp = proP.isNotEmpty;
      } else if (proP is Map) {
        isProp = proP.isNotEmpty;
      }
      if (isProp) {
        final methodName = 'compile' + Utils.ucfirst(component);
        final extraParam = proP;
        sql[component] = callMethod(methodName, [query, extraParam]);
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
  ///  [query]  QueryBuilder
  ///  [table] String|QueryExpression
  ///  `Return` String
  ///
  String? compileFrom(QueryBuilder query, dynamic table) {
    if (table == null) {
      return null; // Retorna null se a tabela for nula
    }
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
    var sql = <String>[];

    for (var join in joins) {
      var table = this.wrapTable(join.table);
      var type = join.type.toLowerCase();

      // Se for um cross join sem cláusulas, retorna apenas "cross join <table>"
      if (type == 'cross' && (join.clauses.isEmpty)) {
        sql.add("cross join $table");
        continue;
      }

      // Compila as cláusulas ON para os demais joins
      var clauses = <String>[];
      for (var clause in join.clauses) {
        clauses.add(this.compileJoinConstraint(clause));
      }

      if (clauses.isNotEmpty) {
        // Remove o booleano da primeira cláusula
        clauses[0] = this.removeLeadingBoolean(clauses[0]);
      }

      var clausesString = Utils.implode(' ', clauses);
      sql.add("$type join $table on $clausesString");
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
    bool isNested = clause['nested'] ?? false;
    if (isNested) {
      return this.compileNestedJoinConstraint(clause);
    }

    var first = this.wrap(clause['first']);
    var second;
    bool isWhereClause = clause['where'] ?? false;
    if (isWhereClause) {
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
  String compileNestedJoinConstraint(Map clause) {
    final clauses = [];
    for (var nestedClause in clause['join'].clauses) {
      clauses.add(this.compileJoinConstraint(nestedClause));
    }
    clauses[0] = this.removeLeadingBoolean(clauses[0]);
    final clausesStr = Utils.implode(' ', clauses);
    return "${clause['boolean']} ($clausesStr)";
  }

  ///
  ///  Compile the "where" portions of the query.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @return String
  ///
  String compileWheres(QueryBuilder query) {
    var sql = <String>[];

    if (Utils.array_is_empty(query.wheresProp)) {
      return '';
    }

    // Each type of where clauses has its own compiler function which is responsible
    // for actually creating the where clauses SQL. This helps keep the code nice
    // and maintainable since each clause has a very small method that it uses.
    for (var where in query.wheresProp) {
      final methodName = "where${where['type']}";

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
    if (Utils.empty(where['values'])) {
      return '0 = 1';
    }

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
  String whereDate(QueryBuilder query, dynamic where) {
    return this.dateBasedWhere('date', query, where);
  }

  ///
  /// Compile a "where time" clause.
  ///
  /// [query] QueryBuilder
  /// [where] dynamic/map/array
  /// @return string
  ///
  String whereTime(QueryBuilder query, dynamic where) {
    return dateBasedWhere('time', query, where);
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

  /// Compila uma cláusula "where" que compara duas colunas.
  ///
  /// Parâmetros:
  /// [query] - A instância de QueryBuilder (não necessariamente usada aqui, mas passada para manter consistência).
  /// [where] - Mapa com as chaves 'first', 'operator' e 'second' que representam, respectivamente, a primeira coluna, o operador e a segunda coluna.
  ///
  /// Retorna a string SQL resultante, por exemplo: "table1.col1 = table2.col2".
  String whereColumn(QueryBuilder query, Map<String, dynamic> where) {
    final firstWrapped = this.wrap(where['first']);
    final secondWrapped = this.wrap(where['second']);
    final operator = where['operator'];

    return '$firstWrapped $operator $secondWrapped';
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
    // Mapeia cada cláusula having para sua representação SQL utilizando compileHaving.
    var sqlParts = havings.map((having) => compileHaving(having)).toList();

    // Junta as partes com um espaço em branco.
    var combinedSql = sqlParts.join(' ');

    // Remove o conector booleano inicial e retorna a string final com a palavra "having".
    return 'having ' + removeLeadingBoolean(combinedSql);
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
  /// Compile the random statement into SQL.
  ///
  /// @param  string  $seed
  /// @return string
  ///
  String compileRandom($seed) {
    return 'RANDOM()';
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

    // Itera sobre cada union armazenada na propriedade unionsProp.
    for (var union in query.unionsProp) {
      sql += compileUnion(union);
    }

    // Se houver unionOrders, adiciona-os.
    if (query.unionOrdersProp.isNotEmpty) {
      sql += ' ' + compileOrders(query, query.unionOrdersProp);
    }

    // Se houver unionLimit, adiciona-o.
    if (query.unionLimit != null) {
      sql += ' ' + compileLimit(query, query.unionLimit!);
    }

    // Se houver unionOffset, adiciona-o.
    if (query.unionOffset != null) {
      sql += ' ' + compileOffset(query, query.unionOffset!);
    }

    return sql.trimLeft();
  }

  ///
  ///  Compile a single union statement.
  ///
  ///  @param  array  $union
  ///  @return String
  ///
  String compileUnion(Map<String, dynamic> union) {
    // Se o union tiver a flag 'all' verdadeira, utiliza "union all"; caso contrário, "union".
    var joiner = union['all'] == true ? ' union all ' : ' union ';
    return joiner + union['query'].toSql();
  }

  ///
  ///  Compile an exists statement into SQL.
  ///
  ///  @param \Illuminate\Database\Query\Builder $query
  ///  @return String
  ///
  String compileExists(QueryBuilder query) {
    final select = compileSelect(query);
    return "select exists($select) as ${this.wrap('exists')}";
  }

  ///
  ///  Compile an insert statement into SQL.
  ///
  ///  [query]  QueryBuilder
  ///  [values] Map<String,dynamic>
  ///  `Return` String
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
    final res = Utils.trim("update $table$joins set $columns $where");

    return this.compileExpressions(query) + ' ' + res;
  }

  ///
  /// Prepare the bindings for an update statement.
  ///
  /// @param  List  bindingsP
  /// @param  Map  valuesP
  /// @return List
  ///
  prepareBindingsForUpdate(dynamic bindingsP, dynamic valuesP) {
    // Obtém os bindings de CTEs, se existirem
    //final exprBindings = bindingsP['expressions'] ?? <dynamic>[];
    //print('prepareBindingsForUpdate $valuesP');

    // Mescla os bindings de expressions antes dos valores normais
    // ignore: unused_local_variable
    //final mergedValues = [...exprBindings, ...valuesP];

    // Remove o grupo 'expressions' para não causar binding duplicado
    //bindingsP.remove('expressions');

    return bindingsP;
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
    final res = Utils.trim("delete from $table " + where);

    return this.compileExpressions(query) + ' ' + res;
  }

  ///
  ///  Compile a truncate table statement into SQL.
  ///
  ///  @param  \Illuminate\Database\Query\Builder  $query
  ///  @return array
  ///
  Map<String, dynamic> compileTruncate(QueryBuilder query) {
    return {'truncate ' + this.wrapTable(query.fromProp): []};
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

    return segments.values
        .where((value) => value != '' && value != null)
        .join(' ');
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
