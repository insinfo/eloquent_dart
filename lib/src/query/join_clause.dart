import 'package:eloquent/eloquent.dart';

/// TODO implement extends QueryBuilder
class JoinClause {
  ///
  /// The type of join being performed.
  ///
  /// @var string
  ///
  String type;

  ///
  /// The table the join clause is joining to.
  ///
  /// @var string | QueryExpression
  ///
  dynamic table;

  ///
  /// The "on" clauses for the join.
  ///
  /// @var array
  ///
  List<Map<String, dynamic>> clauses = [];

  ///
  /// The "on" bindings for the join.
  ///
  /// @var array
  ///
  List bindingsLocal = [];

  bool isLateral; // <-- Adicionado

  /// Adiciona uma cláusula ON TRUE.
  JoinClause onTrue([String boolean = 'and']) {
    return this.on(QueryExpression('TRUE'), null, null, boolean, false);
  }

  ///
  /// Create a new join clause instance.
  ///
  /// @param  String  $type
  /// @param  String  $table
  ///
  JoinClause(this.type, this.table,
      [QueryBuilder? parentQuery, this.isLateral = false]) {
    //: super(parentQuery.getConnection(), parentQuery.getGrammar(),  parentQuery.getProcessor())
    //public function __construct(Builder $parentQuery, $type, $table)
    /// TODO implement extends QueryBuilder
    /// $this->parentQuery = $parentQuery;
    //  super(
    //         $parentQuery->getConnection(), $parentQuery->getGrammar(), $parentQuery->getProcessor()
    //     );
  }

  // /**
  //  * Get a new instance of the join clause builder.
  //  *
  //  * @return \Illuminate\Database\Query\JoinClause
  //  */
  // public function newQuery()
  // {
  //     return new static($this->parentQuery, $this->type, $this->table);
  // }

  // /**
  //  * Create a new query instance for sub-query.
  //  *
  //  * @return \Illuminate\Database\Query\Builder
  //  */
  // protected function forSubQuery()
  // {
  //     return $this->parentQuery->newQuery();
  // }

  ///
  /// Add an "on" clause to the join.
  ///
  /// On clauses can be chained, e.g.
  ///
  ///  join.on('contacts.user_id', '=', 'users.id')
  ///       .on('contacts.info_id', '=', 'info.id')
  ///
  /// will produce the following SQL:
  ///
  /// on `contacts`.`user_id` = `users`.`id`  and `contacts`.`info_id` = `info`.`id`
  ///
  /// @param  String|\Closure  $first
  /// @param  String|null  $operator
  /// @param  String|null  $second
  /// @param  String  $boolean
  /// @param  bool  $where
  /// @return $this
  ///
  /// @throws \InvalidArgumentException
  ///
  JoinClause on(dynamic first,
      [String? operator,
      dynamic second,
      String boolean = 'and',
      bool where = false]) {
    if (first is Function) {
      return this.nest(first, boolean);
    }

    if (where) {
      this.bindingsLocal.add(second);
    }

    if (where &&
        (operator == 'in' || operator == 'not in') &&
        Utils.is_array(second)) {
      second = Utils.count(second);
    }

    var nested = false;

    this.clauses.add({
      'first': first,
      'operator': operator,
      'second': second,
      'boolean': boolean,
      'where': where,
      'nested': nested
    });

    return this;
  }

  ///
  /// Add an "or on" clause to the join.
  ///
  /// @param  String|\Closure  $first
  /// @param  String|null  $operator
  /// @param  String|null  $second
  /// @return \Illuminate\Database\Query\JoinClause
  ///
  JoinClause orOn(dynamic first, [String? operator, dynamic second]) {
    return this.on(first, operator, second, 'or');
  }

  ///
  /// Add an "on where" clause to the join.
  ///
  /// @param  String|\Closure  $first
  /// @param  String|null  $operator
  /// @param  String|null  $second
  /// @param  String  $boolean
  /// @return \Illuminate\Database\Query\JoinClause
  ///
  JoinClause where(dynamic first,
      [String? operator, dynamic second, String boolean = 'and']) {
    return this.on(first, operator, second, boolean, true);
  }

