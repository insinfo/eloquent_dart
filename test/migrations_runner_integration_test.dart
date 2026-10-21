// Live tests for the migration runner (runPending, markAsRan, the log in the
// migration's transaction, the advisory lock between concurrent migrators,
// Migration.statement) and the schema fixes it relies on (time precision,
// PostgreSQL column comments, compile errors). Requires localhost:5432 and
// localhost:3306, database `banco_teste`, user/password `dart`/`dart`.
@Tags(['integration'])
library;

import 'dart:async';

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

Map<String, dynamic> _config(String driver, bool pool) => driver == 'mysql'
    ? {
        'driver': 'mysql',
        'host': 'localhost',
        'port': '3306',
        'database': 'banco_teste',
        'username': 'dart',
        'password': 'dart',
        'pool': pool,
        'poolsize': 3,
      }
    : {
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
      };

const _log = 'mig_runner_log';

class _CreateItems extends Migration {
  @override
  Future<void> up() async {
    await (await schema).create('mig_items', (Blueprint t) {
      t.increments('id');
      t.string('nome');
      t.comment("Nome do item (com 'aspas')");
      t.timestamp('criado');
      t.nullable();
    });
  }

  @override
  Future<void> down() async => (await schema).dropIfExists('mig_items');
}

class _AddCodigo extends Migration {
  @override
  Future<void> up() async {
    await (await schema).table('mig_items', (Blueprint t) {
      t.integer('codigo');
      t.nullable();
      t.comment('Código externo');
    });
    await statement('create index mig_items_codigo_idx on mig_items (codigo)');
  }

  @override
  Future<void> down() async {
    await statement('drop index mig_items_codigo_idx');
  }
}

/// Creates a table with raw SQL and then fails.
class _Failing extends Migration {
  @override
  Future<void> up() async {
    await statement('create table mig_failing (id int)');
    throw StateError('falha proposital');
  }

  @override
  Future<void> down() async {}
}

/// Counts its runs in mig_counter, slowly, for the concurrency test.
class _Counted extends Migration {
  _Counted(this.name);
  final String name;

  @override
  Future<void> up() async {
    await statement('insert into mig_counter (migration) values (?)', [name]);
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  @override
  Future<void> down() async {}
}

class _ConcurrentIndex extends Migration {
  _ConcurrentIndex() {
    withinTransaction = false;
  }

  @override
  Future<void> up() async {
    await statement('create index concurrently if not exists '
        'mig_items_nome_idx on mig_items (nome)');
  }

