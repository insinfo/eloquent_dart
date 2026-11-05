// The operators on real servers: the catalog of PostgreSQL against the list, an
// operator created with CREATE OPERATOR, the ones with `?` on every adapter, and
// the SQL that JSON selectors used to carry.
//
// Connections: PostgreSQL localhost:5432 and MariaDB/MySQL localhost:3306,
// db=banco_teste, user/pass=dart.

@Tags(['integration'])
library;

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

const _drivers = ['postgres', 'postgres_v3', 'dargres', 'dpgsql'];

Future<Connection> _pg(Manager manager,
    {String driver = 'postgres_v3', Object? customOperators}) {
  manager.addConnection({
    'driver': 'pgsql',
    'driver_implementation': driver,
    'host': 'localhost',
    'port': '5432',
    'database': 'banco_teste',
    'username': 'dart',
    'password': 'dart',
    if (customOperators != null) 'custom_operators': customOperators,
  }, 'pg');
  return manager.connection('pg');
}

void main() {
  late Manager manager;

  setUp(() => manager = Manager());
  tearDown(() async {
    for (final name in ['pg', 'my']) {
      try {
        await manager.getDatabaseManager().purge(name);
      } catch (_) {}
    }
  });

  group('the catalog of the server', () {
    Future<List<String>> operators(Connection db, String condition) async {
      final rows =
          await db.select('select distinct oprname from pg_operator where '
              "oprnamespace = 'pg_catalog'::regnamespace $condition");
      return [for (final row in rows) row['oprname'] as String];
    }

    test('where accepts every operator of pg_operator', () async {
      final db = await _pg(manager);
      final refused = <String>[];
      for (final operator in await operators(db, '')) {
        try {
          db.table('t').where('a', operator, 1).toSql();
        } on ArgumentError {
          refused.add(operator);
        }
      }
      // `?` is the bind placeholder, and these have one function per type.
      expect(refused..sort(), ['?#', '?-', '?-|', '?||']);
    });

    test('whereSqlOperator accepts every boolean one', () async {
      final db = await _pg(manager);
      final refused = <String>[];
      final condition = "and oprresult = 'bool'::regtype and oprleft <> 0";
      for (final operator in await operators(db, condition)) {
        try {
          QueryBuilder2(db, 't').whereSqlOperator('a', operator, 1).toSql();
        } on ArgumentError {
          refused.add(operator);
        }
      }
      expect(refused..sort(), ['?#', '?-', '?-|', '?||']);
    });
  });

  group('an operator of your own', () {
    Future<void> create(Connection db, String schema) async {
      await db
          .execute('create function pg_temp.op_eq(int, int) returns boolean '
              "language sql as 'select \$1 = \$2'");
      await db.execute('create operator $schema.=~=~ '
          '(leftarg = int, rightarg = int, function = pg_temp.op_eq)');
    }

    for (final driver in _drivers) {
      test('$driver: from the config, as it runs on the server', () async {
        final db = await _pg(manager,
            driver: driver, customOperators: ['OPERATOR(pg_temp.=~=~)']);
        await create(db, 'pg_temp');
        await db.execute('create temporary table op_own (id int)');
        await db.execute('insert into op_own values (1), (2)');

        final rows = await db
            .table('op_own')
            .where('id', 'OPERATOR(pg_temp.=~=~)', 2)
            .get();
        expect(rows.map((r) => r['id']), [2]);

        final viaColumn = await db
            .table('op_own')
            .whereColumn('id', 'operator(pg_temp.=~=~)', 'id')
            .get();
        expect(viaColumn, hasLength(2));
      });
    }

    test('refused until it is added at run time', () async {
      final db = await _pg(manager);
      expect(() => db.table('t').where('a', '=~=~', 1), throwsArgumentError);
      db.addCustomOperators(['=~=~']);
      expect(db.table('t').where('a', '=~=~', 1).toSql(),
          'select * from "t" where "a" =~=~ ?');
    });

    test('a config with something that is not an operator fails', () async {
      await expectLater(
          _pg(manager, customOperators: ['= 1 or 1=1']), throwsArgumentError);
    });

    test('a config that is not a list fails', () async {
      await expectLater(
          _pg(manager, customOperators: '===~'), throwsArgumentError);
    });
  });

  group('the operators with ?', () {
    for (final driver in _drivers) {
      test('$driver: they run', () async {
        final db = await _pg(manager, driver: driver);
        await db.execute('create temporary table op_json (id int, data jsonb)');
        await db.execute('insert into op_json values '
            '(1, \'{"a":1,"b":2}\'), (2, \'{"a":1}\'), (3, \'{"c":1}\')');

        Future<List<Object?>> ids(String operator, Object value) async {
          final rows = await db
              .table('op_json')
              .where('data', operator, value)
              .orderBy('id')
              .get();
          return [for (final row in rows) row['id']];
        }

        expect(await ids('?', 'b'), [1]);
        expect(await ids('?|', ['b', 'c']), [1, 3]);
        expect(await ids('?&', ['a', 'b']), [1]);
        expect(await ids('@?', r'$.c'), [3]);
      });
    }
  });

  group('SQL in a JSON selector does nothing', () {
    test('PostgreSQL', () async {
      final db = await _pg(manager);
      await db.execute('create temporary table op_sel (id int, data jsonb)');
      await db.execute(
          'insert into op_sel values (1, \'{"a":"x"}\'), (2, \'{"a":"y"}\')');
      const evil = "data->x' is null or 1=1 or 'a";
      expect(await db.table('op_sel').where(evil, 'zzz').get(), isEmpty);
      // A key with a quote is only a key.
      await db.execute("insert into op_sel values (3, '{\"it''s\":\"z\"}')");
      final rows = await db.table('op_sel').where("data->it's", 'z').get();
      expect(rows.map((r) => r['id']), [3]);
    });

    test('an operator from outside does nothing on a real server', () async {
      final db = await _pg(manager);
      await db.execute('create temporary table op_real (id int)');
      await db.execute('insert into op_real values (1), (2), (3)');
      expect(() => db.table('op_real').where('id', '= 0 or 1=1 or 1 =', 1),
          throwsArgumentError);
      expect(await db.table('op_real').where('id', '=', 1).get(), hasLength(1));
    });

    group('MariaDB', () {
      late Connection db;

      setUp(() async {
        manager.addConnection({
          'driver': 'mysql',
          'host': 'localhost',
          'port': '3306',
          'database': 'banco_teste',
          'username': 'dart',
          'password': 'dart',
        }, 'my');
        db = await manager.connection('my');
        await db.execute('drop temporary table if exists op_my');
        await db.execute('create temporary table op_my (id int, data json)');
        await db.execute(
            'insert into op_my values (1, \'{"a":"x"}\'), (2, \'{"a":"y"}\')');
      });

      /// The rows of [query], or none if the server refuses its JSON path: what
      /// matters is that it does not return them all.
      Future<int> rows(QueryBuilder query) async {
        try {
          return (await query.get()).length;
        } on Exception {
          return 0;
        }
      }

      test('whereJsonContains with a backslash', () async {
        const evil = r"data->a\') or 1=1 #";
        expect(await rows(db.table('op_my').whereJsonContains(evil, 'zzz')), 0);
        expect(
            await rows(db.table('op_my').whereJsonContains('data->a', 'x')), 1);
      });

      test('where with a quote', () async {
        const evil = 'data->x" is null or 1=1 or "a';
        expect(await rows(db.table('op_my').where(evil, 'zzz')), 0);
      });

      test('# is refused', () {
        expect(
            () => db.table('op_my').where('id', '#', 1), throwsArgumentError);
      });
    });
  });
}
