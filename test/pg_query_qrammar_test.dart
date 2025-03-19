import 'package:test/test.dart';
import 'package:eloquent/eloquent.dart';

class FakeConnection implements ConnectionInterface {
  @override
  QueryBuilder table(String table) {
    throw UnimplementedError();
  }

  @override
  QueryExpression raw(value) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>?> selectOne(String query,
      [List bindings = const [], int? timeoutInSeconds]) {
    throw UnimplementedError();
  }

  @override
  Future<List<Map<String, dynamic>>> select(String query,
      [List bindings = const [],
      bool useReadPdo = true,
      int? timeoutInSeconds]) {
    throw UnimplementedError();
  }

  @override
  Future<PDOResults> insert(String query,
      [List bindings = const [], int? timeoutInSeconds]) {
    throw UnimplementedError();
  }

  @override
  Future<dynamic> update(String query,
      [List bindings = const [], int? timeoutInSeconds]) {
    throw UnimplementedError();
  }

  @override
  Future<int> delete(String query,
      [List bindings = const [], int? timeoutInSeconds]) {
    throw UnimplementedError();
  }

  @override
  Future<PDOResults> statement(String query,
      [List bindings = const [], int? timeoutInSeconds]) {
    throw UnimplementedError();
  }

  @override
  Future<int> affectingStatement(String query,
      [List bindings = const [], int? timeoutInSeconds]) {
    throw UnimplementedError();
  }

  @override
  Future<int> unprepared(String query, int? timeoutInSeconds) {
    throw UnimplementedError();
  }

  @override
  dynamic prepareBindings(List bindings) {
    throw UnimplementedError();
  }

  @override
  Future<dynamic> transaction(Future<dynamic> Function(Connection ctx) callback,
      [int? timeoutInSeconds]) {
    throw UnimplementedError();
  }

  @override
  int transactionLevel() {
    throw UnimplementedError();
  }

  @override
  Future<dynamic> pretend(Function callback) {
    throw UnimplementedError();
  }
}

class FakeQueryBuilder extends QueryBuilder {
  FakeQueryBuilder({List<String>? columns, String? from})
      : super(FakeConnection(), QueryPostgresGrammar(), Processor()) {
    columnsProp = columns;
    fromProp = from;
  }

  @override
  List<dynamic>? getColumns() {
    return columnsProp;
  }
}

