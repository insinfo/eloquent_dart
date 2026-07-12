// migrations_seeders_integration_test.dart
//
// Integration tests (require a live PostgreSQL) for the end-to-end migrations
// engine and the seeders subsystem added in the `performace` branch.
//
// Connection: localhost:5432 db=postgres user/pass=dart (dpgsql driver).

@Tags(['integration'])
library;

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

const _config = {
  'driver': 'pgsql',
  'driver_implementation': 'dpgsql',
  'host': '127.0.0.1',
  'port': '5432',
  'database': 'postgres',
  'username': 'dart',
  'password': 'dart',
  'charset': 'utf8',
  'prefix': '',
  'schema': ['public'],
};

// --- Example migrations (registered explicitly, no code generation) ---

class CreateWidgetsTable extends Migration {
  @override
  Future<void> up() async {
    final s = await schema;
    await s.create('perf_widgets', (Blueprint t) {
      t.increments('id');
      t.string('name');
      t.integer('qty');
    });
  }

  @override
  Future<void> down() async {
    final s = await schema;
    await s.dropIfExists('perf_widgets');
  }
}

class AddWidgetsActiveColumn extends Migration {
  @override
  Future<void> up() async {
    final s = await schema;
    await s.table('perf_widgets', (Blueprint t) {
      t.boolean('active');
    });
  }

  @override
  Future<void> down() async {
    // no-op: column dropped with the table in the first migration's down
  }
}

// --- Example seeder ---

class WidgetsSeeder extends Seeder {
  @override
  Future<void> run() async {
    final conn = await db!.connection(connectionName);
    await conn.table('perf_widgets').insert(
        {'name': 'alpha', 'qty': 1, 'active': true});
    await conn.table('perf_widgets').insert(
        {'name': 'beta', 'qty': 2, 'active': false});
  }
}

const _mig1 = '2026_07_12_000001_create_widgets_table';
const _mig2 = '2026_07_12_000002_add_widgets_active_column';

void main() {
  late Manager manager;
  late DatabaseManager dbm;
  late Connection db;
  late DatabaseMigrationRepository repo;
  late Migrator migrator;

  final registry = <String, Migration Function()>{
    _mig1: () => CreateWidgetsTable(),
    _mig2: () => AddWidgetsActiveColumn(),
  };

  setUp(() async {
    manager = Manager();
    manager.addConnection(Map<String, dynamic>.from(_config));
    manager.setAsGlobal();
    db = await manager.connection();
    dbm = manager.getDatabaseManager();

    // Clean slate.
    await db.execute('DROP TABLE IF EXISTS perf_widgets');
    await db.execute('DROP TABLE IF EXISTS perf_migrations');

    repo = DatabaseMigrationRepository(dbm, 'perf_migrations');
    if (!await repo.repositoryExists()) {
      await repo.createRepository();
    }
    migrator = Migrator(repo, dbm, registry, databaseManager: dbm);
  });

  tearDown(() async {
    await db.execute('DROP TABLE IF EXISTS perf_widgets');
    await db.execute('DROP TABLE IF EXISTS perf_migrations');
    await manager.getDatabaseManager().purge('default');
  });

  test('runs migrations up: creates table and records batch', () async {
    await migrator.runMigrationList([_mig1, _mig2]);

    final schema = await dbm.schema();
    expect(await schema.hasTable('perf_widgets'), isTrue);
    expect(await schema.hasColumn('perf_widgets', 'active'), isTrue);

    final ran = await repo.getRan();
    expect(ran, containsAll([_mig1, _mig2]));
  });

  test('rollback undoes the last batch', () async {
    await migrator.runMigrationList([_mig1, _mig2]);
    final schema = await dbm.schema();
    expect(await schema.hasTable('perf_widgets'), isTrue);

    final rolled = await migrator.rollback();
    expect(rolled, equals(2));
    expect(await schema.hasTable('perf_widgets'), isFalse);
    expect(await repo.getRan(), isEmpty);
  });

  test('seeder inserts rows via injected DatabaseManager', () async {
    await migrator.runMigrationList([_mig1, _mig2]);

    await SeederRunner(dbm).call(WidgetsSeeder());

    final count = await db.table('perf_widgets').count();
    expect(count, equals(2));

    final active = await db.table('perf_widgets')
        .where('active', '=', true).count();
    expect(active, equals(1));
  });
}