  ///
  /// Add an "or on where" clause to the join.
  ///
  /// @param  String|\Closure  $first
  /// @param  String|null  $operator
  /// @param  String|null  $second
  /// @return \Illuminate\Database\Query\JoinClause
  ///
  JoinClause orWhere(dynamic first, [String? operator, dynamic second]) {
    return this.on(first, operator, second, 'or', true);
  }

  ///
  /// Add an "on where is null" clause to the join.
  ///
  /// @param  String  $column
  /// @param  String  $boolean
  /// @return \Illuminate\Database\Query\JoinClause
  ///
  JoinClause whereNull(String column, [String boolean = 'and']) {
    return this.on(column, 'is', QueryExpression('null'), boolean, false);
  }

  ///
  /// Add an "or on where is null" clause to the join.
  ///
  /// @param  String  $column
  /// @return \Illuminate\Database\Query\JoinClause
  ///
  JoinClause orWhereNull(String column) {
    return this.whereNull(column, 'or');
  }

  ///
  /// Add an "on where is not null" clause to the join.
  ///
  /// @param  String  $column
  /// @param  String  $boolean
  /// @return \Illuminate\Database\Query\JoinClause
  ///
  JoinClause whereNotNull(String column, [String boolean = 'and']) {
    return this.on(column, 'is', QueryExpression('not null'), boolean, false);
  }

  ///
  /// Add an "or on where is not null" clause to the join.
  ///
  /// @param  String  $column
  /// @return \Illuminate\Database\Query\JoinClause
  ///
  JoinClause orWhereNotNull(String column) {
    return this.whereNotNull(column, 'or');
  }

  ///
  /// Add an "on where in (...)" clause to the join.
  ///
  /// @param  String  $column
  /// @param  array  $values
  /// @return \Illuminate\Database\Query\JoinClause
  ///
  JoinClause whereIn(String column, List values) {
    return this.on(column, 'in', values, 'and', true);
  }

  ///
  /// Add an "on where not in (...)" clause to the join.
  ///
  /// @param  String  $column
  /// @param  array  $values
  /// @return \Illuminate\Database\Query\JoinClause
  ///
  JoinClause whereNotIn(String column, List values) {
    return this.on(column, 'not in', values, 'and', true);
  }

  ///
  /// Add an "or on where in (...)" clause to the join.
  ///
  /// @param  String  $column
  /// @param  array  $values
  /// @return \Illuminate\Database\Query\JoinClause
  ///
  JoinClause orWhereIn(String column, List values) {
    return this.on(column, 'in', values, 'or', true);
  }

  ///
  /// Add an "or on where not in (...)" clause to the join.
  ///
  /// @param  String  $column
  /// @param  array  $values
  /// @return \Illuminate\Database\Query\JoinClause
  ///
  JoinClause orWhereNotIn(String column, List values) {
    return this.on(column, 'not in', values, 'or', true);
  }

  ///
  /// Add a nested where statement to the query.
  ///
  /// @param  \Closure  $callback
  /// @param  String   $boolean
  /// @return \Illuminate\Database\Query\JoinClause
  ///
  JoinClause nest(Function callback, [String boolean = 'and']) {
    final join = JoinClause(this.type, this.table);

    callback(join);

    if (Utils.count(join.clauses) != 0) {
      var nested = true;

      this.clauses.add({
        'nested': nested,
        'join': join,
        'boolean': boolean,
      });
      this.bindingsLocal =
          Utils.array_merge(this.bindingsLocal, join.bindingsLocal);
    }

    return this;
  }

  ///
  /// Add a raw "on" clause to the join.
  ///
  /// @param  String  $sql
  /// @param  String  $boolean
  /// @return $this
  ///
  JoinClause onRaw(String sql, [String boolean = 'and']) {
    this.clauses.add({
      'type': 'raw',
      'sql': sql,
      'boolean': boolean,
    });
    return this;
  }
}
