import 'package:eloquent/eloquent.dart';

class QueryPostgresGrammar extends QueryGrammar {
  ///
  ///All of the available clause operators.
  ///
  ///protected @var array
  ///
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
    'not ilike',
    '~',
    '&',
    '|',
    '#',
    '<<',
    '>>',
    '<<=',
    '>>=',
    '&&',
    '@>',
    '<@',
    '?',
    '?|',
    '?&',
    '||',
    '-',
    '-',
    '#-',
    'is distinct from',
    'is not distinct from',
  ];

  ///
  /// Compile a "where date" clause.
  ///
  /// [query] QueryBuilder
  /// [where] dynamic/map/array
  /// @return string
  ///
  String whereDate(QueryBuilder query, dynamic where) {
    var value = this.parameter(where['value']);
    return this.wrap(where['column']) +
        '::date ' +
        where['operator'] +
        ' ' +
        value;
  }

  ///
  /// Compile a date based where clause.
  ///
  /// @param  string  $type
  /// @param  \Illuminate\Database\Query\Builder  $query
  /// @param  array  $where
  /// @return string
  ///
  String dateBasedWhere(type, QueryBuilder query, dynamic where) {
    var value = this.parameter(where['value']);
    return 'extract(' +
        type +
        ' from ' +
        this.wrap(where['column']) +
        ') ' +
        where['operator'] +
        ' ' +
        value;
  }

  ///
  /// Compile a "JSON contains" statement into SQL.
  ///
  /// @param  string  $column
  /// @param  string  $value
  /// @return string
  ///
  String compileJsonContains(dynamic column, dynamic value) {
    //column = str_replace('->>', '->', this.wrap(column));
    final newCol = this.wrap(column).replaceAll('->>', '->');
    return '(' + newCol + ')::jsonb @> ' + value;
  }

  ///
  /// Compile the lock into SQL.
  ///
  /// [query] QueryBuilder
  /// [value]  bool|String
  /// @return String
  ///
  String compileLock(QueryBuilder query, dynamic value) {
    if (value is! String) {
      return value ? 'for update' : 'for share';
    }
    return value;
  }

  ///
  ///  Compile an insert statement into SQL.
  ///
  ///  [query]  QueryBuilder
  ///  [values] Map<String,dynamic>
  ///  `Return` String
  ///
  String compileInsert(QueryBuilder query, Map<String, dynamic> values) {
    final table = this.wrapTable(query.fromProp);
    return values.isEmpty
        ? "insert into $table} DEFAULT VALUES"
        : super.compileInsert(query, values);
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

    return this.compileInsert(query, values) +
        ' returning ' +
        this.wrap(sequence);
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
    return 'update $table set $columns$from $where'.trim();
  }

  ///
  /// Compile the columns for the update statement.
  ///
  /// @param  array   $values
  /// @return String
  ///
  String compileUpdateColumns(Map<String, dynamic> values) {
    final columns = <String>[];

    // When gathering the columns for an update statement, we'll wrap each of the
    // columns and convert it to a parameter value. Then we will concatenate a
    // list of the columns that can be added into this update query clauses.
    for (var items in values.entries) {
      final key = items.key;
      final value = items.value;
      columns.add(this.wrap(key) + ' = ' + this.parameter(value));
    }
    return columns.join(', ');
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

    if (froms.length > 0) {
      return ' from ' + froms.join(', ');
    }

    return null;
  }

  ///
  ///Compile the additional where clauses for updates with joins.
  ///
  ///@param  QueryBuilder  $query
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
  ///@param  QueryBuilder  $query
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
  /// Compile a truncate table statement into SQL.
  ///
  /// @param  \Illuminate\Database\Query\Builder  $query
  /// @return array
  ///
  Map<String, dynamic> compileTruncate(QueryBuilder query) {
    return {
      'truncate ' + this.wrapTable(query.fromProp) + ' restart identity': []
    };
  }

  String wrapValue(String value) {
    if (value == '*') {
      return value;
    }
    if (value.contains('->')) {
      return wrapJsonSelector(value);
    }
    return '"' + value.replaceAll('"', '""') + '"';
  }

  String wrapJsonSelector(String value) {
    // Divide a string pelo separador '->'
    List<String> path = value.split('->');

    // Obtém o campo inicial e aplica wrapValue nele
    String field = wrapValue(path.removeAt(0));

    // Envolve os demais atributos do caminho
    List<String> wrappedPath = wrapJsonPathAttributes(path);

    // Remove o último atributo, que será tratado de forma especial
    String attribute = wrappedPath.removeLast();

    // Se existirem outros atributos no caminho, junta-os com '->'
    if (wrappedPath.isNotEmpty) {
      return '$field->${wrappedPath.join("->")}->>$attribute';
    }

    return '$field->>$attribute';
  }

  List<String> wrapJsonPathAttributes(List<String> path) {
    // Para cada atributo do caminho, envolve-o com aspas simples
    return path.map((attribute) => "'$attribute'").toList();
  }
}
