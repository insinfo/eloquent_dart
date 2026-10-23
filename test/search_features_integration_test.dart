// Live tests for whereSearch / unaccent, orderByInput, whereInTuple,
// whereRowValues, whereAnyArray, between columns, explain, afterQuery,
// updateFrom, cursorPaginate and paginateWithWindowCount, in QueryBuilder and
// QueryBuilder2, on PostgreSQL (postgres, postgres_v3, dargres, dpgsql) and
// MariaDB/MySQL. Requires localhost:5432 and localhost:3306, database
// `banco_teste`, user/password `dart`/`dart` (PostgreSQL: superuser, for
// CREATE EXTENSION unaccent).
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

const _table = 'eloquent_search_feat';
const _other = 'eloquent_search_feat2';

const _names = [
  'José da Silva', // 1
  'JOSE SANTOS', // 2
  'Maria 10% Off', // 3
  'Ana_Paula', // 4
  'Ana Paula', // 5
  'João Pedro', // 6
  'Mário Silva', // 7
  'Pedro Álvares', // 8
  'Beatriz', // 9
  'Carlos', // 10
];

void main() {
  for (final driver in [
    'postgres',
    'postgres_v3',
    'dargres',
    'dpgsql',
    'mysql'
  ]) {
    final isPg = driver != 'mysql';
    group(driver, () {
      late Manager manager;
      late Connection db;
      final name = 'search_$driver';

      setUp(() async {
        manager = Manager()..addConnection(_config(driver), name);
        db = await manager.getConnection(name);
        if (isPg) await db.execute('CREATE EXTENSION IF NOT EXISTS unaccent');
        await db.execute('DROP TABLE IF EXISTS $_table');
        await db.execute('DROP TABLE IF EXISTS $_other');
        await db.execute('CREATE TABLE $_table (id int PRIMARY KEY, '
            'nome varchar(60), ano int, numero int, valor int, minimo int, '
            'maximo int, criado timestamp, '
            'uid ${isPg ? 'uuid' : 'char(36)'})');
        await db
            .execute('CREATE TABLE $_other (ref int PRIMARY KEY, flag int)');
        await db.table(_table).insertMany([
          for (var i = 1; i <= _names.length; i++)
            {
              'id': i,
              'nome': _names[i - 1],
              'ano': 2023 + (i % 3),
              'numero': i,
              'valor': i * 10,
              'minimo': 20,
              'maximo': 60,
              'criado': DateTime(2026, 1, 1 + (i % 4), 10, 0, i),
              'uid': '00000000-0000-0000-0000-${i.toString().padLeft(12, '0')}',
            }
        ]);
        await db.table(_other).insertMany([
          {'ref': 2, 'flag': 1},
          {'ref': 4, 'flag': 1},
          {'ref': 6, 'flag': 0},
        ]);
      });

      tearDown(() async {
        await db.execute('DROP TABLE IF EXISTS $_table');
        await db.execute('DROP TABLE IF EXISTS $_other');
        await manager.getDatabaseManager().purge(name);
      });

      Future<List<int>> ids(QueryBuilder query) async {
        final rows = await query.orderBy('id').get(['id']);
        return [for (final row in rows) row['id'] as int];
      }

      Future<List<int>> ids2(QueryBuilder2 query) async {
        final rows = await (query..select(['id'])).orderBy('id').get();
        return [for (final row in rows) row['id'] as int];
      }

      test('whereSearch matches the term literally', () async {
        // `%` and `_` of the term are not wildcards.
        expect(await ids(db.table(_table).whereSearch(['nome'], '10%')), [3]);
        expect(await ids(db.table(_table).whereSearch(['nome'], 'a_p')), [4]);
        expect(await ids(db.table(_table).whereAnyLike(['nome'], 'ana_paula')),
            [4, 5]);
        expect(
            await ids(db.table(_table).whereSearch(['nome'], 'silva')), [1, 7]);
        expect(
            await ids(db
                .table(_table)
                .whereSearch(['nome'], 'pedro', match: SearchMatch.startsWith)),
            [8]);
        expect(
            await ids(db
                .table(_table)
                .whereSearch(['nome'], 'carlos', match: SearchMatch.exact)),
            [10]);
        expect(await ids(db.table(_table).whereSearch(['nome'], null)),
            [for (var i = 1; i <= 10; i++) i]);
        expect(await ids2(db.table2(_table).whereSearch(['nome'], 'silva')),
            [1, 7]);
        // Words in order, anything between ("Contido no nome").
        expect(
            await ids(db.table(_table).whereSearch(['nome'], 'ana paula',
                match: SearchMatch.wordsInOrder)),
            [4, 5]);
        expect(
            await ids(db.table(_table).whereSearch(['nome'], 'paula ana',
                match: SearchMatch.wordsInOrder)),
            isEmpty);
        // lower() on both sides finds the same rows as ilike / the collation.
        expect(
            await ids(
                db.table(_table).whereSearch(['nome'], 'SILVA', lower: true)),
            [1, 7]);
        expect(
            await ids2(
                db.table2(_table).whereSearch(['nome'], 'jose s', lower: true)),
            [2]);
      });

      if (isPg) {
        test('unaccent and everyWord (PostgreSQL)', () async {
          expect(
              await ids(db
                  .table(_table)
                  .whereSearch(['nome'], 'jose', unaccent: true)),
              [1, 2]);
          expect(
              await ids(db
                  .table(_table)
                  .whereSearch(['nome'], 'joao', unaccent: true)),
              [6]);
          expect(
              await ids(db.table(_table).whereSearch(['nome'], 'jose')), [2]);
          expect(
              await ids(db
                  .table(_table)
                  .whereSearch(['nome'], 'JOSÉ', unaccent: true, lower: true)),
              [1, 2]);
          // An expression index on lower(unaccent(...)) needs an IMMUTABLE
          // function: the wrapper the grammar can be told to use. Its body
          // names the schema: since PostgreSQL 17, CREATE INDEX runs index
          // functions with search_path = pg_catalog, pg_temp.
          final schema =
              (await db.select('select extnamespace::regnamespace::text as s '
                      "from pg_extension where extname = 'unaccent'"))
                  .first['s'];
          await db
              .execute('CREATE OR REPLACE FUNCTION eloquent_f_unaccent(text) '
                  'RETURNS text LANGUAGE sql IMMUTABLE AS '
                  "\$\$ SELECT $schema.unaccent(\$1) \$\$");
          await db.execute('CREATE INDEX eloquent_search_feat_nome_idx ON '
              '$_table (lower(eloquent_f_unaccent(nome::text)) text_pattern_ops)');
          final grammar = db.getQueryGrammar() as QueryPostgresGrammar;
          final previous = grammar.unaccentFunction;
          grammar.unaccentFunction = 'eloquent_f_unaccent';
          try {
            expect(
                await ids(db.table(_table).whereSearch(['nome'], 'MARI',
                    unaccent: true,
                    lower: true,
                    match: SearchMatch.startsWith)),
                [3, 7]);
          } finally {
            grammar.unaccentFunction = previous;
            await db
                .execute('DROP INDEX IF EXISTS eloquent_search_feat_nome_idx');
            await db
                .execute('DROP FUNCTION IF EXISTS eloquent_f_unaccent(text)');
          }
          expect(
              await ids(db.table(_table).whereSearch(['nome'], 'silva jose',
                  unaccent: true, everyWord: true)),
              [1]);
          expect(
              await ids(db.table(_table).whereSearch(
                  [QueryExpression("nome || ' ' || ano")], 'silva 2024',
                  unaccent: true)),
              [1, 7]);
          expect(
              await ids2(db
                  .table2(_table)
                  .whereSearch(['nome'], 'alvares', unaccent: true)),
              [8]);
        });
      }

      test('orderByInput', () async {
        final allowed = {
          'nome': 'nome',
          'chave': ['ano', 'numero']
        };
        final byName = await db
            .table(_table)
            .orderByInput('nome', 'DESC', allowed: allowed)
            .limit(2)
            .get(['id']);
        expect(byName.map((r) => r['id']), [8, 7]);
        final fallback = await db
            .table(_table)
            .orderByInput('nome; drop table x', 'desc',
                allowed: allowed, fallback: 'id', fallbackDirection: 'desc')
            .limit(2)
            .get(['id']);
        expect(fallback.map((r) => r['id']), [10, 9]);
        final composite = await db
            .table2(_table)
            .select(['id'])
            .orderByInput('chave', 'asc', allowed: allowed)
            .limit(3)
            .get();
        expect(composite.map((r) => r['id']), [3, 6, 9]);
      });

      test('whereInTuple / whereRowValues', () async {
        // id i: ano = 2023 + i % 3, numero = i.
        expect(
            await ids(db.table(_table).whereInTuple([
              'ano',
              'numero'
            ], [
              [2024, 1],
              [2025, 2],
              [2025, 3], // no such row
            ])),
            [1, 2]);
        expect(
            await ids(db.table(_table).whereNotInTuple([
              'ano',
              'numero'
            ], [
              [2024, 1]
            ])),
            [2, 3, 4, 5, 6, 7, 8, 9, 10]);
        expect(await ids(db.table(_table).whereInTuple(['ano', 'numero'], [])),
            isEmpty);
        expect(
            await ids(db
                .table(_table)
                .whereRowValues(['ano', 'numero'], '>=', [2025, 5])),
            [5, 8]);
        expect(
            await ids2(db.table2(_table).whereInTuple([
              'ano',
              'numero'
            ], [
              [2023, 3]
            ])),
            [3]);
      });

      test('whereAnyArray', () async {
        expect(await ids(db.table(_table).whereAnyArray('id', {2, 4, 99})),
            [2, 4]);
        expect(
            await ids(
                db.table(_table).whereAnyArray('nome', ['Beatriz', 'Carlos'])),
            [9, 10]);
        expect(await ids(db.table(_table).whereAnyArray('id', [])), isEmpty);
        expect(
            await ids(db
                .table(_table)
                .where('id', '<', 5)
                .whereNotAnyArray('id', [1, 2])),
            [3, 4]);
        expect(
            await ids(db.table(_table).whereAnyArray(
                'uid',
                [
                  '00000000-0000-0000-0000-000000000003',
                  '00000000-0000-0000-0000-000000000005',
                ],
                elementType: isPg ? 'uuid' : null)),
            [3, 5]);
        // One statement for any number of values.
        final many = [for (var i = 1; i <= 3000; i++) i];
        expect(
            (await ids(db.table(_table).whereAnyArray('id', many))).length, 10);
        expect(await ids2(db.table2(_table).whereAnyArray('id', [7])), [7]);
      });

      test('between columns / value between', () async {
        // valor = id * 10, between 20 and 60.
        expect(
            await ids(db
                .table(_table)
                .whereBetweenColumns('valor', ['minimo', 'maximo'])),
            [2, 3, 4, 5, 6]);
        expect(
            await ids(db
                .table(_table)
                .where('id', '<', 3)
                .whereNotBetweenColumns('valor', ['minimo', 'maximo'])),
            [1]);
        expect(
            await ids(db
                .table(_table)
                .where('id', '<', 3)
                .whereValueBetween(30, ['minimo', 'maximo'])),
            [1, 2]);
        expect(
            await ids(db
                .table(_table)
                .whereValueNotBetween(30, ['minimo', 'maximo'])),
            isEmpty);
        expect(
            await ids2(db
                .table2(_table)
                .where('id', 1)
                .whereValueBetween(25, 'minimo', 'maximo')),
            [1]);
      });

      test('explain', () async {
        final plan = await db.table(_table).where('id', 3).explain();
        expect(plan, isNotEmpty);
        if (isPg) {
          final analyzed =
              await db.table2(_table).where('id', 3).explain(analyze: true);
          expect(analyzed.toString(), contains('actual'));
        }
      });

      test('afterQuery', () async {
        final rows = await db
            .table(_table)
            .where('id', '<', 3)
            .orderBy('id')
            .afterQuery((rows) => [
                  for (final row in rows) {...row, 'rotulo': 'n${row['id']}'}
                ])
            .get(['id']);
        expect(rows.map((r) => r['rotulo']), ['n1', 'n2']);
        expect(
            await db
                .table(_table)
                .afterQuery((rows) => <Map<String, dynamic>>[])
                .count(),
            10);
      });

      test('updateFrom', () async {
        final updated = await db
            .table(_table)
            .join(_other, '$_table.id', '=', '$_other.ref')
            .where('$_other.flag', 1)
            .updateFrom({'valor': 0});
        expect(updated, 2);
        expect(await ids(db.table(_table).where('valor', 0)), [2, 4]);
      });

      test('cursorPaginate forward and back', () async {
        // Order by ano desc, criado, id: a composite key with a timestamp.
        Future<CursorPage> page([String? cursor]) => db
            .table(_table)
            .orderByDesc('ano')
            .orderBy('criado')
            .orderBy('id')
            .cursorPaginate(
                perPage: 3, cursor: cursor, columns: ['id', 'ano', 'criado']);

        final expected = (await db
                .table(_table)
                .orderByDesc('ano')
                .orderBy('criado')
                .orderBy('id')
                .get(['id']))
            .map((r) => r['id'] as int)
            .toList();

        final forward = <List<int>>[];
        String? cursor;
        CursorPage current;
        do {
          current = await page(cursor);
          forward.add([for (final row in current.items) row['id'] as int]);
          cursor = current.nextCursor;
        } while (cursor != null);
        expect(forward.expand((p) => p).toList(), expected);
        expect(forward.map((p) => p.length), [3, 3, 3, 1]);

        final backward = <List<int>>[];
        cursor = current.previousCursor;
        while (cursor != null) {
          final previous = await page(cursor);
          backward.add([for (final row in previous.items) row['id'] as int]);
          cursor = previous.previousCursor;
        }
        expect(backward, forward.reversed.skip(1).toList());

        final q2 = await db
            .table2(_table)
            .select(['id'])
            .orderBy('id')
            .cursorPaginate(perPage: 4);
        final q2next = await db
            .table2(_table)
            .select(['id'])
            .orderBy('id')
            .cursorPaginate(perPage: 4, cursor: q2.nextCursor);
        expect(q2next.items.map((r) => r['id']), [5, 6, 7, 8]);
      });

      test('paginateWithWindowCount matches paginate', () async {
        final query = db.table(_table).where('id', '>', 2).orderBy('id');
        final window =
            await query.clone().paginateWithWindowCount(perPage: 3, page: 2);
        final classic = await query.clone().paginate(perPage: 3, page: 2);
        expect(window.total(), classic.total());
        expect(window.total(), 8);
        expect(window.items(), classic.items());
        expect(
            window.items().first.containsKey('eloquent_window_total'), isFalse);
        final past =
            await query.clone().paginateWithWindowCount(perPage: 3, page: 9);
        expect(past.total(), 8);
        expect(past.items(), isEmpty);
        final q2 = await db
            .table2(_table)
            .select(['id'])
            .orderBy('id')
            .paginateWithWindowCount(page: 1, perPage: 4);
        expect(q2.total, 10);
        expect(q2.items.map((r) => r['id']), [1, 2, 3, 4]);
      });

      test('QueryBuilder2 parity', () async {
        expect(await ids2(db.table2(_table).whereAny(['numero', 'valor'], 30)),
            [3]);
        expect(await ids2(db.table2(_table).whereDate('criado', '2026-01-02')),
            [1, 5, 9]);
        expect(
            await ids2(db.table2(_table).whereYear('criado', 2026))
                .then((list) => list.length),
            10);
        expect(await db.table2(_table).where('id', 999).exists(), isFalse);
        await expectLater(db.table2(_table).where('id', 999).firstOrFail(),
            throwsA(isA<RecordsNotFoundException>()));
        final pages = <int>[];
        await db.table2(_table).chunkById(4, (rows) {
          pages.add(rows.length);
          return true;
        });
        expect(pages, [4, 4, 2]);
        final inserted = await db.table2(_other).insertUsing(
            ['ref', 'flag'],
            db
                .table2(_table)
                .selectRaw('id + 100')
                .selectRaw('2')
                .where('id', 1, operator: CompOperator.lessThanOrEqualTo));
        expect(inserted, 1);
        expect(await db.table2(_other).where('flag', 2).count(), 1);
        if (isPg) {
          final latest = await db
              .table2('$_table as p')
              .select(['p.id', 'ultimo.numero'])
              .leftJoinLateral(
                  db
                      .table2('$_table as q')
                      .select(['q.numero'])
                      .whereColumn('q.ano', 'p.ano')
                      .orderByDescending('q.numero')
                      .limit(1),
                  'ultimo')
              .where('p.id', 1)
              .first();
          expect(latest!['numero'], 10); // ano 2024: ids 1, 4, 7, 10
          final firstOfYear = await db
              .table2(_table)
              .select(['ano', 'id'])
              .distinctOn(['ano'])
              .orderBy('ano')
              .orderBy('id')
              .get();
          expect(firstOfYear.map((r) => r['id']), [3, 1, 2]);
        }
      });
    });
  }
}
