// Doctrine platforms against real databases: a Schema built in memory is
// created with toSql(), introspected (A), dropped and created again from A,
// introspected (B), and A and B must not differ.
// Requires localhost:5432 / 3306, database `banco_teste`, dart/dart.
@Tags(['integration'])
library;

import 'package:eloquent/eloquent.dart';
import 'package:test/test.dart';

Map<String, dynamic> _config(String driver) => driver == 'mysql'
    ? {
        'driver': 'mysql',
        'host': 'localhost',
        'port': '3306',
        'database': 'banco_teste',
        'username': 'dart',
        'password': 'dart',
      }
    : {
        'driver': 'pgsql',
        'driver_implementation': driver,
        'host': 'localhost',
        'port': '5432',
        'database': 'banco_teste',
        'username': 'dart',
        'password': 'dart',
        'charset': 'utf8',
        'schema': ['public'],
      };

const _prefix = 'dpl_';

/// The application's schema, built in memory.
Schema _expected({required bool postgres}) {
  final schema = Schema();
  final cliente = schema.createTable('${_prefix}cliente');
  cliente.addColumn('id', 'integer', options: {'autoIncrement': true});
  cliente.addColumn('nome', 'string', options: {'length': 80});
  cliente.addColumn('email', 'string',
      options: {'length': 120, 'nullable': true, 'comment': 'contato'});
  cliente.setPrimaryKey(['id']);
  cliente.addUniqueIndex(columns: ['email'], name: '${_prefix}cliente_email_uniq');
  cliente.addOption('comment', 'clientes');

  final pedido = schema.createTable('${_prefix}pedido');
  pedido.addColumn('id', 'bigInteger', options: {'autoIncrement': true});
  pedido.addColumn('cliente_id', 'integer');
  pedido.addColumn('total', 'decimal', options: {'precision': 10, 'scale': 2});
  pedido.addColumn('status', 'string', options: {'length': 20});
  pedido.setPrimaryKey(['id']);
  pedido.addIndex(columns: ['status'], name: '${_prefix}pedido_status_idx');
  pedido.addForeignKey(
      localColumns: ['cliente_id'],
      foreignTableName: '${_prefix}cliente',
      foreignColumns: ['id'],
      name: '${_prefix}pedido_cliente_fk',
      options: {
        'onDelete': 'cascade',
        if (postgres) 'deferrable': true,
        if (postgres) 'deferred': true,
      });
  if (postgres) {
    schema.createSequence('${_prefix}protocolo', initialValue: 100, cache: 5);
  }
  return schema;
}

/// The introspected schema, limited to this test's objects.
Future<Schema> _introspect(Connection db) async {
  final all = await db.getDoctrineSchemaManager().introspectSchema();
  return Schema(
    tables: [
      for (final table in all.getTables())
        if (table.getName().startsWith(_prefix)) table,
    ],
    sequences: [
      for (final sequence in all.getSequences())
        if (sequence.getName().startsWith(_prefix)) sequence,
    ],
    schemaConfig: SchemaConfig(name: all.getName()),
  );
}

void main() {
  for (final driver in ['postgres', 'dpgsql', 'mysql']) {
    group(driver, () {
      late Manager manager;
      late Connection db;
      final postgres = driver != 'mysql';

      Future<void> dropAll() async {
        for (final table in ['${_prefix}pedido', '${_prefix}cliente']) {
          await db.execute('DROP TABLE IF EXISTS $table');
        }
        if (postgres) {
          await db.execute('DROP SEQUENCE IF EXISTS ${_prefix}protocolo');
        }
      }

      setUp(() async {
        manager = Manager()..addConnection(_config(driver), 'dpl_$driver');
        db = await manager.getConnection('dpl_$driver');
        await dropAll();
      });

      tearDown(() async {
        await dropAll();
        await manager.getDatabaseManager().purge('dpl_$driver');
      });

      test('create, introspect, recreate: no differences', () async {
        final platform = db.getDatabasePlatform();
        expect(platform, postgres ? isA<PostgreSQLPlatform>() : isA<MySQLPlatform>());

        for (final sql in _expected(postgres: postgres).toSql(platform)) {
          await db.execute(sql);
        }
        final a = await _introspect(db);

        final cliente = a.getTable('${_prefix}cliente');
        expect(cliente.getPrimaryKey()!.getColumns(), ['id']);
        expect(cliente.getColumn('id').autoIncrement, isTrue);
        expect(cliente.getColumn('nome').length, 80);
        expect(cliente.getColumn('email').notnull, isFalse);
        expect(cliente.getColumn('email').comment, 'contato');
        expect(cliente.getComment(), 'clientes');
        expect(
            cliente.getIndexes().where((i) => i.isUnique && !i.isPrimary).single.getColumns(),
            ['email']);

        final pedido = a.getTable('${_prefix}pedido');
        expect(pedido.getColumn('total').precision, 10);
        expect(pedido.getColumn('total').scale, 2);
        expect(pedido.hasIndex('${_prefix}pedido_status_idx'), isTrue);
        final fk = pedido.getForeignKey('${_prefix}pedido_cliente_fk');
        expect(fk.getForeignTableName(), '${_prefix}cliente');
        expect(fk.getOnDelete(), 'CASCADE');
        if (postgres) {
          expect(fk.getOption('deferrable'), isTrue);
          expect(fk.getOption('deferred'), isTrue);
          final sequence = a.getSequence('${_prefix}protocolo');
          expect(sequence.getCache(), 5);
          expect(sequence.getInitialValue(), 100);
        }

        // Drop and create again from what was read.
        for (final sql in a.toDropSql(platform)) {
          await db.execute(sql);
        }
        expect(await db.getDoctrineSchemaManager().tablesExist(['${_prefix}pedido']),
            isFalse);
        for (final sql in a.toSql(platform)) {
          await db.execute(sql);
        }
        final b = await _introspect(db);

        final diff = Comparator().compareSchemas(a, b);
        expect(diff.isEmpty(), isTrue,
            reason: platform.getAlterSchemaSQL(diff).join('\n'));
      });

      test('compareSchemas + getAlterSchemaSQL migrate a live schema', () async {
        final platform = db.getDatabasePlatform();
        for (final sql in _expected(postgres: postgres).toSql(platform)) {
          await db.execute(sql);
        }
        final current = await _introspect(db);

        final wanted = current.clone();
        wanted.getTable('${_prefix}pedido').addColumn('observacao', 'string',
            options: {'length': 60, 'nullable': true});
        final diff = Comparator().compareSchemas(current, wanted);
        for (final sql in platform.getAlterSchemaSQL(diff)) {
          await db.execute(sql);
        }

        final after = await _introspect(db);
        expect(after.getTable('${_prefix}pedido').hasColumn('observacao'), isTrue);
        expect(Comparator().compareSchemas(wanted, after).isEmpty(), isTrue,
            reason: platform
                .getAlterSchemaSQL(Comparator().compareSchemas(wanted, after))
                .join('\n'));
      });
    });
  }
}
