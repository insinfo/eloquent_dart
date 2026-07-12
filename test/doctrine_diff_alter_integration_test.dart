// doctrine_diff_alter_integration_test.dart
//
// Integration tests (require a live PostgreSQL) for the Doctrine
// introspection -> diff -> ALTER pipeline (Phase 7). These also guard the
// introspection fixes (pg_attrdef.adinhcount, oid-as-bind-param, int2vector
// indkey) that previously made live introspection throw.
//
// Connection: localhost:5432 db=postgres user/pass=dart (dpgsql driver).

@Tags(['integration'])
library;

import 'package:eloquent/eloquent.dart';
import 'package:eloquent/src/doctrine/schema/comparator.dart';
import 'package:test/test.dart';

const _config = {
  'driver': 'pgsql',
  'driver_implementation': 'dpgsql',
  'host': '127.0.0.1',
  'port': '5432',
  'database': 'postgres',
  'username': 'dart',
  'password': 'dart',
  'schema': ['public'],
};

void main() {
  late Manager manager;
  late Connection db;

  setUp(() async {
    manager = Manager();
    manager.addConnection(Map<String, dynamic>.from(_config));
    manager.setAsGlobal();
    db = await manager.connection();

    await db.execute('DROP TABLE IF EXISTS perf_diff');
    await db.execute('''
      CREATE TABLE perf_diff (
        id serial primary key,
        name varchar(50),
        age int not null,
        old_col text
      )
    ''');
    await db.execute(
        'CREATE INDEX perf_diff_name_idx ON perf_diff (name)');
  });

  tearDown(() async {
    await db.execute('DROP TABLE IF EXISTS perf_diff');
    await manager.getDatabaseManager().purge('default');
  });

  test('live introspection returns columns and indexes', () async {
    final sm = db.getDoctrineSchemaManager();
    final table = await sm.listTableDetails('perf_diff');

    final byName = {for (final c in table.getColumns()) c.getName(): c};
    expect(byName.keys, containsAll(['id', 'name', 'age', 'old_col']));
    expect(byName['name']!.type, equals('string'));
    expect(byName['name']!.length, equals(50));
    expect(byName['age']!.notnull, isTrue);

    final indexNames = table.getIndexes().map((i) => i.getName()).toList();
    expect(indexNames, containsAll(['perf_diff_pkey', 'perf_diff_name_idx']));
  });

  test('introspecting the same table twice yields an empty diff', () async {
    final sm = db.getDoctrineSchemaManager();
    final a = await sm.listTableDetails('perf_diff');
    final b = await sm.listTableDetails('perf_diff');
    final diff = Comparator().compareTables(a, b);
    expect(diff.isEmpty(), isTrue,
        reason: 'introspection must round-trip without spurious diffs');
  });

  test('change column type + nullability -> ALTER -> applied', () async {
    final sm = db.getDoctrineSchemaManager();
    final grammar = db.getSchemaBuilder().grammar as SchemaPostgresGrammar;

    final bp = Blueprint('perf_diff');
    bp.text('name');
    bp.change();
    final age = bp.integer('age');
    age.attributes['nullable'] = true;
    bp.change();

    final diff = await grammar.getChangedDiff(bp, sm);
    final List<String> statements = grammar.compileTableDiff(diff, bp);

    expect(
      statements,
      containsAll([
        'alter table "perf_diff" alter column "name" type text',
        'alter table "perf_diff" alter column "age" drop not null',
      ]),
    );

    for (final s in statements) {
      await db.execute(s);
    }

    final after = {
      for (final c
          in (await sm.listTableDetails('perf_diff')).getColumns())
        c.getName(): c
    };
    expect(after['name']!.type, equals('text'));
    expect(after['age']!.notnull, isFalse);
  });

  test('add + drop columns via Comparator -> ALTER -> applied', () async {
    final sm = db.getDoctrineSchemaManager();
    final grammar = db.getSchemaBuilder().grammar as SchemaPostgresGrammar;

    final current = await sm.listTableDetails('perf_diff');

    // Desired: clone current, drop old_col, add email.
    final desired = current.clone();
    desired.dropColumn('old_col');
    desired.addColumn('email', 'string',
        options: {'length': 100, 'notnull': false});

    final diff = Comparator().compareTables(current, desired);
    final statements = grammar.compileTableDiff(diff, Blueprint('perf_diff'));

    for (final s in statements) {
      await db.execute(s);
    }

    final after = (await sm.listTableDetails('perf_diff'))
        .getColumns()
        .map((c) => c.getName())
        .toList();
    expect(after, contains('email'));
    expect(after, isNot(contains('old_col')));
  });
}