  @override
  Future<void> down() async {}
}

/// A blueprint with a command no grammar compiles.
class _BogusBlueprint extends Blueprint {
  _BogusBlueprint(super.table) {
    addCommand('bogus');
  }
}

void main() {
  const drivers = <(String, bool)>[
    ('postgres', false),
    ('postgres', true),
    ('dpgsql', false),
    ('mysql', false),
  ];

  for (final (driver, pool) in drivers) {
    final isPg = driver != 'mysql';
    group('$driver${pool ? ' (pool)' : ''}', () {
      late Manager manager;
      late Connection db;
      late DatabaseManager dbm;
      final name = 'mig_${driver}_${pool ? 'pool' : 'single'}';

      Migrator migrator(Map<String, Migration Function()> registry,
          [DatabaseManager? on]) {
        final m = on ?? dbm;
        return Migrator(DatabaseMigrationRepository(m, _log), m, registry,
            databaseManager: m);
      }

      Future<void> dropAll(Connection c) async {
        for (final table in [_log, 'mig_items', 'mig_failing', 'mig_counter']) {
          await c.execute('drop table if exists $table');
        }
      }

      setUp(() async {
        manager = Manager()..addConnection(_config(driver, pool), name);
        manager.getDatabaseManager().setDefaultConnection(name);
        db = await manager.connection(name);
        dbm = manager.getDatabaseManager();
        await dropAll(db);
      });

      tearDown(() async {
        SchemaBuilder.defaultTimePrecision = null;
        await dropAll(db);
        await dbm.purge(name);
      });

      Future<int?> precision(String table, String column) async {
        final row = await db
            .table('information_schema.columns')
            .select(['datetime_precision'])
            .where('table_name', '=', table)
            .where('column_name', '=', column)
            .first();
        final value = row?['datetime_precision'] ?? row?['DATETIME_PRECISION'];
        return value == null ? null : int.parse('$value');
      }

      test('time precision: none by default, per column, or a global default',
          () async {
        final schema = db.getSchemaBuilder();
        await schema.create('mig_items', (Blueprint t) {
          t.timestamp('padrao');
          t.timestamp('milis', precision: 3);
          t.dateTime('data_hora');
          t.time('hora');
        });
        expect(await precision('mig_items', 'padrao'), isPg ? 6 : 0);
        expect(await precision('mig_items', 'milis'), 3);
        expect(await precision('mig_items', 'data_hora'), isPg ? 6 : 0);
        expect(await precision('mig_items', 'hora'), isPg ? 6 : 0);

        // Laravel's default.
        SchemaBuilder.defaultTimePrecision = 0;
        await schema.table('mig_items', (Blueprint t) {
          t.timestamp('laravel');
          t.timestamp('micros', precision: 6);
        });
        expect(await precision('mig_items', 'laravel'), 0);
        expect(await precision('mig_items', 'micros'), 6);
      });

      test('an unknown Blueprint command throws instead of being skipped',
          () async {
        final blueprint = _BogusBlueprint('mig_items');
        expect(() => blueprint.toSql(db, db.getSchemaBuilder().grammar),
            throwsA(isA<UnsupportedError>()));
      });

      test('runPending creates the log, runs in order and only once', () async {
        final m = migrator({
          '2026_10_21_000002_add_codigo': () => _AddCodigo(),
          '2026_10_21_000001_create_items': () => _CreateItems(),
        });
        expect(await m.pending(), [
          '2026_10_21_000001_create_items',
          '2026_10_21_000002_add_codigo',
        ]);
        expect(await m.runPending(), hasLength(2));
        expect(await m.pending(), isEmpty);
        expect(await m.runPending(), isEmpty);

        final log = await db.table(_log).orderBy('id').get();
        expect(log.map((r) => r['migration']), [
          '2026_10_21_000001_create_items',
          '2026_10_21_000002_add_codigo',
        ]);
        expect(log.map((r) => r['batch']), [1, 1]);

        await db.table('mig_items').insert({'nome': 'a', 'codigo': 1});
        expect(await db.table('mig_items').count(), 1);
      });

      test('a failing migration rolls back its DDL and is not logged',
          () async {
        if (!isPg) return; // MySQL commits DDL implicitly.
        final m = migrator({
          '2026_10_21_000001_create_items': () => _CreateItems(),
          '2026_10_21_000002_failing': () => _Failing(),
        });
        await expectLater(m.runPending(), throwsA(isA<StateError>()));
        expect(await db.getSchemaBuilder().hasTable('mig_failing'), isFalse);
        expect(await db.getSchemaBuilder().hasTable('mig_items'), isTrue);
        expect(await m.pending(), ['2026_10_21_000002_failing']);
      });

      test('markAsRan records a baseline without running it', () async {
        final m = migrator({
          '2026_10_21_000001_create_items': () => _CreateItems(),
          '2026_10_21_000002_add_codigo': () => _AddCodigo(),
        });
        await m.markAsRan(['2026_10_21_000001_create_items']);
        expect(await db.getSchemaBuilder().hasTable('mig_items'), isFalse);
        expect(await m.pending(), ['2026_10_21_000002_add_codigo']);
        expect(() => m.markAsRan(['nao_registrada']), throwsArgumentError);
      });

      test('rollback runs down and removes the log', () async {
        final m = migrator({
          '2026_10_21_000001_create_items': () => _CreateItems(),
        });
        await m.runPending();
        expect(await m.rollback(), 1);
        expect(await db.getSchemaBuilder().hasTable('mig_items'), isFalse);
        expect(await m.pending(), ['2026_10_21_000001_create_items']);
      });

      if (isPg) {
        test('column comments become COMMENT ON COLUMN', () async {
          await migrator({
            '2026_10_21_000001_create_items': () => _CreateItems(),
            '2026_10_21_000002_add_codigo': () => _AddCodigo(),
          }).runPending();
          Future<String?> comment(String column) async {
            final row = await db.selectOne(
                'select col_description(a.attrelid, a.attnum) as c '
                'from pg_attribute a where a.attrelid = ?::regclass '
                'and a.attname = ?',
                ['mig_items', column]);
            return row?['c'] as String?;
          }

          expect(await comment('nome'), "Nome do item (com 'aspas')");
          expect(await comment('codigo'), 'Código externo');
          expect(await comment('criado'), isNull);
        });

        test('a non-transactional migration (CREATE INDEX CONCURRENTLY)',
            () async {
          await migrator({
            '2026_10_21_000001_create_items': () => _CreateItems(),
            '2026_10_21_000002_concurrent_index': () => _ConcurrentIndex(),
          }).runPending();
          final index = await db.selectOne(
              "select 1 as ok from pg_indexes where indexname = 'mig_items_nome_idx'");
          expect(index, isNotNull);
        });

        test('concurrent migrators apply each migration once', () async {
          await db.execute(
              'create table mig_counter (migration varchar(100) not null)');
          final registry = <String, Migration Function()>{
            for (var i = 1; i <= 3; i++)
              '2026_10_21_00000${i}_counted': () => _Counted('m$i'),
          };
          // The log table first, so both migrators find it.
          await migrator(registry).markAsRan([]);

          final other = Manager()
            ..addConnection(_config(driver, pool), '${name}_other');
          other.getDatabaseManager().setDefaultConnection('${name}_other');
          try {
            await Future.wait([
              migrator(registry).runPending(),
              migrator(registry, other.getDatabaseManager()).runPending(),
            ]);
          } finally {
            await other.getDatabaseManager().purge('${name}_other');
          }

          final counts = await db
              .table('mig_counter')
              .select(['migration'])
              .selectRaw('count(*) as n')
              .groupBy('migration')
              .orderBy('migration')
              .get();
          expect(counts, [
            {'migration': 'm1', 'n': 1},
            {'migration': 'm2', 'n': 1},
            {'migration': 'm3', 'n': 1},
          ]);
          expect(await db.table(_log).count(), 3);
        });
      }
    });
  }
}
