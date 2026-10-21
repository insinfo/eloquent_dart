// Live tests: db.unprepared()/db.execute() run a whole SQL script (several
// statements, comments with ?, dollar-quoted bodies, BEGIN/COMMIT) the same
// way on the four PostgreSQL adapters, as PDO::exec / Laravel's
// DB::unprepared. Requires localhost:5432, database `banco_teste`,
// user/password `dart`/`dart`.
@Tags(['integration'])
library;

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

const _table = 'eloquent_script_test';

const _script = '''
-- Por quê? Um comentário com ? e 'aspas'
create table $_table (id int primary key, nome text);
insert into $_table values (1, 'a?b'), (2, 'c');
create or replace function eloquent_script_fn() returns int
language plpgsql as \$\$
begin
  return 1; -- ; dentro do corpo
end;
\$\$;
begin;
insert into $_table values (3, 'tx');
commit;
''';

void main() {
  const drivers = <(String, bool)>[
    ('postgres', false),
    ('postgres', true),
    ('postgres_v3', false),
    ('dargres', false),
    ('dargres', true),
    ('dpgsql', false),
    ('dpgsql', true),
  ];

  for (final (driver, pool) in drivers) {
    group('$driver${pool ? ' (pool)' : ''}', () {
      late Manager manager;
      late Connection db;
      final name = 'script_${driver}_${pool ? 'pool' : 'single'}';

      setUp(() async {
        manager = Manager()
          ..addConnection({
            'driver': 'pgsql',
            'driver_implementation': driver,
            'host': 'localhost',
            'port': '5432',
            'database': 'banco_teste',
            'username': 'dart',
            'password': 'dart',
            'schema': ['public'],
            'pool': pool,
            'poolsize': 3,
          }, name);
        db = await manager.getConnection(name);
        await db.execute('drop table if exists $_table');
        await db.execute('drop function if exists eloquent_script_fn()');
      });

      tearDown(() async {
        await db.execute('drop table if exists $_table');
        await db.execute('drop function if exists eloquent_script_fn()');
        await manager.getDatabaseManager().purge(name);
      });

      Future<List<Map<String, dynamic>>> rows() =>
          db.table(_table).orderBy('id').get();

      test('unprepared runs the whole script', () async {
        await db.unprepared(_script);
        expect(await rows(), [
          {'id': 1, 'nome': 'a?b'},
          {'id': 2, 'nome': 'c'},
          {'id': 3, 'nome': 'tx'},
        ]);
        expect(
            await db.selectOne('select eloquent_script_fn() as v'), {'v': 1});
      });

      test('execute runs the whole script too', () async {
        await db.execute(_script);
        expect(await rows(), hasLength(3));
      });

      test('a script inside a transaction is rolled back with it', () async {
        await db.execute('create table $_table (id int primary key)');
        await expectLater(db.transaction((ctx) async {
          await ctx.unprepared('insert into $_table values (1); '
              'insert into $_table values (2)');
          throw StateError('rollback');
        }), throwsStateError);
        expect(await db.table(_table).count(), 0);

        await db.transaction((ctx) => ctx.unprepared(
            'insert into $_table values (1); insert into $_table values (2)'));
        expect(await db.table(_table).count(), 2);
      });

      test('an error in a later statement fails the script', () async {
        await expectLater(
            db.unprepared('create table $_table (id int); '
                'insert into eloquent_script_missing values (1)'),
            throwsA(anything));
        // One implicit transaction: the create was rolled back.
        expect(await db.getSchemaBuilder().hasTable(_table), isFalse);
      });

      test('parameterized queries still use the prepared path', () async {
        await db.unprepared(_script);
        final row = await db
            .table(_table)
            .where('id', '=', 2)
            .where('nome', '=', 'c')
            .first();
        expect(row, {'id': 2, 'nome': 'c'});
      });

      test('pretend returns 0 rows instead of failing', () async {
        final log = await db.pretend((Connection c) async {
          expect(await c.unprepared('select 1'), 0);
        });
        expect(log, hasLength(1));
      });
    });
  }
}
