import 'package:eloquent/eloquent.dart';

import '../json_expression.dart';

class QueryMySqlGrammar extends QueryGrammar {
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
    '&',
    '|',
    '#',
    '<<',
    '>>',
    '@>',
    '<@',
    '?',
    '?|',
    '?&',
    '||',
    '-',
    '-',
    '#-'
  ];

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
    'lock',
  ];

  ///
  /// Compile a select query into SQL.
  ///
  /// @param  QueryBuilder  query
  /// @return string
  ///
  String compileSelect(QueryBuilder query) {
    var sql = super.compileSelect(query);
    if (query.unionsProp.isNotEmpty) {
      sql = '(' + sql + ') ' + this.compileUnions(query);
    }
    return sql;
  }

  ///
  /// Compile a "JSON contains" statement into SQL.
  ///
  /// @param  string  $column
  /// @param  string  $value
  /// @return string
  ///
  String compileJsonContains(column, value) {
    return 'json_contains(' + this.wrap(column) + ', ' + value + ')';
  }

  ///
  /// Compile a single union statement.
  ///
  /// @param  array  $union
  /// @return string
  ///
  String compileUnion(Map union) {
    var conjunction = union['all'] ? ' union all ' : ' union ';
    return conjunction + '(' + union['query'].toSql() + ')';
  }

  ///
  /// Compile the random statement into SQL.
  ///
  /// @param  string  $seed
  /// @return string
  ///
  String compileRandom(seed) {
    return 'RAND(' + seed + ')';
  }

  ///
  /// Compile the lock into SQL.
  ///
  /// @param QueryBuilder  $query
  /// @param  bool|string  $value
  /// @return string
  ///
  String compileLock(QueryBuilder query, value) {
    if (value is! String) {
      return value ? 'for update' : 'lock in share mode';
    }
    return value;
  }

  ///
  /// Compile an insert and get ID statement into SQL.
  ///
  ///  [query]  QueryBuilder
  ///  [values] Map<String,dynamic>
  /// @param  String  $sequence
  ///  `Return` String
  ///
  @override
  String compileInsertGetId(
      QueryBuilder query, Map<String, dynamic> values, String? sequence) {
    if (sequence == null) {
      sequence = 'id';
    }

    // return this.compileInsert(query, values) +
    //     ' returning ' +
    //     this.wrap(sequence);

    return this.compileInsert(query, values);
  }

  ///
  /// Compile an update statement into SQL.
  ///
  /// @param  QueryBuilder  $query
  /// @param  array  $values
  /// @return string
  ///
  String compileUpdate(QueryBuilder query, Map<String, dynamic> values) {
    final table = this.wrapTable(query.fromProp);

    final columns = <String>[];

    // Each one of the columns in the update statements needs to be wrapped in the
    // keyword identifiers, also a place-holder needs to be created for each of
    // the values in the list of bindings so we can make the sets statements.
    for (var entry in values.entries) {
      var key = entry.key;
      var value = entry.value;

      if (this.isJsonSelector(key)) {
        columns.add(this.compileJsonUpdateColumn(key, JsonExpression(value)));
      } else {
        columns.add(this.wrap(key) + ' = ' + this.parameter(value));
      }
    }

    final columnsStr = columns.join(', ');

    // If the query has any "join" clauses, we will setup the joins on the builder
    // and compile them so we can attach them to this update, as update queries
    // can get join statements to attach to other tables when they're needed.
    var joins = '';
    if (query.joinsProp.isNotEmpty) {
      joins = ' ' + this.compileJoins(query, query.joinsProp);
    }

    // Of course, update queries may also be constrained by where clauses so we'll
    // need to compile the where clauses and attach it to the query so only the
    // intended records are updated by the SQL statements we generate to run.
    final where = this.compileWheres(query);

    var sql = ("update $table$joins set $columnsStr $where").trimRight();

    if (query.ordersProp.isNotEmpty) {
      sql += ' ' + this.compileOrders(query, query.ordersProp);
    }

    if (query.limitProp != null) {
      sql += ' ' + this.compileLimit(query, query.limitProp!);
    }

    return (sql).trimRight();
  }

  ///
  /// Prepares a JSON column being updated using the JSON_SET function.
  ///
  /// @param  string  $key
  /// @param  \Illuminate\Database\JsonExpression  $value
  /// @return string
  ///
  String compileJsonUpdateColumn(key, JsonExpression value) {
    //var path = explode('->', key);
    List<String> path = key.split('->');

    //var field = this.wrapValue(array_shift(path));
    var field = this.wrapValue(path.removeAt(0));

    var accessor = '"\$.' + path.join('.') + '"';

    //return "{$field} = json_set({$field}, {$accessor}, {$value->getValue()})";
    return '$field = json_set($field, $accessor, ${value.getValue()})';
  }

  ///
  /// Prepare the bindings for an update statement.
  ///
  /// [bindings] List<dynamic> bindings
  /// [values] Map<String, dynamic>
  /// @return array
  ///
  List<dynamic> prepareBindingsForUpdate(bindings, values) {
    // Obtemos as chaves do Map na ordem de inserção.
    final keys = values.keys.toList();

    // Itera de trás para frente, removendo os bindings correspondentes
    // para colunas que são seletores JSON e cujo valor é booleano.
    for (int i = keys.length - 1; i >= 0; i--) {
      final column = keys[i];
      final value = values[column];
      if (isJsonSelector(column) && value is bool) {
        bindings.removeAt(i);
      }
    }
    return bindings;
  }

  /**
     * Compile an insert statement using a subquery into SQL.
     *
     * @param \Illuminate\Database\Query\Builder $query
     * @param array $columns
     * @param string $sql
     * @return string
     */
  String compileInsertUsing(QueryBuilder query, columns, String sql) {
    final insert =
        "insert into ${this.wrapTable(query.fromProp)} (${this.columnize(columns)}) ";
    return insert + this.compileExpressions(query) + ' ' + sql;
  }

  ///
  /// Compile a delete statement into SQL.
  ///
  /// @param  QueryBuilder $query
  /// @return string
  ///
  String compileDelete(QueryBuilder query) {
    final table = this.wrapTable(query.fromProp);

    final where = query.wheresProp.isNotEmpty ? this.compileWheres(query) : '';

    if (query.joinsProp.isNotEmpty) {
      final joins = ' ' + this.compileJoins(query, query.joinsProp);
      return "delete $table from $table$joins $where".trim();
    } else {
      var sql = "delete from $table $where".trim();

      if (query.ordersProp.isNotEmpty) {
        sql += ' ' + this.compileOrders(query, query.ordersProp);
      }

      if (query.limitProp != null) {
        sql += ' ' + this.compileLimit(query, query.limitProp!);
      }
      return sql;
    }
  }

  ///
  /// Wrap a single string in keyword identifiers.
  ///
  /// @param  string  $value
  /// @return string
  ///
  String wrapValue(value) {
    if (value == '*') {
      return value;
    }

    if (this.isJsonSelector(value)) {
      return this.wrapJsonSelector(value);
    }

    // return '`'.str_replace('`', '``', $value).'`';
    return '`' + value.replaceAll('`', '``') + '`';
  }

  ///
  /// Wrap the given JSON selector.
  ///
  /// @param  string  $value
  /// @return string
  ///
  String wrapJsonSelector(String value) {
    final path = value.split('->');
    final field = this.wrapValue(path.removeAt(0));
    return field + '->' + '"\$.' + path.join('.') + '"';
  }

  ///
  /// Determine if the given string is a JSON selector.
  ///
  /// @param  string  $value
  /// @return bool
  ///
  bool isJsonSelector(String value) {
    return value.contains('->');
    //Str::contains($value, '->');
  }
}
