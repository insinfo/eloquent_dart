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
    'from': [],
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

  ///
  /// Create a new query builder instance.
  ///
  /// @param  \Illuminate\Database\ConnectionInterface  $connection
  /// @param  \Illuminate\Database\Query\Grammars\Grammar  $grammar
  /// @param  \Illuminate\Database\Query\Processors\Processor  $processor
  ///
  QueryBuilder(this.connection, this.grammar, this.processor);

  ///
  /// Set the columns to be selected.
  ///
  /// [columnsP]  List | dynamic
  /// @return $this
  ///
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

  ///
  /// Add a subselect expression to the query.
  ///
  /// @param  Funcion|QueryBuilder|string $query
  /// @param  String  $as
  /// @return QueryBuilder
  ///
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

  ///
  /// Add a new "raw" select expression to the query.
  ///
  /// @param  String  $expression
  /// @param  array   $bindings
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  QueryBuilder selectRaw(String expression, [List? bindingsP = const []]) {
    this.addSelect(QueryExpression(expression));

    if (bindingsP != null) {
      this.addBinding(bindingsP, 'select');
    }

    return this;
  }

  ///
  /// Add a raw from clause to the query.
  ///
  /// @param  string  $expression
  /// @param  mixed   $bindings
  /// @return \Illuminate\Database\Query\Builder|static
  ///
  /// Example:
  ///
  ///  var map = await db
  ///     .table('clientes')
  ///     .selectRaw('clientes.*')
  ///     .fromRaw('(SELECT * FROM public.clientes) AS clientes')
  ///     .limit(1)
  ///     .first();
  ///
  ///
  QueryBuilder fromRaw(String expression, [List? $bindings = const []]) {
    this.fromProp = QueryExpression(expression);
    this.addBinding($bindings, 'from');
    return this;
  }

  ///
  /// Creates a subquery and parse it.
  ///
  /// [query]  Function|QueryBuilder|String
  /// `Return` List [String query ,List Bindings]
  ///
  List createSub(dynamic query) {
    // If the given query is a Closure, we will execute it while passing in a new
    // query instance to the Closure. This will give the developer a chance to
    // format and work with the query before we cast it to a raw SQL string.

    if (query is Function) {
      var callback = query;
      callback(query = this.forSubQuery());
    }

    final result = this.parseSub(query);

    return result;
  }

  ///
  /// Parse the subquery into SQL and bindings.
  ///
  /// [query] dynamic
  /// `Return` List [String query ,List Bindings]
  ///
  List parseSub(dynamic query) {
    if (query is QueryBuilder) {
      return [query.toSql(), query.getBindings()];
    } else if (query is String) {
      return [query, []];
    } else if (query is QueryExpression) {
      // adicionado para lidar com join lateral
      // Se for uma QueryExpression, obtém o valor (SQL bruto)
      // e assume que não há bindings associados *a esta expressão* aqui.
      // Bindings para a expressão bruta devem ser adicionados separadamente se necessário.
      return [query.getValue(), []];
    } else {
      throw InvalidArgumentException();
    }
  }

  ///
  /// Add a new select column to the query.
  ///
  /// [columnP]  QueryExpression List | dynamic
  /// @return $this
  ///
  QueryBuilder addSelect(dynamic columnP) {
    //var column = is_array(column) ? column : func_get_args();
    var col = columnP is List ? columnP : [columnP];
    this.columnsProp = Utils.array_merge(columnsProp, col);
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
  /// [tableP] QueryExpression | String
  /// `Return QueryBuilder`
  ///
  QueryBuilder from(dynamic tableP) {
    this.fromProp = tableP;
    return this;
  }

  ///
  /// Add a join clause to the query.
  ///
  /// [table] String|QueryExpression name of table
  /// [one]  String | Function(JoinClause)
  /// [operator] String  Example: '=', 'in', 'not in'
  /// [two]  string|null
  /// [type]  String  Example: 'inner', 'left'
  /// [where]  bool
  /// `Return` this QueryBuilder
  ///
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
  /// Add a subquery join clause to the query.
  ///
  /// [query]  QueryBuilder|String
  /// [alias]  string
  /// [first]  string
  /// [operator]  string|null
  /// [second] string|null
  /// [type]  string  inner|left|right|outer
  /// [where]  bool
  /// `Return` QueryBuilder|static
  ///
  /// @throws \InvalidArgumentException
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
  ///
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

  QueryBuilder crossJoin(dynamic table,
      [dynamic first, String? operator, dynamic second]) {
    if (first != null) {
      // Se for passado um join condicional, delega para o método join com tipo 'cross'
      return this.join(table, first, operator, second, 'cross');
    }
    // Caso contrário, adiciona um JoinClause do tipo 'cross' sem cláusula ON
    this.joinsProp.add(JoinClause('cross', table, this));
    return this;
  }

  /// Apply the [callback] only if [condition] is true.
  /// Retorna o próprio QueryBuilder para encadeamento (fluent interface).
  QueryBuilder when(dynamic condition, Function(QueryBuilder) callback) {
    // Se condition for "truthy" (diferente de null/false/0/''), chama o callback
    if (condition != null && condition != false) {
      callback(this);
    }
    return this;
  }

  ///
  /// Add a basic where clause to the query.
  ///
  /// [column] String | Map | Function(QueryBuilder)
  /// [operator]  String Examples: '=', '<', '>', '<>'
  /// @param  mixed   $value
  /// @param  String  $boolean
  /// @return $this
  ///
  /// throws \InvalidArgumentException
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

  /// Adiciona uma cláusula WHERE “flexível” à consulta.
  ///
  /// Este método tenta emular o comportamento do método `where` do Laravel, onde:
  ///
  /// - Se o primeiro parâmetro for um `Map`, ele assume que o mapa contém pares de chave/valor e
  ///   delega para uma cláusula WHERE aninhada (onde cada chave é comparada com o operador `'='`).
  /// - Se o primeiro parâmetro for uma função que recebe um `QueryBuilder`, ele invoca essa função
  ///   para construir uma sub cláusula WHERE aninhada.
  /// - Se a função for chamada com 2 argumentos (por exemplo: `whereFlex('email', 'test@example.com')`),
  ///   o método deve interpretar o segundo parâmetro como o valor e assumir implicitamente o operador
  ///   `'='`.
  /// - Se for chamada com 3 argumentos (por exemplo: `whereFlex('age', '>', 18)`), o segundo parâmetro
  ///   é interpretado como o operador e o terceiro como o valor.
  /// - Se o valor for uma função (Closure) que recebe um `QueryBuilder`, a cláusula será tratada como uma subconsulta.
  /// - Se o valor for `null`, o método invoca internamente `whereNull`, desde que o operador seja `'='`,
  ///   `'=='`, `'!='` ou `'<>'`. Caso contrário, se o operador não for compatível com valores nulos,
  ///   espera-se que lance uma exceção (InvalidArgumentException).
  ///
  /// **Limitações e Cenários Problemáticos**:
  ///
  /// 1. **Detecção do número de argumentos**:
  ///    Diferentemente do PHP (que utiliza `func_num_args()`), no Dart os parâmetros opcionais sempre
  ///    recebem um valor (mesmo que seja o valor padrão). Assim, não há uma forma nativa de diferenciar
  ///    uma chamada com 2 argumentos de uma chamada com 3 argumentos de forma exata.
  ///    O método utiliza uma função auxiliar (_countNonDefaultArguments) como heurística para tentar
  ///    inferir quantos argumentos foram explicitamente passados, mas essa abordagem pode falhar em casos
  ///    ambíguos.
  ///
  /// 2. **Caso do uso de valores nulos**:
  ///    Por exemplo, se o usuário chamar:
  ///    ```dart
  ///    qbFlex.whereFlex('deleted_at', '=', null);
  ///    ```
  ///    espera-se que o método interprete isso como uma cláusula "where deleted_at is null".
  ///    Contudo, devido à heurística utilizada, o método pode interpretar essa chamada como se tivesse
  ///    sido feita com 2 argumentos – fazendo com que o operador `'='` seja considerado como valor, o que
  ///    resultará na SQL gerada:
  ///    ```sql
  ///    select * from "users" where "deleted_at" = ?
  ///    ```
  ///    com um binding cujo valor é `'='` em vez de `null`.
  ///
  /// 3. **Operadores não válidos com null**:
  ///    Se for usado um operador diferente de `'='`, `'=='`, `'!='` ou `'<>'` ao passar explicitamente um valor null,
  ///    espera-se que o método lance uma exceção. No entanto, se o método interpretar a chamada como tendo
  ///    apenas 2 parâmetros, essa validação não ocorrerá e o SQL gerado não corresponderá à intenção do
  ///    desenvolvedor.
  ///
  /// **Exemplo de uso esperado (sem problemas):**
  ///
  /// ```dart
  /// // Interpretação de 2 argumentos: operador '=' é inferido
  /// qbFlex.whereFlex('email', 'test@example.com');
  /// // Gera: where "email" = ?
  /// // Binding: ['test@example.com']
  ///
  /// // Chamada com 3 argumentos para operadores válidos:
  /// qbFlex.whereFlex('age', '>', 18);
  /// // Gera: where "age" > ?
  /// // Binding: [18]
  /// ```
  ///
  /// **Cenário problemático:**
  ///
  /// ```dart
  /// // A intenção é que este código gere uma cláusula "where deleted_at is null"
  /// // mas, devido à heurística, pode produzir:
  /// qbFlex.whereFlex('deleted_at', '=', null);
  /// // Gera: where "deleted_at" = ?
  /// // Binding: ['=']   <-- binding incorreto, pois o operador '=' foi interpretado como valor
  /// ```
  ///
  /// Devido a essas limitações intrínsecas da linguagem Dart (especialmente a dificuldade de detectar
  /// precisamente o número de argumentos passados), é possível que a funcionalidade de `whereFlex` não
  /// se comporte como o esperado em todos os cenários, sendo recomendada cautela ao utilizá-la em casos
  /// onde valores nulos e operadores precisam ser diferenciados com precisão.
  ///
  /// **Retorno:**
  /// Retorna a instância atual de `QueryBuilder` para permitir encadeamento de métodos.
  QueryBuilder whereFlex(dynamic column,
      [dynamic operator, // Mantido como dynamic
      dynamic value,
      String boolean = 'and']) {
    // Caso 1: Map
    if (column is Map) {
      return this.whereNested((query) {
        column.forEach((k, v) {
          query.where(k, '=', v);
        }); // Use where normal aqui
      }, boolean);
    }

    // Caso 2: Function no primeiro argumento
    if (column is Function(QueryBuilder)) {
      return this.whereNested(column, boolean);
    }

    // --- Lógica Refinada para Determinar Operador e Valor ---
    String? finalOperator;
    dynamic finalValue;

    // Verifica se o SEGUNDO argumento (operator) FOI fornecido
    if (operator != null) {
      // Verifica se o TERCEIRO argumento (value) também foi fornecido
      if (value != null) {
        // Cenário: where('column', 'op', 'val')
        // O segundo argumento DEVE ser um operador String válido
        if (operator is String && isValidOperator(operator)) {
          finalOperator = operator;
          finalValue = value;
        } else {
          throw InvalidArgumentException(
              'When 3 arguments are provided, the second must be a valid string operator. Got type ${operator.runtimeType} ("$operator")');
        }
      } else {
        // Cenário: where('column', 'something') - 'something' pode ser operador ou valor
        // Verifica se 'something' (passado como operator) é um operador String VÁLIDO
        if (operator is String && isValidOperator(operator)) {
          // É um operador válido! Tratar como where('column', 'op'). O valor é implicitamente null.
          finalOperator = operator;
          finalValue = null;
          // A validação posterior (invalidOperatorAndValue) tratará se op + null é válido
        } else {
          // NÃO é um operador válido. Tratar como where('column', 'value').
          finalOperator = '='; // Operador implícito
          finalValue = operator; // O segundo argumento era o valor
        }
      }
    } else {
      // Cenário where('column') - Segundo argumento (operator) é null.
      // Tratar como where('column', '=', null), que será pego pela lógica de null abaixo.
      finalOperator = '=';
      finalValue = null;
    }
    // --- Fim da Lógica Refinada ---

    // Caso 3: Valor final é Função (whereSub)
    if (finalValue is Function(QueryBuilder)) {
      // É crucial que 'finalOperator' seja um operador válido aqui.
      // A lógica acima deve garantir isso ou ter lançado exceção.
      // Se finalOperator for nulo aqui, algo está errado, usar '=' como fallback seguro.
      return this.whereSub(column, finalOperator, finalValue, boolean); //?? '='
    }

    // Caso 4: Valor final é null (whereNull / whereNotNull)
    if (finalValue == null) {
      bool not = (finalOperator == '!=' || finalOperator == '<>');
      if (finalOperator == '=' || finalOperator == '==' || not) {
        return this.whereNull(column, boolean, not);
      }
      // Se não for um operador de (in)igualdade, a validação abaixo DEVE falhar.
    }

    // Validação final: Verifica combinações ilegais
    if (this.invalidOperatorAndValue(finalOperator, finalValue)) {
      // Se esta validação falhar, significa que a lógica acima não tratou
      // corretamente ou o usuário forneceu uma combinação inválida (ex: '>', null)
      throw InvalidArgumentException(
          'Illegal operator "$finalOperator" and value combination ($finalValue). Operator must be "=" or "!=" or "<>" if value is null.');
    }

    // Caso 5: Cláusula WHERE básica
    final type = 'Basic';
    this.wheresProp.add({
      'type': type,
      'column': column,
      'operator': finalOperator, // Definitivamente não nulo aqui
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

  /**
     * Add a "where" clause comparing two columns to the query.
     *
     * @param  string|array  $first
     * @param  string|null  $operator
     * @param  string|null  $second
     * @param  string|null  $boolean
     * @return \Illuminate\Database\Query\Builder|static
     */
  QueryBuilder whereColumn(dynamic first,
      [String? operator, dynamic second, String boolean = 'and']) {
    // Se "first" for um array (Lista ou Map), assumimos que é um conjunto de condições
    // e delegamos a adição das condições ao método addArrayOfWheres.
    if (first is List || first is Map) {
      return this.addArrayOfWheres(first, boolean, 'whereColumn');
    }

    // Verifica se o operador fornecido é válido.
    // Se o operador não for encontrado na lista de operadores válidos da classe (_operators)
    // ou na lista de operadores da gramática (grammar.getOperators()),
    // assumimos que o desenvolvedor está encurtando o uso do operador '='.
    if (operator == null ||
        !(Utils.in_array(operator.toLowerCase(), this._operators) ||
            Utils.in_array(
                operator.toLowerCase(), this.grammar.getOperators()))) {
      second = operator;
      operator = '=';
    }

    // Define o tipo da cláusula "where" como "Column"
    var type = 'Column';

    // Adiciona a cláusula na lista de condições (wheresProp)
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
    // Utiliza whereNested para agrupar as condições
    return this.whereNested((QueryBuilder query) {
      // Se "column" for um Map (array associativo de condições)
      if (column is Map) {
        column.forEach((key, value) {
          // Se a chave for numérica e o valor for uma lista,
          // assumimos que a lista contém os parâmetros para chamar o método where dinamicamente.
          if (key is int && value is List) {
            if (method == 'where') {
              Function.apply(query.where, value);
            } else if (method == 'orWhere') {
              Function.apply(query.orWhere, value);
            } else {
              // Se o método não for reconhecido, usa-se o método where por padrão.
              Function.apply(query.where, value);
            }
          } else {
            // Caso contrário, trata a chave como nome da coluna e o valor como o valor a ser comparado.
            query.where(key, '=', value);
          }
        });
      }
      // Se "column" for uma lista, itera sobre cada item
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
            // Se o item for um mapa, itera sobre cada chave e valor
            item.forEach((key, value) {
              query.where(key, '=', value);
            });
          }
        }
      }
    }, boolean);
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
  /// Original
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
    final query = this.forSubQuery(); // Use forSubQuery para consistência
    callback(query);

    // Garante um operador padrão se for nulo, embora a lógica anterior deva prevenir isso
    operator ??= '=';

    this.wheresProp.add({
      'type': type,
      'column': column,
      'operator': operator, // Operador final determinado
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
  /// [values] List<dynamic> | QueryBuilder | Function
  /// @param  String  $boolean
  /// @param  bool    $not
  /// @return $this
  ///
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
  /// Básico: `orWhereDate('created_at', '=', someDate)`
  QueryBuilder orWhereDate(String column, String operator, DateTime? value) {
    return this.whereDate(column, operator, value, 'or');
  }

  /// Add a "where time" statement to the query.
  /// [column] Ex: 'created_at'
  /// [operator] Ex: '=', '<', '>'
  /// [value] Ex: '12:00:00' ou um DateTime cujo horário interessa
  /// [boolean] Se é 'and' ou 'or'
  QueryBuilder whereTime(String column, String operator, dynamic value,
      [String boolean = 'and']) {
    // Supondo que addDateBasedWhere('Time', ...) trunque/compare somente a parte de hora
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
  /// Exemplo: `whereFirstNameAndLastName('John', 'Doe')` será traduzido para:
  /// ```dart
  /// where('first_name', '=', 'John', 'and')
  ///   .where('last_name', '=', 'Doe', 'and')
  /// ```
  ///
  /// O método espera que o nome comece com "where" e o restante seja composto
  /// por segmentos separados por "And" ou "Or".
  QueryBuilder dynamicWhere(String method, List<dynamic> parameters) {
    // Remove o prefixo "where"
    final finder = method.substring(5);

    // Processa a string, separando os segmentos e conectores.
    // Usa um regex para capturar "And" ou "Or" quando seguido de letra maiúscula.
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
    // Converte o segmento de CamelCase para snake_case.
    final column = Utils.toSnakeCase(segment);
    // Adiciona a cláusula where usando o operador "=".
    // Aqui assume-se que o método where já está implementado na classe.
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

  /// Adiciona uma cláusula "having" bruta (raw) à consulta.
  ///
  /// [sql] é a expressão SQL bruta.
  /// [bindings] são os valores que devem ser vinculados à consulta (por exemplo, parâmetros).
  /// [boolean] indica o conector lógico da cláusula (por padrão, "and").
  /// Retorna a instância atual de QueryBuilder para permitir encadeamento de chamadas.
  QueryBuilder havingRaw(String sql,
      [List bindings = const [], String boolean = 'and']) {
    const type = 'raw';

    // Adiciona um registro em havingsProp com as informações necessárias
    this.havingsProp.add({
      'type': type,
      'sql': sql,
      'boolean': boolean,
    });

    // Adiciona os valores de binding à seção 'having'
    this.addBinding(bindings, 'having');

    return this;
  }

  /// Adiciona uma cláusula "having" bruta (raw) com conector "or" à consulta.
  ///
  /// [sql] é a expressão SQL bruta.
  /// [bindings] são os valores que devem ser vinculados à consulta.
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
  /// [seed] pode ser usado em alguns SGDBs para gerar "random com semente".
  QueryBuilder inRandomOrder([String seed = '']) {
    // grammar.compileRandom(seed) retornaria algo como "RAND()" ou "RANDOM()"
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
    // Se a página não for informada, resolve a página atual.
    page ??= PaginationUtils.resolveCurrentPage(pageName);

    // Obtém o total de registros para a paginação.
    int total = await getCountForPagination(columns);

    // Se houver registros, obtém os resultados da página solicitada; caso contrário, retorna uma lista vazia.
    List<Map<String, dynamic>> results =
        total > 0 ? await forPage(page, perPage).get(columns) : [];

    // Retorna o objeto LengthAwarePaginator com os resultados e metadados.
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
  /// Mais eficiente em grandes conjuntos pois não faz count(*).
  Future<DefaultPaginator> simplePaginate({
    int perPage = 15,
    List<String> columns = const ['*'],
    String pageName = 'page',
    int? page,
  }) async {
    // 1. Determina a página atual
    page ??= PaginationUtils.resolveCurrentPage(pageName);

    // 2. Carrega (perPage + 1) resultados p/ detectar se há próxima página
    this.skip((page - 1) * perPage).take(perPage + 1);
    final results = await this.get(columns);

    // 3. Se vieram mais registros que `perPage`, tem mais páginas
    bool hasMorePages = results.length > perPage;

    // Se veio 1 a mais, remove o extra (pois só queremos exibir 'perPage' itens)
    List<Map<String, dynamic>> pageItems = results;
    if (hasMorePages) {
      pageItems = results.sublist(0, perPage);
    }

    // 4. Monta o paginador
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
  /// Retorna a contagem total de registros para a paginação.
  Future<int> getCountForPagination(
      [List<String> columns = const ['*']]) async {
    backupFieldsForCount();

    // Define a agregação para contagem, removendo eventuais aliases.
    aggregateProp = {
      'function': 'count',
      'columns': clearSelectAliases(columns)
    };

    // Executa a consulta (nesse caso, a consulta de contagem).
    List<Map<String, dynamic>> results = await get();

    aggregateProp = null;

    restoreFieldsForCount();

    // Se houver agrupamentos, retorna o número de resultados.
    if (groupsProp.isNotEmpty) {
      return results.length;
    }

    // Caso contrário, espera que o resultado possua uma chave 'aggregate'.
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
  /// Faz o backup dos campos utilizados na contagem da paginação.
  void backupFieldsForCount() {
    // Backup dos campos da consulta.
    backups['orders'] = ordersProp;
    backups['limit'] = limitProp;
    backups['offset'] = offsetProp;
    backups['columns'] = columnsProp;

    // Define os campos de consulta como nulos (ou listas vazias) para a contagem.
    ordersProp = [];
    limitProp = null;
    offsetProp = null;
    columnsProp = null;

    // Backup dos bindings para 'order' e 'select'.
    bindingBackups['order'] = bindings['order'];
    bindingBackups['select'] = bindings['select'];

    // Limpa os bindings de 'order' e 'select' para que não interfiram na contagem.
    bindings['order'] = [];
    bindings['select'] = [];
  }

  ///
  /// Remove the column aliases since they will break count queries.
  ///
  /// @param  array  $columns
  /// @return array
  ///
  /// Remove aliases de colunas para evitar problemas na contagem.
  /// Exemplo: "users.name as user_name" será transformado em "users.name".
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
  /// Restaura os campos que foram modificados para a contagem da paginação.
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
  /// O callback recebe (lista de resultados, número da página).
  /// Retorna false se for interrompido antes, ou true se iterou tudo.
  Future<bool> chunk(
    int count,
    FutureOr<bool> Function(List<Map<String, dynamic>> chunk, int page)
        callback,
  ) async {
    int page = 1;

    while (true) {
      // Carrega o próximo bloco
      final results = await this.forPage(page, count).get();
      final countResults = results.length;

      if (countResults == 0) {
        // Não há mais registros
        break;
      }

      // Executa o callback; se ele retornar false, paramos o loop
      final cbResult = await callback(results, page);
      if (cbResult == false) {
        return false;
      }

      page++;

      // Se veio menos que "count", não há mais nada pra buscar
      if (countResults < count) {
        break;
      }
    }

    return true;
  }

  /// Chunk the results of a query by comparing numeric IDs.
  ///
  /// [count]: quantos registros por “bloco”
  /// [callback]: recebe a lista do bloco e deve retornar bool
  /// [column]: nome da coluna de ID, por padrão 'id'
  /// [alias]: se o campo tiver alias diferente, ex: 'users.id as user_id'.
  ///
  /// Exemplo de uso:
  ///   await query.chunkById(100, (chunk) async { ... }, 'id');
  Future<bool> chunkById(
    int count,
    FutureOr<bool> Function(List<Map<String, dynamic>> chunk) callback, {
    String column = 'id',
    String? alias,
  }) async {
    alias ??= column;
    dynamic lastId = 0; // valor inicial

    while (true) {
      // Carrega os próximos [count] registros, onde column > lastId
      final results = await this.forPageAfterId(count, lastId, column).get();
      final countResults = results.length;

      if (countResults == 0) {
        break;
      }

      // Chama o callback para este bloco
      final cbResult = await callback(results);
      if (cbResult == false) {
        return false;
      }

      // Pega o valor do ID do último registro retornado
      final lastRow = results.last;
      final dynamic aliasValue = lastRow[alias];
      if (aliasValue == null) {
        // se não achamos o valor do ID no registro, paramos
        break;
      }
      lastId = aliasValue;

      // Se vieram menos registros que “count”, não há mais nada
      if (countResults < count) {
        break;
      }
    }

    return true;
  }

  /// Execute a callback over each item while chunking.
  ///
  /// [callback] é chamado para cada item individual. Se retornar false, interrompe.
  /// [count] é o tamanho do bloco para chunking.
  /// Retorna true se concluiu tudo, ou false se interrompido antes.
  Future<bool> each(
    FutureOr<bool> Function(Map<String, dynamic> row, int index) callback, [
    int count = 1000,
  ]) async {
    // (Opcional) no Laravel, exige que haja orderBy definido antes de each()
    int globalIndex = 0; // Contador geral, across chunks
    return await this.chunk(count, (chunkRows, page) async {
      for (int i = 0; i < chunkRows.length; i++) {
        final row = chunkRows[i];
        // callback recebe (row, índice global ou local)
        final cbResult = await callback(row, globalIndex);
        if (cbResult == false) {
          return false; // Interrompe chunk e devolve false
        }
        globalIndex++;
      }
      return true; // continuar para o próximo chunk
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
  /// Em Laravel, `implode($column, $glue)` combina os valores em uma só string.
  /// Aqui, retorna a string concatenada.
  Future<String> implode(String column, [String glue = '']) async {
    // 1. Obtém a lista de valores da coluna usando pluck
    final dynamic result = await this.pluck(column);
    // 2. Se pluck retornar uma lista, converte cada item para string e faz a junção
    if (result is List) {
      return result.map((item) => item?.toString() ?? '').join(glue);
    }
    // 3. Caso não seja lista (ou se pluck ainda não estiver completo), retorna vazio
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
    //a constant __FUNCTION__  retorna o nome da corrent função https://www.php.net/manual/en/language.constants.magic.php
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
  /// [function] Pode ser "count", "sum", "avg", "min" ou "max".
  /// [columns] Lista de colunas (por padrão ['*']).
  /// Retorna um valor [num] (int ou double).
  Future<num> numericAggregate(String function,
      [List<String> columns = const ['*']]) async {
    // Chama o método aggregate para obter o resultado cru
    final dynamic result = await this.aggregate(function, columns);
    // Se não houver resultado, retorna 0
    if (result == null) {
      return 0;
    }
    // Se já for int ou double, devolve diretamente
    if (result is int || result is double) {
      return result;
    }
    // Converte para string para analisar se possui ponto decimal
    final String resultStr = result.toString();
    // Se não tiver ponto decimal, parse como int
    if (!resultStr.contains('.')) {
      return int.tryParse(resultStr) ?? 0;
    }
    // Caso contrário, converte para double
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
  /// Se não existir nenhum registro correspondente a [attributes]:
  ///   -> executa insert(attributes + values).
  /// Senão:
  ///   -> atualiza o primeiro registro correspondente.
  ///
  /// Retorna `true` em caso de sucesso, `false` se falhar (ou não alterar nada).
  Future<bool> updateOrInsert(
    Map<String, dynamic> attributes, [
    Map<String, dynamic> values = const {},
  ]) async {
    // 1. Verifica se existe algum registro com os atributos fornecidos
    final bool recordExists = await this.where(attributes).exists();

    if (!recordExists) {
      // 2. Se não existir, faz insert
      final inserted = await this.insert({
        ...attributes,
        ...values,
      });

      // O retorno de insert pode variar (bool, int, etc.),
      // dependendo do seu ConnectionInterface. Ajuste conforme necessário:
      if (inserted is bool) {
        return inserted; // true ou false
      } else if (inserted is num) {
        return inserted > 0; // se for a contagem de rows inseridas
      }
      return inserted != null; // fallback simples
    } else {
      // 3. Se existir, atualiza apenas 1 registro
      final int affectedRows =
          await this.where(attributes).limit(1).update(values);

      // 4. Converte o número de linhas afetadas em bool
      return affectedRows > 0;
    }
  }

  /// Increment a column's value by a given amount.
  ///
  /// [column] Nome da coluna que será incrementada.
  /// [amount] Valor a ser somado à coluna.
  /// [extra]  Valores adicionais que podem ser atualizados no mesmo update.
  /// Retorna a quantidade de linhas afetadas (geralmente int).
  Future<int> increment(String column,
      [num amount = 1, Map<String, dynamic> extra = const {}]) async {
    // 2. Wrap do nome da coluna para garantir escape (ex: `"table"."column"`)
    final wrapped = this.grammar.wrap(column);
    // 3. Monta o Map de colunas, criando uma expressão do tipo "<coluna> + <amount>"
    //    e faz merge com possíveis colunas extras:
    final Map<String, dynamic> columnsToUpdate = {
      ...extra,
      column: this.raw('$wrapped + $amount'),
    };
    // 4. Chama o update(...) passando as colunas calculadas
    final int affected = await this.update(columnsToUpdate);
    // 5. Retorna o número de linhas afetadas (dependerá da implementação do update)
    return affected;
  }

  /// Decrement a column's value by a given amount.
  ///
  /// [column] Nome da coluna que será decrementada.
  /// [amount] Valor a ser subtraído da coluna.
  /// [extra]  Valores adicionais que podem ser atualizados no mesmo update.
  /// Retorna a quantidade de linhas afetadas (geralmente int).
  Future<int> decrement(String column,
      [num amount = 1, Map<String, dynamic> extra = const {}]) async {
    // 2. Wrap do nome da coluna para garantir escape (ex: `"table"."column"`)
    final wrapped = this.grammar.wrap(column);

    // 3. Monta o Map de colunas, criando uma expressão do tipo "<coluna> - <amount>"
    //    e faz merge com possíveis colunas extras:
    final Map<String, dynamic> columnsToUpdate = {
      ...extra,
      column: this.raw('$wrapped - $amount'),
    };

    // 4. Chama o update(...) passando as colunas calculadas
    final int affected = await this.update(columnsToUpdate);

    // 5. Retorna o número de linhas afetadas (dependerá da implementação do update)
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

    // Mescla as cláusulas WHERE
    this.wheresProp.addAll(wheresP);
    // Mescla os bindings do tipo 'where'
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

  /// Adiciona um INNER JOIN LATERAL à consulta.
  ///
  /// [subquery] pode ser um QueryBuilder, uma Closure (Function) ou uma String SQL bruta.
  /// [alias] é o alias obrigatório para a subconsulta lateral.
  /// [onCallback] é uma função que recebe um JoinClause para definir as condições ON.
  /// Frequentemente para JOIN LATERAL, a condição é `ON TRUE`.
  QueryBuilder joinLateral(
      dynamic subquery, String alias, Function(JoinClause) onCallback) {
    return _addLateralJoin('inner', subquery, alias, onCallback);
  }

  /// Adiciona um LEFT JOIN LATERAL à consulta.
  ///
  /// [subquery] pode ser um QueryBuilder, uma Closure (Function) ou uma String SQL bruta.
  /// [alias] é o alias obrigatório para a subconsulta lateral.
  /// [onCallback] é uma função que recebe um JoinClause para definir as condições ON.
  /// Frequentemente para JOIN LATERAL, a condição é `ON TRUE`.
  QueryBuilder leftJoinLateral(
      dynamic subquery, String alias, Function(JoinClause) onCallback) {
    return _addLateralJoin('left', subquery, alias, onCallback);
  }

  /// Método auxiliar para adicionar joins laterais.
  QueryBuilder _addLateralJoin(String type, dynamic subquery, String alias,
      Function(JoinClause) onCallback) {
    // Cria a subconsulta e obtém SQL + bindings
    final res = createSub(subquery);

    final sql = res[0];
    final bindings = res[1];

    // Cria a expressão para a subconsulta ( "(subconsulta) as alias" )
    final expression = QueryExpression('($sql) as ${grammar.wrapTable(alias)}');

    // Adiciona os bindings da subconsulta ao tipo 'join'
    addBinding(bindings, 'join');

    // Cria o JoinClause, marcando como lateral
    final join = JoinClause(type, expression, this, true);

    // Aplica as condições ON usando o callback fornecido
    onCallback(join);

    // Adiciona o JoinClause configurado à lista de joins da consulta principal
    joinsProp.add(join);

    // Adiciona os bindings das cláusulas ON ao tipo 'join'
    addBinding(join.bindingsLocal, 'join');

    return this;
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
