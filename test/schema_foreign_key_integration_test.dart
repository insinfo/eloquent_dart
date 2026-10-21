// Migrations: foreign(), deferrable(), dropForeign(), dropColumn() and
// rename() produced no SQL on PostgreSQL (foreign() also on MySQL), so the
// commands were silently skipped. Requires localhost:5432 / 3306,
// database `banco_teste`, dart/dart.
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
        'host': 'localhost',
        'port': '5432',
        'database': 'banco_teste',
        'username': 'dart',
        'password': 'dart',
        'charset': 'utf8',
        'schema': ['public'],
      };

void main() {
  for (final driver in ['pgsql', 'mysql']) {
    group(driver, () {
      late Manager manager;
      late Connection db;
      late SchemaBuilder schema;

      Future<void> cleanup() async {
        for (final t in [
          'eloq_fk_pedido2',
          'eloq_fk_pedido',
          'eloq_fk_cliente'
        ]) {
          await db.execute('DROP TABLE IF EXISTS $t');
        }
      }

      setUp(() async {
        manager = Manager()..addConnection(_config(driver), 'fk_$driver');
        db = await manager.getConnection('fk_$driver');
        schema = db.getSchemaBuilder();
        await cleanup();
        await schema.create('eloq_fk_cliente', (t) {
          t.integer('id');
          t.primary('id');
        });
        await schema.create('eloq_fk_pedido', (t) {
          t.integer('id');
          t.integer('cliente_id');
          t.string('obs');
          t.nullable();
          t.foreign('cliente_id');
          t.references('id');
          t.on('eloq_fk_cliente');
          t.onDelete('cascade');
        });
      });

      tearDown(() async {
        await cleanup();
        await manager.getDatabaseManager().purge('fk_$driver');
      });

      test('foreign() creates the constraint, dropForeign() removes it',
          () async {
        await db.table('eloq_fk_cliente').insert({'id': 1});
        await db.table('eloq_fk_pedido').insert({'id': 1, 'cliente_id': 1});
        await expectLater(
            db.table('eloq_fk_pedido').insert({'id': 2, 'cliente_id': 99}),
            throwsA(anything));

        await db.table('eloq_fk_cliente').where('id', 1).delete();
        expect(await db.table('eloq_fk_pedido').count(), 0,
            reason: 'on delete cascade');

        await schema.table('eloq_fk_pedido', (t) {
          t.dropForeign('eloq_fk_pedido_cliente_id_foreign');
        });
        await db.table('eloq_fk_pedido').insert({'id': 3, 'cliente_id': 99});
        expect(await db.table('eloq_fk_pedido').count(), 1);
      });

      test('dropColumn() and rename()', () async {
        await schema.table('eloq_fk_pedido', (t) {
          t.dropColumn(['obs']);
        });
        await expectLater(
            db.select('select obs from eloq_fk_pedido'), throwsA(anything));

        await schema.rename('eloq_fk_pedido', 'eloq_fk_pedido2');
        expect(await db.table('eloq_fk_pedido2').count(), 0);
      });

      if (driver == 'pgsql') {
        test('deferrable() + initiallyDeferred() checks at COMMIT', () async {
          await schema.table('eloq_fk_pedido', (t) {
            t.dropForeign('eloq_fk_pedido_cliente_id_foreign');
          });
          await schema.table('eloq_fk_pedido', (t) {
            t.foreign('cliente_id');
            t.references('id');
            t.on('eloq_fk_cliente');
            t.deferrable();
            t.initiallyDeferred();
          });
          final row = (await db.select(
                  "select condeferrable, condeferred from pg_constraint "
                  "where conname = 'eloq_fk_pedido_cliente_id_foreign'"))
              .single;
          expect(row['condeferrable'], isTrue);
          expect(row['condeferred'], isTrue);

          // The child row comes first; the parent arrives before COMMIT.
          await db.transaction((ctx) async {
            await ctx
                .table('eloq_fk_pedido')
                .insert({'id': 1, 'cliente_id': 7});
            await ctx.table('eloq_fk_cliente').insert({'id': 7});
          });
          expect(await db.table('eloq_fk_pedido').count(), 1);
        });
      }
    });
  }

  test('an invalid referential action is rejected', () {
    final grammar = SchemaPostgresGrammar();
    final blueprint = Blueprint('t', (t) {
      t.foreign('a');
      t.references('id');
      t.on('o');
      t.onDelete('cascade; drop table x');
    });
    final command = blueprint.getCommands().last;
    expect(
        () => grammar.compileForeign(blueprint, command), throwsArgumentError);
  });
}