void main() {
  late QueryGrammar grammar;

  setUp(() {
    grammar = QueryPostgresGrammar();
  });

  test('callMethod - chama método existente', () {
    final qb = FakeQueryBuilder(columns: ['id', 'name']);

    final result = grammar.callMethod('compileColumns', [qb, qb.columnsProp]);
    expect(result, equals('select "id", "name"'),
        reason: 'Deve compor colunas corretamente');
  });

  test('callMethod - método inexistente gera exceção', () {
    expect(
      () => grammar.callMethod('metodoInexistente', []),
      throwsA(isA<Exception>()),
    );
  });

  test('compileSelect - retorna SQL com colunas e from', () {
    final qb = FakeQueryBuilder(columns: ['id', 'nome'], from: 'users');
    final sql = grammar.compileSelect(qb);
    expect(sql, contains('select "id", "nome" from "users"'));
  });

  test('compileSelect - whereBasic', () {
    final qb = QueryBuilder(FakeConnection(), grammar, Processor());
    qb.select(['id', 'nome']);
    qb.from('users');
    qb.where('email', '=', 'foo@example.com', 'and');
    final sql = grammar.compileSelect(qb);

    expect(
      sql,
      contains('where "email" = ?'),
      reason: 'Deve conter a cláusula where básica',
    );
  });

  test('compileSelect - limit e offset', () {
    final qb = FakeQueryBuilder(columns: ['id', 'nome'], from: 'users');
    qb.limit(10);
    qb.offset(5);
    final sql = grammar.compileSelect(qb);
    expect(sql, contains('limit 10'));
    expect(sql, contains('offset 5'));
  });

  test('compileSelect - group by', () {
    final qb = FakeQueryBuilder(columns: ['id', 'nome'], from: 'users');
    qb.groupBy(['nome']);
    final sql = grammar.compileSelect(qb);
    expect(sql, contains('group by \"nome\"'));
  });

  test('compileSelect - having', () {
    final qb = FakeQueryBuilder(columns: ['id', 'nome'], from: 'users');
    qb.havingRaw('having COUNT("id") > 1');
    final sql = grammar.compileSelect(qb);
    expect(sql, contains('having COUNT("id") > 1'));
  });

  test('compileSelect - union', () {
    final qb = FakeQueryBuilder(columns: ['id', 'nome'], from: 'users');
    qb.unionsProp = [
      {
        'all': false,
        'query': FakeQueryBuilder(columns: ['foo', 'bar'], from: 'admins'),
      }
    ];
    final sql = grammar.compileSelect(qb);
    expect(sql, contains('union select \"foo\", \"bar\" from \"admins\"'));
  });

  test('compileSelect - whereIn, whereNotIn', () {
    final qb = QueryBuilder(FakeConnection(), grammar, Processor());
    qb.select(['id']);
    qb.from('users');
    qb.whereIn('id', [1, 2, 3]);
    qb.whereNotIn('status', ['inactive', 'banned']);

    final sql = grammar.compileSelect(qb);
    // Esperamos algo como: where \"id\" in (?, ?, ?) and \"status\" not in (?, ?)
    expect(sql, contains('\"id\" in (?, ?, ?)'));
    expect(sql, contains('\"status\" not in (?, ?)'));
  });

  test('compileSelect - whereBetween', () {
    final qb = QueryBuilder(FakeConnection(), grammar, Processor());
    qb.select(['id']);
    qb.from('products');
    qb.whereBetween('price', [10, 50], 'and', false);
    final sql = grammar.compileSelect(qb);
    expect(sql, contains('where "price" between ? and ?'));
  });

  test('compileSelect - whereNull, whereNotNull', () {
    final qb = QueryBuilder(FakeConnection(), grammar, Processor());
    qb.select(['id']);
    qb.from('users');
    qb.whereNull('deleted_at');
    qb.whereNotNull('created_at');
    final sql = grammar.compileSelect(qb);
    expect(sql, contains('"deleted_at" is null'));
    expect(sql, contains('"created_at" is not null'));
  });

  test('compileAggregate', () {
    final qb = FakeQueryBuilder();
    qb.aggregateProp = {
      'function': 'count',
      'columns': ['*'],
    };
    final result = grammar.compileAggregate(qb, qb.aggregateProp!);
    expect(result, equals('select count(*) as aggregate'));
  });

  test('compileJoins', () {
    final qb =
        FakeQueryBuilder(columns: ['users.id', 'profiles.bio'], from: 'users');

    qb.join('profiles', 'profiles.user_id', '=', 'users.id', 'inner');
    final sql = grammar.compileSelect(qb);

    expect(
        sql,
        contains(
            'inner join \"profiles\" on \"profiles\".\"user_id\" = \"users\".\"id\"'));
  });

  test('compileInsert', () {
    final qb = QueryBuilder(FakeConnection(), grammar, Processor());
    qb.from('users');
    final sql = grammar
        .compileInsert(qb, {'name': 'John', 'email': 'john@example.com'});

    expect(sql,
        contains('insert into \"users\" (\"name\", \"email\") values (?, ?)'));
  });

  test('compileInsertGetId', () {
    final qb = QueryBuilder(FakeConnection(), grammar, Processor());
    qb.from('users');
    final sql = grammar.compileInsertGetId(qb, {'name': 'Jane'}, 'id');
    expect(sql, contains('insert into \"users\" (\"name\") values (?)'));
  });

  test('compileUpdate', () {
    final qb = QueryBuilder(FakeConnection(), grammar, Processor());
    qb.from('users');
    final sql = grammar.compileUpdate(qb, {'name': 'Mark', 'age': 30});
    expect(sql, contains('update \"users\" set \"name\" = ?, \"age\" = ?'));
  });

  test('compileDelete', () {
    final qb = QueryBuilder(FakeConnection(), grammar, Processor());
    qb.from('users');
    final sql = grammar.compileDelete(qb);
    expect(sql, contains('delete from \"users\"'));
  });

  test('compileTruncate', () {
    final qb = FakeQueryBuilder(from: 'users'); // Set the table via from
    final mapResult = grammar.compileTruncate(qb);
    expect(mapResult.keys.first, contains('truncate "users"'));
  });

  test('compileExists', () {
    final qb = QueryBuilder(FakeConnection(), grammar, Processor());
    qb.from('users');
    qb.select(['id']);
    final sql = grammar.compileExists(qb);
    expect(sql, contains('select exists('));
    expect(sql, contains('as "exists"'));
  });

  test('prepareBindingsForUpdate', () {
    final bindings = ['John', 'john@example.com', 30];
    final values = {'name': 'John', 'email': 'john@example.com', 'age': 30};
    expect(grammar.prepareBindingsForUpdate(bindings, values), bindings);
    final bindingsWithNull = ['John', null, 30];
    final valuesWithNull = {'name': 'John', 'email': null, 'age': 30};
    expect(grammar.prepareBindingsForUpdate(bindingsWithNull, valuesWithNull),
        bindingsWithNull);
  });

  test('whereTime', () {
    var qb = QueryBuilder(FakeConnection(), grammar, Processor());
    qb.select(['*']);
    qb.from('events');

    // Teste com operador '='
    qb.whereTime('start_time', '=', '10:00:00');
    expect(grammar.compileSelect(qb), contains('select * from "events" where extract(time from "start_time") = ?'));

    // Teste com operador '!='
    qb = QueryBuilder(FakeConnection(), grammar, Processor());
    qb.select(['*']);
    qb.from('events');
    qb.whereTime('start_time', '!=', '10:00:00');
    expect(grammar.compileSelect(qb), contains('select * from "events" where extract(time from "start_time") != ?'));

    // Teste com operador '>'
    qb = QueryBuilder(FakeConnection(), grammar, Processor());
    qb.select(['*']);
    qb.from('events');
    qb.whereTime('start_time', '>', '10:00:00');
    expect(grammar.compileSelect(qb), contains('select * from "events" where extract(time from "start_time") > ?'));

    // Teste com operador '<'
    qb = QueryBuilder(FakeConnection(), grammar, Processor());
    qb.select(['*']);
    qb.from('events');
    qb.whereTime('start_time', '<', '10:00:00');
    expect(grammar.compileSelect(qb), contains('select * from "events" where extract(time from "start_time") < ?'));
  });

  test('compileSelect - sem from', () {
    final qb = FakeQueryBuilder(columns: ['1']);
    final sql = grammar.compileSelect(qb);
    expect(sql, 'select "1"');
  });

  test('compileSelect - distinct com múltiplas colunas', () {
    final qb = FakeQueryBuilder(columns: ['id', 'name'], from: 'users');
    qb.distinctProp = true;
    final sql = grammar.compileSelect(qb);
    expect(sql, 'select distinct "id", "name" from "users"');
  });

  test('compileSelect - combinações de cláusulas', () {
    final qb = QueryBuilder(FakeConnection(), grammar, Processor());
    qb
        .select(['id', 'name'])
        .from('users')
        .where('age', '>', 25)
        .orderBy('name')
        .limit(10)
        .offset(5);
    final sql = grammar.compileSelect(qb);
    expect(
        sql,
        contains(
            'select "id", "name" from "users" where "age" > ? order by "name" asc limit 10 offset 5'));
  });

  test('compileSelect - combinações de cláusulas com order by desc', () {
    final qb = QueryBuilder(FakeConnection(), grammar, Processor());
    qb
        .select(['id', 'name'])
        .from('users')
        .where('age', '>', 25)
        .orderBy('name', 'desc')
        .limit(10)
        .offset(5);
    final sql = grammar.compileSelect(qb);
    expect(
        sql,
        contains(
            'select "id", "name" from "users" where "age" > ? order by "name" desc limit 10 offset 5'));
  });

  test('compileSelect - com QueryExpression', () {
    final qb = QueryBuilder(FakeConnection(), grammar, Processor());
    qb
        .select(
            [QueryExpression('CONCAT(first_name, " ", last_name)'), 'email'])
        .from(QueryExpression(
            '(select * from users where active = 1) as active_users'))
        .where('email', 'like', '%@example.com');
    final sql = grammar.compileSelect(qb);
    expect(
        sql,
        contains(
            'select CONCAT(first_name, " ", last_name), "email" from (select * from users where active = 1) as active_users where "email" like ?'));
  });

  test('compileComponents - com propriedades nulas', () {
    final qb = FakeQueryBuilder(columns: ['*'], from: 'users');
    final sql = grammar.compileComponents(qb);
    expect(sql.containsKey('wheres'), isFalse);
    expect(sql.containsKey('groups'), isFalse);
    expect(sql.containsKey('havings'), isFalse);
  });

  test('compileJoins - leftJoin, rightJoin, crossJoin', () {
    final qb = FakeQueryBuilder(columns: ['*'], from: 'users');
    qb.leftJoin('posts', 'users.id', '=', 'posts.user_id');
    qb.rightJoin('comments', 'posts.id', '=', 'comments.post_id');
    qb.crossJoin('categories');
    final sql = grammar.compileSelect(qb);
    expect(
        sql, contains('left join "posts" on "users"."id" = "posts"."user_id"'));
    expect(
        sql,
        contains(
            'right join "comments" on "posts"."id" = "comments"."post_id"'));
    expect(sql, contains('cross join "categories"'));
  });

  test('compileJoins - joins aninhados', () {
    final qb = FakeQueryBuilder(columns: ['*'], from: 'users');
    qb.join('posts', (JoinClause join) {
      join.on('users.id', '=', 'posts.user_id');
      join.on('posts.published', '=', QueryExpression('true'));
      join.orOn('posts.draft', '=', QueryExpression('false'));
    });
    final sql = grammar.compileSelect(qb);

    expect(
        sql,
        contains(
            'select * from "users" inner join "posts" on "users"."id" = "posts"."user_id" and "posts"."published" = true or "posts"."draft" = false'));
  });

  test('compileJoins - joins aninhados com where', () {
    final qb = FakeQueryBuilder(columns: ['*'], from: 'users');
    qb.join('posts', (JoinClause join) {
      join.on('users.id', '=', 'posts.user_id');
      join.where('posts.published', '=', true);
      join.orWhere('posts.draft', '=', false);
    });
    final sql = grammar.compileSelect(qb);

    expect(
        sql,
        contains(
            'select * from "users" inner join "posts" on "users"."id" = "posts"."user_id" and "posts"."published" = ? or "posts"."draft" = ?'));
  });

  test('compileJoinConstraint - diferentes operadores', () {
    final clause1 = {
      'first': 'age',
      'operator': '>',
      'second': 25,
      'boolean': 'and',
      'where': true
    };
    final clause2 = {
      'first': 'name',
      'operator': 'like',
      'second': '%John%',
      'boolean': 'or',
      'where': true
    };
    expect(grammar.compileJoinConstraint(clause1 as Map<String, dynamic>),
        'and "age" > ?'); // Expect 'and' no início
    expect(grammar.compileJoinConstraint(clause2 as Map<String, dynamic>),
        'or "name" like ?'); // Expect 'or' no início
  });

  test('whereSub', () {
    final qb = QueryBuilder(FakeConnection(), grammar, Processor());

    qb.from('posts').whereSub('author_id', 'in', (QueryBuilder subQuery) {
      subQuery.select('id').from('users').where('age', '>', 25);
    }, 'and');
    final sql = grammar.compileSelect(qb);
    expect(
        sql,
        contains(
            'where "author_id" in (select "id" from "users" where "age" > ?)'));
  });

  test('compileHavings - múltiplas cláusulas', () {
    final qb = FakeQueryBuilder(columns: ['id', 'count'], from: 'items');
    qb.groupBy('id');

    qb.having('count', '>', 10);
    qb.orHaving('count', '<', 5);

    final sql = grammar.compileSelect(qb);
    expect(sql, contains('having "count" > ? or "count" < ?'));
  });

  test('compileUnion - union all', () {
    final qb2 = FakeQueryBuilder(columns: ['id'], from: 'admins');
    final qb = FakeQueryBuilder(columns: ['id'], from: 'users');
    qb.unionsProp = [
      {'all': true, 'query': qb2}
    ];
    final sql = grammar.compileSelect(qb);
    expect(
        sql,
        contains(
            'select "id" from "users" union all select "id" from "admins"'));
  });

  test('compileSelect - whereRaw com bindings', () {
    final qb = QueryBuilder(FakeConnection(), grammar, Processor());
    qb
        .select(['*'])
        .from('products')
        .whereRaw('price > ? and in_stock = ?', [10.50, true]);
    final sql = grammar.compileSelect(qb);
    expect(sql, contains('where price > ? and in_stock = ?'));
  });

  test('compileOrders - múltiplas colunas', () {
    final qb = FakeQueryBuilder(from: 'users');
    qb.orderBy('name', 'asc');
    qb.orderBy('email', 'desc');

    final sql = grammar.compileSelect(qb);

    expect(sql, contains('order by "name" asc, "email" desc'));
  });

  test('compileUnion - com orderBy, limit e offset', () {
    final qb2 = FakeQueryBuilder(columns: ['id'], from: 'admins');
    final qb = FakeQueryBuilder(columns: ['id'], from: 'users');
    qb.union(qb2);
    qb.orderBy('id', 'desc').limit(5).offset(10);
    final sql = grammar.compileSelect(qb);
    expect(
        sql,
        contains(
            'select "id" from "users" union select "id" from "admins" order by "id" desc limit 5 offset 10'));
  });

  test('compileInsert - valores nulos', () {
    final qb =
        QueryBuilder(FakeConnection(), QueryPostgresGrammar(), Processor())
            .from('users');
    final sql = grammar.compileInsert(qb, {'name': 'John', 'email': null});
    expect(
        sql, contains('insert into "users" ("name", "email") values (?, ?)'));
  });

  test('compileSelect - whereIn com lista vazia', () {
    final qb = QueryBuilder(FakeConnection(), grammar, Processor());
    qb.select(['id']).from('users').whereIn('id', []);
    final sql = grammar.compileSelect(qb);
    expect(sql, contains('select "id" from "users" where "id" in ()'));
  });

  test('compileSelect - lock for update', () {
    final qb =
        QueryBuilder(FakeConnection(), QueryPostgresGrammar(), Processor());
    qb.from('users');
    qb.lockForUpdate();
    final sql = grammar.compileSelect(qb);
    expect(sql,
        contains('for update')); // Adapte para a sintaxe do seu banco de dados
  });
}
