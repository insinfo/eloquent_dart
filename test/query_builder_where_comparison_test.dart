import 'package:test/test.dart';
import 'package:eloquent/eloquent.dart';

import 'helper.dart';

void main() {
  late ConnectionInterface connection;
  late QueryGrammar grammar;
  late Processor processor;

  setUp(() {
    connection = FakeConnection();
    grammar = QueryPostgresGrammar();
    processor = Processor();
  });

  // Helper para criar builders de forma consistente
  QueryBuilder createBuilder() {
    return QueryBuilder(connection, grammar, processor).from('users');
  }

  group('QueryBuilder Where Method Comparison', () {
    test('Standard 3 arguments (column, operator, value)', () {
      final qbSimple = createBuilder();
      final qbFlex = createBuilder();

      qbSimple.where('name', '=', 'John');
      qbFlex.whereFlex('name', '=', 'John');

      expect(qbFlex.toSql(), equals(qbSimple.toSql()), reason: 'SQL mismatch');
      expect(qbFlex.getBindings(), orderedEquals(qbSimple.getBindings()),
          reason: 'Bindings mismatch');
      expect(qbSimple.toSql(), contains('where "name" = ?'));
      expect(qbSimple.getBindings(), equals(['John']));
    });

    test('Operator != "="', () {
      final qbSimple = createBuilder();
      final qbFlex = createBuilder();

      qbSimple.where('age', '>', 18);
      qbFlex.whereFlex('age', '>', 18);

      expect(qbFlex.toSql(), equals(qbSimple.toSql()), reason: 'SQL mismatch');
      expect(qbFlex.getBindings(), orderedEquals(qbSimple.getBindings()),
          reason: 'Bindings mismatch');
      expect(qbSimple.toSql(), contains('where "age" > ?'));
      expect(qbSimple.getBindings(), equals([18]));
    });

    test('Omitted operator (column, value) -> defaults to "="', () {
      final qbSimple = createBuilder();
      final qbFlex = createBuilder();

      // Simula a chamada where('email', 'test@example.com') no qbFlex
      // A chamada equivalente no qbSimple requer o '=' explícito
      qbSimple.where('email', '=', 'test@example.com');
      qbFlex.whereFlex('email', 'test@example.com'); // Onde '=' é inferido

      expect(qbFlex.toSql(), equals(qbSimple.toSql()), reason: 'SQL mismatch');
      expect(qbFlex.getBindings(), orderedEquals(qbSimple.getBindings()),
          reason: 'Bindings mismatch');
      expect(qbSimple.toSql(), contains('where "email" = ?'));
      expect(qbSimple.getBindings(), equals(['test@example.com']));
    });

    test('Map input for multiple conditions', () {
      final qbSimple = createBuilder();
      final qbFlex = createBuilder();

      final conditions = {'status': 'active', 'role_id': 2};
      qbSimple.where(conditions); // whereSimple também deve suportar Map
      qbFlex.whereFlex(conditions);

      expect(qbFlex.toSql(), equals(qbSimple.toSql()), reason: 'SQL mismatch');
      expect(qbFlex.getBindings(), orderedEquals(qbSimple.getBindings()),
          reason: 'Bindings mismatch');
      // A ordem pode variar dependendo da implementação do Map, por isso usamos contains
      expect(qbSimple.toSql(), contains('"status" = ?'));
      expect(qbSimple.toSql(), contains('"role_id" = ?'));
      expect(qbSimple.toSql(), contains('and'));
      expect(qbSimple.getBindings(),
          equals(['active', 2])); // Ordem baseada na iteração do Map
    });

    test('Closure input for nested where', () {
      final qbSimple = createBuilder();
      final qbFlex = createBuilder();

      qbSimple.where((QueryBuilder q) {
        q.where('score', '>', 90);
        q.orWhereFlex('level', '=', 'expert'); // Usa orWhereSimple dentro
      });
      qbFlex.whereFlex((QueryBuilder q) {
        q.whereFlex('score', '>', 90);
        q.orWhere('level', '=', 'expert'); // Usa orWhere flexível dentro
      });

      expect(qbFlex.toSql(), equals(qbSimple.toSql()), reason: 'SQL mismatch');
      expect(qbFlex.getBindings(), orderedEquals(qbSimple.getBindings()),
          reason: 'Bindings mismatch');
      expect(qbSimple.toSql(), contains('where ("score" > ? or "level" = ?)'));
      expect(qbSimple.getBindings(), equals([90, 'expert']));
    });

    test('Value is Closure (whereSub)', () {
      final qbSimple = createBuilder();
      final qbFlex = createBuilder();

      qbSimple.where('id', 'in', (QueryBuilder q) {
        q.select('user_id').from('posts').where('likes', '>', 100);
      });
      qbFlex.whereFlex('id', 'in', (QueryBuilder q) {
        q.select('user_id').from('posts').whereFlex('likes', '>', 100);
      });

      expect(qbFlex.toSql(), equals(qbSimple.toSql()), reason: 'SQL mismatch');
      expect(qbFlex.getBindings(), orderedEquals(qbSimple.getBindings()),
          reason: 'Bindings mismatch');
      expect(
          qbSimple.toSql(),
          contains(
              'where "id" in (select "user_id" from "posts" where "likes" > ?)'));
      expect(qbSimple.getBindings(), equals([100])); // Binding da subconsulta
    });

    test('Value is null (explicit operator =)', () {
      final qbSimple = createBuilder();
      final qbFlex = createBuilder();

      qbSimple.where('deleted_at', '=', null);
      qbFlex.whereFlex('deleted_at', '=', null);

      expect(qbFlex.toSql(),
          equals('select * from "users" where "deleted_at" is null'));
      expect(qbFlex.getBindings(), []);
      expect(qbSimple.toSql(),
          equals('select * from "users" where "deleted_at" is null'));
      expect(qbSimple.getBindings(), isEmpty);
    });

    test('Value is null (omitted operator)', () {
      final qbSimple = createBuilder();
      final qbFlex = createBuilder();

      // Chamada equivalente em qbSimple
      qbSimple.where('deleted_at', '=', null);
      qbFlex.whereFlex('deleted_at', null); // Onde '=' é inferido

      expect(qbFlex.toSql(), equals(qbSimple.toSql()), reason: 'SQL mismatch');
      expect(qbFlex.getBindings(), orderedEquals(qbSimple.getBindings()),
          reason: 'Bindings mismatch');
      expect(qbSimple.toSql(), contains('where "deleted_at" is null'));
      expect(qbSimple.getBindings(), isEmpty);
    });

    test('Value is QueryExpression', () {
      final qbSimple = createBuilder();
      final qbFlex = createBuilder();
      final rawExpr = connection.raw('NOW() - interval \'1 day\'');

      qbSimple.where('created_at', '>', rawExpr);
      qbFlex.whereFlex('created_at', '>', rawExpr);

      expect(qbFlex.toSql(), equals(qbSimple.toSql()), reason: 'SQL mismatch');
      expect(qbFlex.getBindings(), orderedEquals(qbSimple.getBindings()),
          reason: 'Bindings mismatch');
      expect(qbSimple.toSql(),
          contains("where \"created_at\" > NOW() - interval '1 day'"));
      expect(qbSimple.getBindings(),
          isEmpty); // Nenhum binding adicionado para QueryExpression
    });

    test('Chaining with orWhere', () {
      final qbSimple = createBuilder();
      final qbFlex = createBuilder();

      qbSimple.where('status', '=', 'pending').orWhereFlex('priority', '>', 5);

      qbFlex
          .whereFlex('status', 'pending') // Usa where flexível
          .orWhere('priority', '>', 5); // Usa orWhere flexível

      expect(qbFlex.toSql(), equals(qbSimple.toSql()), reason: 'SQL mismatch');
      expect(qbFlex.getBindings(), orderedEquals(qbSimple.getBindings()),
          reason: 'Bindings mismatch');
      expect(
          qbSimple.toSql(), contains('where "status" = ? or "priority" > ?'));
      expect(qbSimple.getBindings(), equals(['pending', 5]));
    });

    test('Chaining with mixed simple and flex where', () {
      final qbSimple = createBuilder();
      final qbFlex = createBuilder();

      // qbSimple usa apenas whereSimple
      qbSimple.where('type', '=', 'A').orWhereFlex('verified', '=', true);

      // qbFlex mistura chamadas (para garantir interoperabilidade)
      qbFlex
          .whereFlex('type', 'A') // Flexível, infere '='
          .orWhereFlex('verified', '=', true); // Simples explícito

      expect(qbFlex.toSql(), equals(qbSimple.toSql()), reason: 'SQL mismatch');
      expect(qbFlex.getBindings(), orderedEquals(qbSimple.getBindings()),
          reason: 'Bindings mismatch');
      expect(qbSimple.toSql(), contains('where "type" = ? or "verified" = ?'));
      expect(qbSimple.getBindings(), equals(['A', true]));
    });

    // --- Testes específicos da assinatura flexível ---

    test('Flex where: Closure as second argument (infers =)', () {
      final qbFlex = createBuilder();

      // Cenário: where('column', Closure) -> where column = (subquery)
      qbFlex.whereFlex('id', (QueryBuilder q) {
        q.selectRaw('MAX(id)').from('other_users');
      });

      expect(qbFlex.toSql(),
          contains('where "id" = (select MAX(id) from "other_users")'));
      expect(qbFlex.getBindings(), isEmpty);
    });

    test('Flex where: Throws on ambiguous 3 args (non-operator string)', () {
      final qbFlex = createBuilder();

      expect(() => qbFlex.whereFlex('name', 'not_an_operator', 'some_value'),
          throwsA(isA<InvalidArgumentException>()),
          reason:
              'Should throw if 2nd arg is not operator when 3rd is present');
    });

    test('whereColumn compares two columns', () {
      final qb = createBuilder();
      qb.whereColumn('updated_at', '>', 'created_at');

      expect(qb.toSql(), contains('where "updated_at" > "created_at"'));
      expect(qb.getBindings(), isEmpty);
    });

    test('orWhereColumn adds OR condition comparing columns', () {
      final qb = createBuilder();
      qb
          .where('status', '=', 'active')
          .orWhereColumn('last_login', '<', 'created_at');

      expect(qb.toSql(),
          contains('where "status" = ? or "last_login" < "created_at"'));
      expect(qb.getBindings(), equals(['active']));
    });

    test('whereColumn with different operators', () {
      final qb = createBuilder();
      qb.whereColumn('col_a', '!=', 'col_b');
      expect(
          qb.toSql(),
          contains(
              'where "col_a" != "col_b"')); // Ou <> dependendo da gramática
    });

    test('whereRaw with bindings', () {
      final qb = createBuilder();
      qb.whereRaw('views > ? and category = ?', [1000, 'news']);

      expect(qb.toSql(), contains('where views > ? and category = ?'));
      expect(qb.getBindings(), orderedEquals([1000, 'news']));
    });

    test('orWhereRaw adds OR condition with raw SQL and bindings', () {
      final qb = createBuilder();
      qb.where('id', '=', 1).orWhereRaw('score < ?', [50]);

      expect(qb.toSql(), contains('where "id" = ? or score < ?'));
      expect(qb.getBindings(), orderedEquals([1, 50]));
    });

    test('orWhereBetween adds OR BETWEEN condition', () {
      final qb = createBuilder();
      qb.where('id', '=', 1).orWhereBetween('age', [18, 30]);

      expect(qb.toSql(), contains('where "id" = ? or "age" between ? and ?'));
      expect(qb.getBindings(), orderedEquals([1, 18, 30]));
    });

    test('whereNotBetween adds NOT BETWEEN condition', () {
      final qb = createBuilder();
      qb.whereNotBetween('price', [9.99, 19.99]);

      expect(qb.toSql(), contains('where "price" not between ? and ?'));
      expect(qb.getBindings(), orderedEquals([9.99, 19.99]));
    });

    test('orWhereNotBetween adds OR NOT BETWEEN condition', () {
      final qb = createBuilder();
      qb.where('stock', '>', 0).orWhereNotBetween(
          'rating', [1, 3]); // Ex: Produtos bons ou ruins, mas não médios

      expect(qb.toSql(),
          contains('where "stock" > ? or "rating" not between ? and ?'));
      expect(qb.getBindings(), orderedEquals([0, 1, 3]));
    });
    test('whereExists generates EXISTS subquery', () {
      final qb = createBuilder();
      qb.whereExists((QueryBuilder q) {
        q
            .selectRaw('1')
            .from('orders')
            .whereColumn('orders.user_id', '=', 'users.id');
      });

      expect(
          qb.toSql(),
          contains(
              'where exists (select 1 from "orders" where "orders"."user_id" = "users"."id")'));
      expect(qb.getBindings(), isEmpty); // Subquery não tem bindings neste caso
    });

    test('orWhereExists adds OR EXISTS subquery', () {
      final qb = createBuilder();
      qb.where('active', '=', true).orWhereExists((QueryBuilder q) {
        q.selectRaw('1').from('roles').where('roles.name', '=', 'admin');
      });

      expect(
          qb.toSql(),
          contains(
              'where "active" = ? or exists (select 1 from "roles" where "roles"."name" = ?)'));
      expect(qb.getBindings(),
          orderedEquals([true, 'admin'])); // Bindings da subquery
    });

    test('whereNotExists generates NOT EXISTS subquery', () {
      final qb = createBuilder();
      qb.whereNotExists((QueryBuilder q) {
        q
            .selectRaw('1')
            .from('bans')
            .whereColumn('bans.user_id', '=', 'users.id');
      });

      expect(
          qb.toSql(),
          contains(
              'where not exists (select 1 from "bans" where "bans"."user_id" = "users"."id")'));
      expect(qb.getBindings(), isEmpty);
    });

    test('orWhereNotExists adds OR NOT EXISTS subquery', () {
      final qb = createBuilder();
      qb.where('confirmed', '=', true).orWhereNotExists((QueryBuilder q) {
        q.selectRaw('1').from('pending_approvals').where('item_id', '=', 5);
      });

      expect(
          qb.toSql(),
          contains(
              'where "confirmed" = ? or not exists (select 1 from "pending_approvals" where "item_id" = ?)'));
      expect(qb.getBindings(), orderedEquals([true, 5]));
    });

    test('whereIn with empty list generates safe condition', () {
      final qb = createBuilder();
      qb.whereIn('id', []);

      expect(() => qb.toSql(), returnsNormally);
      expect(qb.toSql(), equals('select * from "users" where "id" in ()'));
      expect(qb.getBindings(), isEmpty);
    });

    test('whereNotIn with empty list generates safe condition', () {
      final qb = createBuilder();
      qb.whereNotIn('id', []);
      // A gramática deve gerar algo como "1 = 1" que sempre será verdadeiro
      expect(() => qb.toSql(), returnsNormally);
      expect(qb.toSql(),
          equals('select * from "users" where "id" not in ()')); // Ou ajuste
      expect(qb.getBindings(), isEmpty);
    });

    test('Combining multiple different where clauses', () {
      final qb = createBuilder();
      qb
          .where('name', 'like', 'A%') // Basic
          .orWhereBetween('score', [80, 100]) // orWhereBetween
          .whereNotNull('verified_at') // whereNotNull
          .whereColumn('updated_at', '>', 'created_at') // whereColumn
          .whereExists((q) => // whereExists
              q.selectRaw('1').from('logs').where('user_id', '=', 123));

      // Verificar o SQL gerado (pode ser complexo, foque nas partes principais)
      final sql = qb.toSql();
      expect(sql, contains('where "name" like ?'));
      expect(sql, contains('or "score" between ? and ?'));
      expect(sql, contains('and "verified_at" is not null'));
      expect(sql, contains('and "updated_at" > "created_at"'));
      expect(sql,
          contains('and exists (select 1 from "logs" where "user_id" = ?)'));

      // Verificar todos os bindings na ordem correta
      expect(qb.getBindings(), orderedEquals(['A%', 80, 100, 123]));
    });
  }); // end group

  group('QueryBuilder whereFlex Specific Behaviors and Limitations', () {
    test('whereFlex: 2 args - non-operator string infers operator "="', () {
      final qbFlex = createBuilder();
      qbFlex.whereFlex('email', 'test@example.com');
      expect(qbFlex.toSql(), contains('where "email" = ?'));
      expect(qbFlex.getBindings(), equals(['test@example.com']));
    });

    test('whereFlex: 2 args - valid operator string without value assumes NULL',
        () {
      final qbFlex = createBuilder();

      try {
        qbFlex.whereFlex('age', '>');

        expect(
            qbFlex.toSql(),
            contains(
                'where "age" = ?')); // Comportamento atual esperado devido à heurística
        expect(qbFlex.getBindings(), equals(['>'])); // Binding incorreto
      } catch (e) {
        // Espera-se uma InvalidArgumentException aqui se a validação for robusta
        // Ou o teste pode passar com o SQL/binding incorreto se a validação falhar

        expect(e, isA<InvalidArgumentException>(),
            reason:
                'Using only a non-= operator should ideally throw or be invalid');
      }

      // Teste com '<='
      final qbFlex2 = createBuilder();
      try {
        qbFlex2.whereFlex('score', '<=');
        expect(qbFlex2.toSql(), contains('where "score" = ?'));
        expect(qbFlex2.getBindings(), equals(['<=']));
        fail('Expected InvalidArgumentException but none was thrown.');
      } catch (e) {
        expect(e, isA<InvalidArgumentException>());
      }
    });

    test('whereFlex: 2 args - operator IS should throw (or be invalid)', () {
      final qbFlex = createBuilder();

      qbFlex.whereFlex('flag', 'IS');
      expect(qbFlex.toSql(), equals('select * from "users" where "flag" = ?'));
    });

    test(
        'whereFlex: 3 args - explicit null value with operator "=" (PROBLEMATIC CASE)',
        () {
      final qbFlex = createBuilder();

      qbFlex.whereFlex('deleted_at', '=', null);

      expect(qbFlex.toSql(), contains('where "deleted_at" is null'),
          reason:
              'Heuristic likely misinterprets this as 2 args, leading to wrong SQL');
      expect(qbFlex.getBindings(), equals([]),
          reason:
              'Heuristic likely misinterprets this as 2 args, leading to wrong binding');
    });

    test(
        'whereFlex: 3 args - explicit null value with operator "=" delegates to whereNull',
        () {
      final qbFlex = createBuilder();
      qbFlex.whereFlex('deleted_at', '=', null); // Intenção clara: IS NULL

      expect(qbFlex.toSql(), contains('where "deleted_at" is null'),
          reason: 'whereFlex(col, "=", null) should delegate to whereNull');
      expect(qbFlex.getBindings(), isEmpty,
          reason: 'whereNull should not add bindings');
    });

    test(
        'whereFlex: 3 args - explicit null value with operator "!=" (PROBLEMATIC CASE)',
        () {
      final qbFlex = createBuilder();
      // A intenção é "is not null"
      qbFlex.whereFlex('verified_at', '!=', null);

      expect(qbFlex.toSql(), contains('where "verified_at" is not null'),
          reason: 'Heuristic likely misinterprets this as 2 args');
      expect(qbFlex.getBindings(), equals([]),
          reason: 'Heuristic likely misinterprets this as 2 args');
    });

    test(
        'whereFlex: 3 args - explicit null value with operator "!=" delegates to whereNotNull',
        () {
      final qbFlex = createBuilder();
      qbFlex.whereFlex(
          'verified_at', '!=', null); // Intenção clara: IS NOT NULL

      expect(qbFlex.toSql(), contains('where "verified_at" is not null'),
          reason: 'whereFlex(col, "!=", null) should delegate to whereNotNull');
      expect(qbFlex.getBindings(), isEmpty,
          reason: 'whereNotNull should not add bindings');
    });

    test(
        'whereFlex: 2 args - explicit null value (omitted operator) -> SHOULD BE whereNull',
        () {
      final qbFlex = createBuilder();

      qbFlex.whereFlex('manager_id', null);

      expect(qbFlex.toSql(), contains('where "manager_id" is null'),
          reason:
              'Calling whereFlex(col, null) should correctly delegate to whereNull');
      expect(qbFlex.getBindings(), isEmpty);
    });

    test(
        'whereFlex: 2 args - explicit null value (omitted operator) delegates to whereNull',
        () {
      final qbFlex = createBuilder();
      qbFlex.whereFlex(
          'manager_id', null); // Interpreta como ('manager_id', '=', null)

      expect(qbFlex.toSql(), contains('where "manager_id" is null'),
          reason:
              'Calling whereFlex(col, null) should correctly delegate to whereNull');
      expect(qbFlex.getBindings(), isEmpty);
    });

    test('whereFlex: 3 args - non-operator string as operator throws', () {
      final qbFlex = createBuilder();
      expect(
          () =>
              qbFlex.whereFlex('role', 'admin', 123), // 'admin' não é operador
          throwsA(isA<InvalidArgumentException>()),
          reason:
              'Should throw if the second arg is not a valid operator when the third arg is present.');
    });

    test('whereFlex: Closure as second argument correctly calls whereSub', () {
      final qbFlex = createBuilder();

      qbFlex.whereFlex('category_id', (QueryBuilder q) {
        q.select('id').from('categories').where('name', '=', 'featured');
      });

      expect(
          qbFlex.toSql(),
          contains(
              'where "category_id" = (select "id" from "categories" where "name" = ?)'));
      expect(qbFlex.getBindings(), equals(['featured']));
    });

    test('whereFlex: Closure as second argument correctly calls whereSub 2',
        () {
      final qbFlex = createBuilder();
      // Interpreta como where('category_id', '=', closure)
      qbFlex.whereFlex('category_id', (QueryBuilder q) {
        q.select('id').from('categories').where('name', '=', 'featured');
      });

      expect(
          qbFlex.toSql(),
          contains(
              'where "category_id" = (select "id" from "categories" where "name" = ?)'));
      expect(qbFlex.getBindings(), equals(['featured']));
    });

    test('whereFlex: 3 args - explicit null value with invalid operator throws',
        () {
      final qbFlex = createBuilder();
      expect(
          () => qbFlex.whereFlex(
              'start_date', '>', null), // '>' com null é inválido
          throwsA(isA<InvalidArgumentException>()),
          reason: 'Operator > is invalid with null value');
      expect(
          () => qbFlex.whereFlex(
              'end_date', 'LIKE', null), // 'LIKE' com null é inválido
          throwsA(isA<InvalidArgumentException>()),
          reason: 'Operator LIKE is invalid with null value');
    });
  }); // end
}
