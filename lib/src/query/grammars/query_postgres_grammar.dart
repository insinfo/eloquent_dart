import 'package:eloquent/eloquent.dart';

class QueryPostgresGrammar extends QueryGrammar {
  ///
  ///All of the available clause operators.
  ///
  ///protected @var array
  ///
  List operators = [
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
  ];

  ///
  ///Compile the lock into SQL.
  ///
  ///@param  \Illuminate\Database\Query\Builder  $query
  ///@param  bool|string  $value
  ///@return String
  ///
  String compileLock(QueryBuilder query, dynamic value) {
    if (Utils.is_string(value)) {
      return value;
    }

    return value ? 'for update' : 'for share';
  }

  ///
  ///Compile an update statement into SQL.
  ///
  ///@param  \Illuminate\Database\Query\Builder  $query
  ///@param  array  $values
  ///@return String
  ///
  String compileUpdate(QueryBuilder query, dynamic values) {
    var table = this.wrapTable(query.fromProp);

    // Each one of the columns in the update statements needs to be wrapped in the
    // keyword identifiers, also a place-holder needs to be created for each of
    // the values in the list of bindings so we can make the sets statements.
    var columns = this.compileUpdateColumns(values);

    var from = this.compileUpdateFrom(query);

    var where = this.compileUpdateWheres(query);

    return Utils.trim("update {$table} set {$columns}{$from} $where");
  }

  ///
  /// Compile the columns for the update statement.
  ///
  /// @param  array   $values
  /// @return String
  ///
  String compileUpdateColumns(Map<String, dynamic> values) {
    var columns = [];

    // When gathering the columns for an update statement, we'll wrap each of the
    // columns and convert it to a parameter value. Then we will concatenate a
    // list of the columns that can be added into this update query clauses.
    for (var items in values.entries) {
      var key = items.key;
      var value = items.value;
      columns.add(this.wrap(key) + ' = ' + this.parameter(value));
    }

    return Utils.implode(', ', columns);
  }

  ///
  ///Compile the "from" clause for an update with a join.
  ///
  ///@param  \Illuminate\Database\Query\Builder  $query
  ///@return String|null
  ///
  String? compileUpdateFrom(QueryBuilder query) {
    if (!Utils.isset(query.joinsProp)) {
      return '';
    }

    var froms = <String>[];

    // When using Postgres, updates with joins list the joined tables in the from
    // clause, which is different than other systems like MySQL. Here, we will
    // compile out the tables that are joined and add them to a from clause.
    for (var join in query.joinsProp) {
      froms.add(wrapTable(join.table));
    }

    if (Utils.count(froms) > 0) {
      return ' from ' + Utils.implode(', ', froms);
    }

    return null;
  }

  ///
  ///Compile the additional where clauses for updates with joins.
  ///
  ///@param  \Illuminate\Database\Query\Builder  $query
  ///@return String
  ///
  String compileUpdateWheres(QueryBuilder query) {
    var baseWhere = this.compileWheres(query);

    if (!Utils.isset(query.joinsProp)) {
      return baseWhere;
    }

    // Once we compile the join constraints, we will either use them as the where
    // clause or append them to the existing base where clauses. If we need to
    // strip the leading boolean we will do so when using as the only where.
    var joinWhere = this.compileUpdateJoinWheres(query);

    if (Utils.trim(baseWhere) == '') {
      return 'where ' + this.removeLeadingBoolean(joinWhere);
    }

    return baseWhere + ' ' + joinWhere;
  }

  ///
  ///Compile the "join" clauses for an update.
  ///
  ///@param  \Illuminate\Database\Query\Builder  $query
  ///@return String
  ///
  String compileUpdateJoinWheres(QueryBuilder query) {
    var joinWheres = <String>[];

    // Here we will just loop through all of the join constraints and compile them
    // all out then implode them. This should give us "where" like syntax after
    // everything has been built and then we will join it to the real wheres.
    for (var join in query.joinsProp) {
      for (var clause in join.clauses) {
        joinWheres.add(this.compileJoinConstraint(clause));
      }
    }

    return Utils.implode(' ', joinWheres);
  }

  ///
  ///Compile an insert and get ID statement into SQL.
  ///
  ///@param  \Illuminate\Database\Query\Builder  $query
  ///@param  array   $values
  ///@param  String  $sequence
  ///@return String
  ///
  String compileInsertGetId(QueryBuilder query, values, String? sequence) {
    if (Utils.is_null(sequence)) {
      sequence = 'id';
    }

    return this.compileInsert(query, values) +
        ' returning ' +
        this.wrap(sequence);
  }

  ///
  ///Compile a truncate table statement into SQL.
  ///
  ///@param  \Illuminate\Database\Query\Builder  $query
  ///@return array
  ///
  Map<String, dynamic> compileTruncate(QueryBuilder query) {
    return {
      'truncate ' + this.wrapTable(query.fromProp) + ' restart identity': []
    };
  }
}
