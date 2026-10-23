# eloquent
[![CI](https://github.com/insinfo/eloquent_dart/actions/workflows/dart.yml/badge.svg)](https://github.com/insinfo/eloquent_dart/actions/workflows/dart.yml)
[![Pub Package](https://img.shields.io/pub/v/eloquent.svg)](https://pub.dev/packages/eloquent)  

#### Support My Work
[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/isaqueneves)

I’m on @buymeacoffee. If you like my work, you can buy me a ☕ and share your thoughts 🎉 [Buy me a coffee](https://www.buymeacoffee.com/isaqueneves)


eloquent 5.2 query builder port from PHP Laravel to dart

https://laravel.com/docs/5.2/queries

for now it only works with PostgreSQL and MySQL. PostgreSQL has four driver
implementations (`postgres`, `postgres_v3`, `dargres`, `dpgsql`) that return
the same Dart types.

### What's new in 4.0

Details, breaking changes and migration notes:
[doc/release_notes_4.0.0.md](doc/release_notes_4.0.0.md).

- [QueryBuilder2](#querybuilder2-dart-3-api): a Dart 3 API with fixed-meaning
  arguments and typed results (`db.table2()`).
- [Nested transactions](#transactions-nested-transactions-savepoint-and-transactionifneeded)
  (SAVEPOINT), `transactionIfNeeded` and the
  [ambient `transactionScope`](#ambient-transaction-transactionscope).
- [Unique violations, `createOrFirst` and explicit locks](#unique-values-createorfirst-and-explicit-locks):
  `UniqueConstraintViolationException`, `createOrFirst`/`firstOrCreate`,
  `advisoryLock`, `lockTable`; [row locks](#row-locks-for-update--for-share-skip-locked-nowait)
  with SKIP LOCKED/NOWAIT.
- [Search and filters](#search-filters-and-client-ordering) (`whereSearch`,
  `unaccent`, `orderByInput`), [pagination](#pagination) (offset, keyset,
  window count), [composite keys and arrays](#composite-keys-and-arrays).
- [UPSERT / ON CONFLICT / RETURNING](#upsert--on-conflict--returning-postgresql--mysql),
  [bulk inserts and numbering](#bulk-inserts-and-numbering) (`copyInto`,
  `insertUnnest`, `nextValue`).
- [Helpers ported from Laravel 12](#helpers-ported-from-laravel-12): query
  listeners, `toRawSql()`, `when`/`unless`, `whereAny`/`whereAll`, `sole`,
  `lazyById`...
- [Streaming](#streaming-large-result-sets-server-side-cursor) on every
  PostgreSQL adapter, [LISTEN/NOTIFY](#postgresql-listen--notify),
  [direct driver access](#direct-driver-access-copy-listennotify-raw-connection).
- [ORM](#orm-active-record-or-data-mapper-no-code-generation-no-reflection)
  without code generation (Active Record and Data Mapper),
  [migrations, seeders and CLI](#migrations-seeders-and-cli),
  [Doctrine schema port](#schema-objects-and-platforms-doctrine-dbal-port)
  and `schema:diff`.
- [Uniform PostgreSQL types](#postgresql-value-types-pg_types-and-driver-options)
  (`pg_types`), `driver_options` and
  [`datetime_bindings`](#datetime-bindings-datetime_bindings).


## Creating a connection executing a simple select
```dart
    final manager = new Manager();
    manager.addConnection({
      'driver': 'pgsql',
      'host': 'localhost',
      'port': '5432',
      'database': 'database_name',
      'username': 'user_name',
      'password': 'pass',
      'charset': 'utf8',
      'prefix': '',
      'schema': 'public',      
    });
    manager.setAsGlobal();
    final db = await manager.connection();

    final query = db.table('temp_location');
      final res = await query
          .select(['temp_location.id', 'city', 'street'])
          .where('temp_location.id', '=', 1)
          .join('people', 'people.id', '=', 'temp_location.id_people', 'inner')
          .limit(1)
          .offset(0)
          .get();

      expect(res, [
        {'id': 1, 'city': 'Niteroi', 'street': 'Rua B'}
      ]);

  // sub query example
   var subQuery = db.table('public.clientes')
    .selectRaw('clientes_grupos.numero_cliente as numero_cliente, json_agg(row_to_json(grupos.*)) as grupos')
    .join('public.clientes_grupos','clientes_grupos.numero_cliente','=','clientes.numero')
    .join('public.grupos','grupos.numero','=','clientes_grupos.numero_grupo')
    .groupBy('numero_cliente');

  var map = await db
      .table('clientes')
      .selectRaw('clientes.*, grupos.grupos ')
      .fromRaw('(SELECT * FROM public.clientes) AS clientes')
      .joinSub(subQuery, 'grupos',  (JoinClause join) {      
        join.on('grupos.numero_cliente', '=', 'clientes.numero');
      })
      .join('public.clientes_grupos','clientes_grupos.numero_cliente','=','clientes.numero')
      .where('clientes_grupos.numero_grupo','=','2')
    //.whereRaw('clientes.numero in ( SELECT clientes_grupos.numero_cliente FROM public.clientes_grupos WHERE clientes_grupos.
      .get();

  print(map.length);   


```

## QueryBuilder2 (Dart 3 API)

`db.table2('tabela')` returns a `QueryBuilder2`. Every argument has one
meaning: the value is always bound (`?`), operators are enums, columns are
identifiers, and SQL only enters through `whereRaw`/`selectRaw`/`havingRaw`.
Results are typed. `db.table()` (the Laravel-style `QueryBuilder`) is
unchanged.

```dart
final usuarios = await db
    .table2('usuarios')
    .select(['id', 'nome'])
    .where('ativo', true)                                  // "ativo" = ?
    .where('idade', 18, operator: ComparisonOperator.greaterThanOrEqualTo)
    .whereLessThan('tentativas', 5)                        // descriptive form
    .whereIn('perfil', ['administrador', 'operador'])
    .whereNull('excluido_em')
    .whereGroup((w) => w
        .where('cidade', 'Rio das Ostras')
        .orWhere('cidade', 'Macaé'))                       // and (... or ...)
    .whenNotNull(filtro.situacao, (q, s) => q.where('situacao', s))
    .orderBy('nome')
    .limit(50)
    .get();                                                // List<Map>

final total = await db.table2('pedidos').where('pago', true).count();
final nomes = await db.table2('usuarios').pluck<String>('nome');
```

| Call | SQL |
|---|---|
| `where('x', v)` / `whereEqualTo` | `x = ?` |
| `where('x', v, operator: .greaterThan)` / `whereGreaterThan` | `x > ?` |
| `where('x', null)` / `whereNotEqualTo('x', null)` | `x is null` / `x is not null` (other operators with null throw) |
| `whereIn('x', [])` / `whereNotIn('x', [])` | always false / always true (`null` elements throw) |
| `whereBetween('x', low, high)` | `x between ? and ?` |
| `whereLike('nome', 'isa%')` | PostgreSQL `ilike`; `caseSensitive: true` for `like` |
| `whereColumn('a', 'b')` | `a = b` (two columns) |
| `whereGroup((w) => ...)` / `whereNotGroup` | `and (...)` / `and not (...)` |
| `whereExists(sub)` / `whereInSubquery('id', sub)` | `exists (...)` / `id in (...)` |
| `whereSqlOperator('email', '~*', '@gmail')` | dialect predicate operators, validated |
| `whereRaw(sql, bindings)` | caller's SQL |

`whereSqlOperator` accepts the dialect's predicate operators: on PostgreSQL
the comparisons, `ilike`, `~~`, the regex operators `~ ~* !~ !~*`,
`similar to`, `is [not] distinct from`, `@> <@ &&`, `@@` and the
inet/range operators; on MySQL `<=>`, `like binary`, `regexp`, `rlike`,
`sounds like`. Arithmetic operators are rejected because they are not
conditions. `?`, `?|` and `?&` are rejected too, because `?` is the
placeholder: use `whereRaw('jsonb_exists(dados, ?)', ['telefone'])`.

Pagination, writes, unions and CTEs:

```dart
final page = await db.table2('processos').where('ativo', true)
    .orderByDescending('data').paginate(page: 2, perPage: 20);
return page.toMap(); // data, total, per_page, current_page, last_page, from, to

// Atomic sequence (PostgreSQL; on MySQL use insert(..., onConflict: ...)).
final rows = await db.table2('sequencias').insertReturning(
  {'ano': 2026, 'ultimo': 1},
  onConflict: OnConflict.doUpdate(
      columns: ['ano'], set: {'ultimo': db.raw('sequencias.ultimo + 1')}),
  returning: ['ultimo'],
);

await db.table2('estoque').upsert(itens, uniqueBy: ['sku'], update: ['qtd']);
await db.table2('log').insertOrIgnore(linhas);
final removidos = await db.table2('fila').where('status', 'feito')
    .deleteReturning(returning: ['id']);

// Recursive CTE: a sector and its descendants.
final ids = await db.table2('arvore')
    .withRecursiveExpression('arvore',
        db.table2('setor').select(['id']).where('id', 1).unionAll(
            db.table2('setor as s').select(['s.id'])
                .join('arvore as a', 'a.id', 's.pai_id')),
        columns: ['id'])
    .pluck<int>('id');
```

With `union`/`unionAll`, `orderBy`/`limit`/`offset` apply to the combined
result. A part with its own order or limit is wrapped in
`select * from (...)`.

Since Dart 3.10 you can leave out the enum name:
`operator: .greaterThanOrEqualTo`. Joins: `join`, `leftJoin`, `rightJoin`,
`crossJoin` and `joinOn('t', (j) => j.on(...).where(...))`. Writes:
`insert` (returns the rows inserted; `onConflict:`), `insertReturning`,
`insertMany`, `insertOrIgnore`, `upsert`, `insertGetId<T>`, `update`,
`updateReturning`, `delete`, `deleteReturning`, `increment`.
Locks: `lockForUpdate(skipLocked: true)`. `toQueryBuilder()` returns the
equivalent `QueryBuilder` for features not exposed yet.

## whereExists subquery
```dart
  // whereExists receives a QueryBuilder in the callback, so use from(...)
  var res = await db
      .table('usuario as usuario')
      .select(['numcgm'])
      .whereExists((q) {
        q.selectRaw('1')
            .from('administracao.usuario_organograma as uo_filtro')
            .whereColumn('uo_filtro.numcgm', '=', 'usuario.numcgm')
            .where('uo_filtro.id_organograma', '=', 10);
      })
      .get();

  // Alternative using raw EXISTS when needed
  var resRaw = await db
      .table('usuario as usuario')
      .whereRaw(
        '''
        EXISTS (
          SELECT 1
          FROM administracao.usuario_organograma uo_filtro
          WHERE uo_filtro.numcgm = usuario.numcgm
            AND uo_filtro.id_organograma = ?
        )
        ''',
        [10],
      )
      .get();
```

## Creating a connection executing insert/update/delete
```dart
   
    await db.table('temp_location')
        .insert({'id': 1, 'city': 'Rio de Janeiro', 'street': 'Rua R'});

    await db.table('temp_location')
        .where('id', '=', 1).update({'city': 'Teresopolis'});

    await db.table('temp_location')
        .where('id', '=', 1).delete();

```

## Transactions, nested transactions (SAVEPOINT) and transactionIfNeeded

`transaction()` returns the callback's value with its type, and the callback
receives a `Connection` bound to the transaction:

```dart
final id = await db.transaction<int>((ctx) async {   // id is an int
  return await ctx.table('pedidos').insertGetId({'cliente': 1}) as int;
});
```

Calling `transaction()` **on that `ctx`** does not open a second physical
transaction: it creates a `SAVEPOINT`. Success releases it; an error rolls back
to it and is **rethrown**, so the outer transaction can continue if you catch
it:

```dart
await db.transaction((ctx) async {
  await ctx.table('pedidos').insert({'id': 1});
  try {
    await ctx.transaction((nested) async {        // SAVEPOINT eloquent_savepoint_2
      await nested.table('itens').insert({'id': 10});
      throw Exception('Falha no item');           // ROLLBACK TO SAVEPOINT
    });
  } catch (_) {
    // only the item was rolled back
  }
  await ctx.table('auditoria').insert({'descricao': 'parcial'});
});                                               // COMMIT: pedido + auditoria
```

`transactionIfNeeded()` joins the current transaction (no SAVEPOINT) and only
opens one when there is none. Use it for functions that may be called on their
own or as part of a larger transaction:

```dart
Future<int> inserirAnexo(Map<String, dynamic> dados, {Connection? connection}) {
  return (connection ?? db).transactionIfNeeded((ctx) async =>
      (await ctx.table('anexo').insertGetId(dados)) as int);
}
```

| Call | Outside a transaction | Inside a transaction |
|---|---|---|
| `transaction()` | `BEGIN` / `COMMIT` (`ROLLBACK` on error) | `SAVEPOINT` / `RELEASE` (`ROLLBACK TO SAVEPOINT` on error, rethrown) |
| `transactionIfNeeded()` | `BEGIN` / `COMMIT` | reuses the current transaction |

`connection.isInTransaction`, `connection.transactionLevel()` (0 outside, 1 in
the transaction, 2+ in savepoints) and `connection.supportsSavepoints` expose the
state. It belongs to each `ctx`, never to global state, so concurrent requests
do not interfere. A driver context without SAVEPOINT support throws
`UnsupportedNestedTransactionException` instead of opening an independent
transaction.

> **Driver note:** with `postgres_v3`, an *SQL error* (for example a
> duplicate key) inside any part of a transaction makes the driver roll back
> the whole transaction, so a savepoint only isolates Dart exceptions there.
> `postgres` (postgres_fork, through its own `savepoint()`), `dargres`,
> `dpgsql` and MySQL recover with `ROLLBACK TO SAVEPOINT` and the outer
> transaction continues.

## Running a SQL script (unprepared)

`db.unprepared(sql)` (Laravel's `DB::unprepared`, PHP's `PDO::exec`) runs
raw SQL without bindings through the simple query protocol on every
PostgreSQL adapter, so a script with several statements runs whole:

```dart
await db.unprepared(File('scripts/6.4.0/4_orgao_emissor.sql').readAsStringSync());
```

The statements run as one implicit transaction unless the script has its own
`BEGIN`/`COMMIT`; `CREATE INDEX CONCURRENTLY` and `VACUUM` must be alone in
the text. psql meta-commands (`\set`, `\gexec`) are not SQL and are not
understood. Queries with bindings (`select`, `statement`, the query builder)
keep the extended protocol and its prepared statements.

## Ambient transaction: transactionScope

`db.transaction((ctx) ...)` only covers what runs through `ctx`: a repository
that uses `db` inside the callback runs on another pooled connection (outside
the transaction), or waits forever on a single connection.
`transactionScope` makes the transaction ambient for the callback:

```dart
await db.transactionScope((ctx) async {
  await processoRepository.encaminhar(dados);           // uses `db`: in the transaction
  await db.transaction((inner) async { /* ... */ });    // a SAVEPOINT of it
  await db.outsideTransaction(() => log.gravar(evento)); // survives a rollback (needs a pool)
});
```

The scope is a `Zone` value, so it covers only the async calls of the
callback; other requests on the same `db` are not affected. Inside it
`db.isInTransaction` and `db.isInTransactionScope` are true and
`db.transactionIfNeeded` joins the transaction.

## Row locks: FOR UPDATE / FOR SHARE, SKIP LOCKED, NOWAIT

```dart
// job queue: take the next pending job that no other worker holds
await db.transaction((ctx) async {
  final job = await ctx.table('jobs')
      .where('status', '=', 'pending')
      .orderBy('id')
      .lockForUpdate(skipLocked: true)  // ... for update skip locked
      .first();
  if (job == null) return;               // every pending job is taken
  // ... process and update the job
});

db.table('jobs').lockForUpdate();                  // for update
db.table('jobs').sharedLock();                     // for share
db.table('jobs').lockForUpdate(noWait: true);      // for update nowait
db.table('jobs').lockForUpdate(of: ['jobs'], skipLocked: true); // for update of "jobs" skip locked
db.table('jobs').skipLocked();                     // for update skip locked
db.table('jobs').lock('for no key update');        // raw clause, verbatim
```

MySQL uses the 8.0 syntax (`for share`, `skip locked`, `nowait`) whenever a
modifier is present; a plain `sharedLock()` keeps `lock in share mode`.

## Unique values, createOrFirst and explicit locks

A unique violation (PostgreSQL `23505`, MySQL 1062/1586) throws
`UniqueConstraintViolationException`, a `QueryException` with the violated
`constraint`, the `sql`/`bindings` and the driver's exception in `previous`
(its text is kept in `toString()`). Other driver errors are not wrapped. With
a unique index the database enforces the rule, without locks or races:

```dart
// CREATE UNIQUE INDEX tipo_norma_nome_uq
//   ON normas.tipo_norma (lower(public.immutable_unaccent(trim(nom_tipo_norma))));
try {
  await db.table('normas.tipo_norma').insert(item.toMap());
} on UniqueConstraintViolationException catch (e) {
  if (e.constraint != 'tipo_norma_nome_uq') rethrow;
  throw ConflictException('A type with this name already exists.');
}
```

`createOrFirst` / `firstOrCreate` (Laravel's semantics) insert the row, or
return the one a unique index already has:

```dart
final tag = await db.table('tags').createOrFirst({'slug': 'dart'}, {'nome': 'Dart'});
final user = await db.table2('users').firstOrCreate({'email': email}, {'nome': nome});
```

On PostgreSQL `createOrFirst` uses `insert ... on conflict do nothing
returning *`, so a conflict is not an error and a surrounding transaction
stays usable on every adapter; on MySQL it runs in a SAVEPOINT.

When the rule is not a unique value, serialize the code that checks and writes:

```dart
await db.transaction((ctx) async {
  // pg_advisory_xact_lock: one transaction at a time per key, until commit.
  // Reads, other writes and foreign key checks are not blocked.
  await ctx.advisoryLock('normas.tipo_norma');
  if (!await ctx.tryAdvisoryLock('other-key')) { /* held elsewhere */ }

  // LOCK TABLE "normas"."tipo_norma" IN EXCLUSIVE MODE (blocks much more)
  await ctx.table('normas.tipo_norma').lockTable(TableLockMode.exclusive);
  await ctx.table('fila').lockTable(TableLockMode.share, noWait: true);
});
```

| Need | Tool |
|---|---|
| A value must be unique (name, code per year) | Unique index + `UniqueConstraintViolationException` or `createOrFirst` |
| Lock the rows that will be changed | `lockForUpdate()` |
| One transaction at a time in a piece of code | `advisoryLock(key)`; `nextValue()` for a max + 1 |
| Block writes to the whole table | `lockTable(mode)` |

`advisoryLock` and `lockTable` need a transaction (`StateError` outside one)
and PostgreSQL (`UnsupportedError` on MySQL). The key is a `String` (hashed)
or an `int`.

## UPSERT / ON CONFLICT / RETURNING (PostgreSQL & MySQL)

```dart
// Atomic upsert (Laravel-style)
await db.table('users').upsert(
  [{'email': 'a@x.com', 'name': 'A'}],
  ['email'],            // conflict target columns
  {'name': 'A2'},       // DO UPDATE SET (optional; defaults to all non-unique cols)
);

// Insert or ignore
await db.table('users').insertOrIgnore({'email': 'a@x.com', 'name': 'A'});

// Low-level ON CONFLICT ... DO UPDATE ... RETURNING (lock-free sequence).
// Equivalent to PL/pgSQL's "RETURNING last_id INTO v_seq": the returned
// column is read directly in Dart, so no explicit locks are needed.
final rows = await db.table('processos_sequences')
  .onConflict(['ano'])
  .doUpdate({'last_id': db.raw('processos_sequences.last_id + 1')})
  .returning(['last_id'])
  .insert({'ano': 2026, 'last_id': 1});

final seq = rows.first['last_id'];
```

Generated SQL (PostgreSQL):

```sql
INSERT INTO processos_sequences (ano, last_id) VALUES (?, ?)
ON CONFLICT (ano) DO UPDATE SET last_id = processos_sequences.last_id + 1
RETURNING last_id;
```

> Note: `RETURNING ... INTO` is PL/pgSQL syntax (inside functions/DO blocks).
> The client-side idiom is `RETURNING <col>` whose value is read in Dart — which
> is exactly what `.returning([...]).insert(...)` returns (a `List<Map>`).

## Search, filters and client ordering

```dart
final query = db.table('cgm as c')
    // (unaccent(c.nom_cgm::text) ilike unaccent(?) or unaccent(c.cpf::text) ilike unaccent(?))
    // '%' and '_' in the term are escaped; a null or blank term adds nothing.
    .whereSearch(['c.nom_cgm', 'c.cpf'], filtros.searchString, unaccent: true)
    // the client's field goes through an allow-list, never into the SQL
    .orderByInput(filtros.orderBy, filtros.orderDir,
        allowed: {'nome': 'c.nom_cgm', 'cpf': 'c.cpf'}, fallback: 'c.numcgm');
```

- `whereSearch` options: `match` (`SearchMatch.contains` (default),
  `startsWith`, `endsWith`, `exact`, `wordsInOrder`), `everyWord` (each word
  in some column: "ana silva" finds "Ana Maria da Silva"), `lower: true`
  (`lower(col) like lower(?)`, the form an expression index can serve),
  `caseSensitive`. Columns are identifiers or `db.raw(...)`.
- `whereLike(column, pattern, {caseSensitive, unaccent, lower})`,
  `whereAnyLike(columns, pattern)`, `QueryBuilder.escapeLike(text)`.
- `unaccent` needs the PostgreSQL extension; set
  `QueryPostgresGrammar.unaccentFunction` to use an IMMUTABLE wrapper that an
  index can use. MySQL leaves case and accents to the collation.

## Pagination

```dart
// LIMIT/OFFSET + count
final page = await db.table('processo').orderBy('id').paginate(perPage: 20, page: 2);

// The same in one query (count(*) over ()); measure before using it.
final page2 = await db.table('processo').orderBy('id')
    .paginateWithWindowCount(perPage: 20, page: 2);

// Keyset pagination: no OFFSET, no count. Order by unique columns.
final first = await db.table('processo').orderBy('data').orderBy('id')
    .cursorPaginate(perPage: 50);
final next = await db.table('processo').orderBy('data').orderBy('id')
    .cursorPaginate(perPage: 50, cursor: first.nextCursor);
return next.toMap(); // data, per_page, next_cursor, prev_cursor
```

## Composite keys and arrays

```dart
// ("cod_processo", "ano_exercicio") in ((?, ?), (?, ?))
db.table('processo').whereInTuple(['cod_processo', 'ano_exercicio'], [[10, '2024'], [11, '2024']]);
// ("ano", "numero") > (?, ?)
db.table('processo').whereRowValues(['ano', 'numero'], '>', [2024, 100]);
// "id" = any(?) with ONE array parameter (PostgreSQL; MySQL: in (...))
db.table('processo').whereAnyArray('id', ids);
db.table('arquivo').whereAnyArray('uuid', uuids, elementType: 'uuid'); // ?::uuid[]
// "valor" between "minimo" and "maximo"; ? between "data_inicio" and "data_fim"
db.table('faixa').whereBetweenColumns('valor', ['minimo', 'maximo']);
db.table('vigencia').whereValueBetween(DateTime.now(), ['data_inicio', 'data_fim']);
```

## Bulk inserts and numbering

```dart
// COPY ... FROM STDIN on dpgsql, multi-row INSERTs elsewhere
await db.table('leitura').copyInto(rows);

// insert ... select * from unnest(?::int[], ?::text[]): one parameter per column
await db.table('leitura').insertUnnest(rows, types: {'id': 'int', 'nome': 'text'});

// max + 1 per scope under pg_advisory_xact_lock, in the inserting transaction
await db.transaction((ctx) async {
  final cod = await ctx.table('andamento')
      .where('cod_processo', '=', p)
      .nextValue('cod_andamento');
  await ctx.table('andamento').insert({'cod_processo': p, 'cod_andamento': cod});
});
```

## Helpers ported from Laravel 12

```dart
// Query listeners (failed statements included) and slow queries
final stop = db.listen((QueryExecuted q) => print('${q.time.inMilliseconds} ms ${q.toRawSql()}'));
db.onSlowQuery(Duration(milliseconds: 200), (q) => log.warning(q.sql));

// SQL with the bindings inlined, for logs and debugging (never execute it)
print(db.table('users').where('id', '=', 1).toRawSql());

// Conditional building
db.table('processo')
    .when(filtro.situacao, (QueryBuilder q, situacao) => q.where('situacao', situacao))
    .unless(incluirArquivados, (QueryBuilder q) => q.whereNull('arquivado_em'));

db.table('users').whereAny(['nome', 'email'], 'like', '%ana%'); // (... or ...)
db.table('users').whereAll(['a', 'b'], '>', 0);                 // (... and ...)
db.table('users').whereNot('situacao', 'C');
db.table('users').whereIntegerInRaw('id', ids);                 // no 65535-parameter limit

final user = await db.table('users').where('email', '=', e).sole(); // exactly one row
final row = await db.table('users').where('id', '=', 1).firstOrFail();
if (await db.table('users').where('id', '=', 1).doesntExist()) { /* ... */ }

await for (final row in db.table('users').lazyById(1000)) { /* keyset, every driver */ }
await db.table('contador').where('id', '=', 1).incrementEach({'acessos': 1, 'cliques': 2});
```

Also: `orderByDesc`, `reorder`, `select`/`addSelect` with subqueries,
`fromSub`, `leftJoinSub`, `eachById`, `chunkByIdDesc`, `chunkMap`,
`soleValue`, `findOr`, `existsOr`, `havingBetween`, `havingNull`,
`explain({analyze})`, `afterQuery(callback)` and MySQL `whereFullText`.

## Streaming large result sets (server-side cursor)

`cursor()` streams rows so memory stays roughly constant even for millions of
rows. `dpgsql` uses its incremental reader; the other PostgreSQL adapters use
an SQL cursor (`DECLARE ... FETCH`, inside the current transaction or one held
while the stream is read). MySQL throws `UnsupportedError` (use `lazyById`).

```dart
await for (final row in db.table('big_table').where('ativo', '=', true).cursor()) {
  process(row); // constant memory, no full materialization
}

// lazy() is an alias
final stream = db.table('big_table').lazy();
```

Contrast with `chunk`/`each`, which page with `LIMIT/OFFSET` and load a full
page into memory per round-trip.

## ORM: Active Record or Data Mapper (no code generation, no reflection)

Two options, both without `build_runner` or `dart:mirrors`, so they work
with AOT and Flutter:

- **Active Record** (`User extends Model<User>`): the model has plain Dart
  fields, `save()`/`delete()` and relations with eager loading.
- **Data Mapper** (`Repository<T>` + `EntityMapper<T>`, below): plain
  classes and a repository that reads and writes them.

### Active Record

A model implements three members, and the compiler requires them:
`modelDefinition`, `toMap()` and `fill()`.

```dart
class User extends Model<User> {
  static final definition = ModelDefinition<User>(
    table: 'users',
    create: User.new,                 // the constructor replaces reflection
    timestamps: true,                 // created_at / updated_at
    casts: {'ativo': Casts.boolean},
    fillable: ['name', 'email'],      // what assign() may set
    hidden: ['password'],             // left out of toJson()
  );

  @override
  ModelDefinition<User> get modelDefinition => definition;

  // Optional: User.query(db), like Laravel's User::query().
  static ModelQuery<User> query(Connection db) => definition.query(db);

  // Relations are declared once; the related definition is a function so
  // models can refer to each other.
  static final latestOrder = HasOne<User, Order>('latestOrder',
      () => Order.definition, foreignKey: 'user_id').latestOfMany();
  static final largestOrder = HasOne<User, Order>('largestOrder',
      () => Order.definition, foreignKey: 'user_id')
      .ofMany('price', AggregateFunction.maximum);
  static final orders = HasMany<User, Order>('orders',
      () => Order.definition, foreignKey: 'user_id');

  int? id;
  String name = '';
  String? email;
  String? password;
  bool? ativo;

  @override
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'email': email,
        'password': password,
        'ativo': ativo,
      };

  @override
  void fill(Map<String, dynamic> row) {   // the values come through the casts
    id = row['id'] as int?;
    name = row['name'] as String;
    email = row['email'] as String?;
    password = row['password'] as String?;
    ativo = row['ativo'] as bool?;
  }
}

class Order extends Model<Order> {
  static final definition = ModelDefinition<Order>(
      table: 'orders', create: Order.new, casts: {'price': Casts.decimal});
  @override
  ModelDefinition<Order> get modelDefinition => definition;

  static final user = BelongsTo<Order, User>('user', () => User.definition,
      foreignKey: 'user_id');

  int? id;
  int? userId;
  double? price;

  @override
  Map<String, dynamic> toMap() => {'id': id, 'user_id': userId, 'price': price};
  @override
  void fill(Map<String, dynamic> row) {
    id = row['id'] as int?;
    userId = row['user_id'] as int?;
    price = row['price'] as double?;
  }
}

final user = await User.query(db).findOrFail(10);
user.name = 'Isaque';
await user.save();                       // update ... set name = ? (only what changed)

final ana = User()..name = 'Ana';
await ana.save(using: db);               // insert; id and defaults read back

final bia = User.definition.make(db)
  ..assign(request.body);                // only the fillable columns
await bia.save();

final latest = await User.latestOrder.fetch(user);   // one user

final users = await User.query(db)                   // many users:
    .where('ativo', true)                            // QueryBuilder2 where API
    .withRelation(User.latestOrder)                  // one query per relation
    .withRelation(User.largestOrder)
    .withRelation(User.orders)
    .get();
final Order? o = User.largestOrder.getLoaded(users.first);
return users.first.toJson();             // fields without hidden + loaded relations
```

Why `create: User.new` and the static `definition`: Laravel's
`User::query()` is `(new static)->newQuery()`, PHP's late static binding.
Dart has no late static binding, statics are not inherited and a `T` cannot
be created from a type parameter, so the definition holds the constructor
the ORM calls for each row. Dart cannot require a static member, but it
requires the abstract `modelDefinition` getter. A static and an instance
member cannot share a name, so give the static field, the `query` shortcut
and scopes names that are not fields.

| Relation | Picks |
|---|---|
| `HasOne(...).latestOfMany([column])` | highest `column` (default: primary key) |
| `HasOne(...).oldestOfMany([column])` | lowest `column` |
| `HasOne(...).ofMany(column, AggregateFunction.maximum/minimum)` | highest/lowest `column`; null values are not candidates; ties go to the highest primary key |
| `HasOne(...)` | the related row (lowest primary key when several match) |
| `HasMany(...)` | every related row, by primary key |
| `BelongsTo(...)` | the owner |

`where: (w) => w.where('status', 'pago')` filters the candidate rows of a
relation before the choice. In batches, "one of many" uses
`row_number() over (partition by fk order by column, pk desc)`, which needs
PostgreSQL, MySQL 8 or MariaDB 10.2. The keys are sent in chunks of 5000.

Rules:

- `fill(toMap())` must leave the model unchanged. Fields need an initial
  value or a nullable type: a column that was not selected keeps it, is not
  written by `save()` (only changed columns are) and `hasColumn(column)` is
  false.
- On insert, null fields are left out, so the columns get their defaults.
- `getOriginal(column)` reads the database value last read or saved, also
  for columns the model does not map (`selectRaw('count(*) as total')`).
- `getLoaded` on a relation that was not loaded throws;
  `isLoaded(model)` checks it.
- A model keeps the connection it was read with. Inside `transaction` use
  the `ctx` (`User.query(ctx)`, `make(ctx, ...)`), or `save(using: ctx)`.
- Casts: `Casts.boolean` (MySQL `tinyint`), `integer`, `decimal`
  (PostgreSQL `numeric` comes as text), `dateTime`, `json`,
  `enumByName(values)`; implement `AttributeCast` for others. `fill()`
  receives the converted values and `toMap()`'s are converted back.
- `toJson()` writes `DateTime` as ISO-8601 and enums by name, so
  `jsonEncode(model)` works.
- `ModelQuery` also has `find`, `findMany`, `firstOrFail`, `paginate`
  (`ModelPage.toMap()`), `count`, `exists`, `lazyById`, bulk `update`/`delete`,
  and `configure((q) => q.join(...))` for the underlying `QueryBuilder2`.

Many-to-many, scopes, soft deletes and observers:

```dart
class Member extends Model<Member> {
  static final definition = ModelDefinition<Member>(
    table: 'members',
    create: Member.new,
    softDeletes: true,                                   // deleted_at
    globalScopes: {'tenant': (w) => w.where('members.tenant', tenantAtual)},
  );
  @override
  ModelDefinition<Member> get modelDefinition => definition;

  static final roles = BelongsToMany<Member, Role>('roles', () => Role.definition,
      pivotTable: 'member_role', foreignPivotKey: 'member_id',
      relatedPivotKey: 'role_id', pivotColumns: ['level']);

  static void onlyActive(ModelQuery<Member> q) => q.where('ativo', true); // local scope

  // fields, toMap() and fill() as above
}

await Member.roles.attach(member, [10, 20], pivot: {'level': 5});
await Member.roles.sync(member, [20, 30]);   // (attached: [30], detached: [10])
final roles = await Member.roles.fetch(member);
Member.roles.pivot(roles.first)['level'];

await Member.definition.query(db).apply(Member.onlyActive).get();
await Member.definition.query(db).withoutGlobalScope('tenant').count();

await member.delete();        // sets deleted_at; trashed == true
await member.restore();
await member.forceDelete();   // removes the row
await Member.definition.query(db).onlyTrashed().get();

Member.definition.observe(AuditObserver());  // extends ModelObserver<Member>
```

- **Global scopes and soft deletes** apply to every query of the model,
  relations and batch loading included. A query's own conditions are grouped
  when they contain an `or`, so `a or b` cannot bypass the scopes.
- **Observers** receive `saving`, `creating`/`created` or
  `updating`/`updated` (only when something changed), `saved`,
  `deleting`/`deleted` and `restoring`/`restored`. An exception in a
  `...ing` callback stops the operation; a callback may also change
  fields before they are written. Bulk `update`/`delete` on a query do
  not notify observers.
- **`sync`** is not atomic by itself; pass `using: ctx` inside a transaction.

### Data Mapper (Repository, no code generation)

```dart
class User {
  int? id;
  String name;
  User({this.id, required this.name});
}

final userMapper = EntityMapper<User>(
  table: 'users',
  fromRow: (r) => User(id: (r['id'] as num?)?.toInt(), name: r['name'] as String),
  toRow: (u) => {'name': u.name},   // omit the PK; the DB assigns it
  getId: (u) => u.id,
);

final repo = Repository<User>(await manager.connection(), userMapper);

final id = await repo.save(User(name: 'Ada'));  // insert -> returns id
final ada = await repo.findOrFail(id);
ada.name = 'Ada Lovelace';
await repo.save(ada);                            // update (has id)

final all = await repo.all();
final some = await repo.findBy('name', 'Ada Lovelace');
await for (final u in repo.cursor()) { /* streamed hydration */ }
await repo.delete(ada);
```

## Schema objects and platforms (Doctrine DBAL port)

`Schema`, `Table`, `Column`, `Index`, `ForeignKeyConstraint` and `Sequence`
describe a database schema in memory; a platform (`PostgreSQLPlatform`,
`MySQLPlatform`, `MariaDBPlatform`) turns them into SQL.

```dart
final schema = Schema();
final cliente = schema.createTable('cliente');
cliente.addColumn('id', 'integer', options: {'autoIncrement': true});
cliente.addColumn('nome', 'string', options: {'length': 80});
cliente.setPrimaryKey(['id']);

final pedido = schema.createTable('vendas.pedido');      // creates "vendas"
pedido.addColumn('id', 'bigInteger', options: {'autoIncrement': true});
pedido.addColumn('cliente_id', 'integer');
pedido.setPrimaryKey(['id']);
pedido.addForeignKey(
    localColumns: ['cliente_id'],
    foreignTableName: 'cliente',
    foreignColumns: ['id'],
    options: {'onDelete': 'cascade', 'deferrable': true, 'deferred': true});

final platform = db.getDatabasePlatform();               // from the driver
for (final sql in schema.toSql(platform)) {
  await db.execute(sql);
}

// Compare what the database has with what the application expects.
final actual = await db.getDoctrineSchemaManager().introspectSchema();
final diff = Comparator().compareSchemas(actual, expected);
for (final sql in platform.getAlterSchemaSQL(diff)) {
  await db.execute(sql);
}
```

- `toSql` creates namespaces, sequences (not the ones behind serial
  columns), tables, and then the foreign keys, so tables may reference each
  other in any order. `toDropSql` drops the foreign keys first.
- PostgreSQL also writes `COMMENT ON` statements, `CREATE UNLOGGED TABLE`
  (table option `unlogged`) and foreign keys with `MATCH` and
  `DEFERRABLE [INITIALLY DEFERRED]`. MySQL writes column comments inline
  and the table options `engine`, `charset`, `collation` and `comment`.
- Column types come from the same schema grammars as migrations.
- The platforms also give type declarations, portable expressions (dates,
  `LOCATE`, `CONCAT`, ...), reserved keywords, isolation levels and limits.

## Migrations, seeders and CLI

Migrations are Dart classes registered in a map (no code generation). Each
`up`/`down` runs in a transaction together with its row in the migration
table, so a failure rolls both back; `withinTransaction = false` opts out
(for `CREATE INDEX CONCURRENTLY`, `VACUUM`).

```dart
class TipoNormaNomeUnico extends Migration {
  @override
  Future<void> up() async {
    await (await schema).table('normas.tipo_norma', (Blueprint t) {
      t.timestamp('alterado_em');   // timestamp without time zone (microseconds)
      t.nullable();
      t.comment('Última alteração do nome.'); // COMMENT ON COLUMN on PostgreSQL
    });
    // Anything the Blueprint does not cover: one statement per call.
    await statement('create unique index tipo_norma_nome_uq on normas.tipo_norma '
        '(lower(public.immutable_unaccent(trim(nom_tipo_norma))))');
  }

  @override
  Future<void> down() async => statement('drop index normas.tipo_norma_nome_uq');
}

/// The schema of the version the databases already have (empty up/down).
class Baseline extends Migration {
  @override
  Future<void> up() async {}
  @override
  Future<void> down() async {}
}

final dbm = manager.getDatabaseManager();
final migrator = Migrator(DatabaseMigrationRepository(dbm, 'migrations'), dbm, {
  '2026_10_21_000000_baseline_6_4_0': () => Baseline(),
  '2026_10_21_000001_tipo_norma_nome_unico': () => TipoNormaNomeUnico(),
}, databaseManager: dbm);

// An existing database already has the baseline: record it without running it.
await migrator.markAsRan(['2026_10_21_000000_baseline_6_4_0']);

// Run what is pending (creates the migration table). Works in an AOT build:
// it reads the registry, not the source files.
await migrator.runPending();

await SeederRunner(dbm).call(WidgetsSeeder()); // class WidgetsSeeder extends Seeder
```

- On PostgreSQL each migration first takes an advisory lock and checks the
  migration table again (`migrator.isolated`, on by default), so two
  instances deploying at the same time apply each migration once.
- Time columns have no precision by default (`timestamp without time zone`,
  microseconds), so the fractions of a `DateTime` are kept. `precision: 3`
  sets one column; `SchemaBuilder.defaultTimePrecision = 0` restores
  Laravel's `timestamp(0)`, which PostgreSQL rounds to the nearest second.
- `rollback()`, `reset()`, `pending()` and `run(paths)` (Laravel's form,
  reading `YYYY_MM_DD_HHMMSS_name.dart` files from a directory) are also
  available.

```bash
dart run eloquent:eloquent make:migration create_widgets_table --create=widgets
dart run eloquent:eloquent make:seeder WidgetsSeeder
```

## schema:diff CLI

```bash
# print the ALTER statements to make table_a match table_b
dart run eloquent:eloquent schema:diff table_a table_b \
  --database=mydb --username=dart --password=dart

# ...and execute them
dart run eloquent:eloquent schema:diff table_a table_b \
  --database=mydb --username=dart --password=dart --apply
```

## PostgreSQL JSON / full-text / distinct-on

```dart
// JSONB containment (value is JSON-encoded and bound)
await db.table('docs').whereJsonContains('tags', ['urgent']).get();
await db.table('docs').whereJsonContains('meta', {'name': 'ada'}).get();

// JSON array length
await db.table('docs').whereJsonLength('tags', '>', 1).get();

// JSON column access via the -> selector  ("meta"->>'name')
await db.table('docs').where('meta->name', '=', 'ada').get();

// Array operators (text[] / int[] columns): @>  <@  &&
await db.table('docs').whereArrayContains('tags', ['urgent']).get();    // @>
await db.table('docs').whereArrayContainedBy('tags', ['a', 'b']).get(); // <@
await db.table('docs').whereArrayOverlaps('tags', ['x', 'y']).get();    // &&

// Full-text search (mode: plain | phrase | websearch; language default english)
await db.table('docs').whereFullText('body', 'quick fox').get();
await db.table('docs')
    .whereFullText(['title', 'body'], 'cats OR dogs',
        {'language': 'simple', 'mode': 'websearch'})
    .get();

// SELECT DISTINCT ON (one row per user, newest first)
await db.table('events')
    .distinctOn(['user_id'])
    .orderBy('user_id')
    .orderBy('created_at', 'desc')
    .get();
```

## PostgreSQL LISTEN / NOTIFY

Works on every PostgreSQL adapter (`postgres`, `postgres_v3`, `dargres`,
`dpgsql`). `notify` uses `pg_notify`, so inside a transaction the
notification is delivered only on COMMIT (and dropped on rollback).

```dart
// Producer: enqueue and wake the workers in the same transaction.
await db.transaction((ctx) async {
  final id = await ctx.table('fila').insertGetId({'situacao': 'pendente'});
  await ctx.notify('fila_pendente', '$id');
});

// Worker: process on notification; poll as a fallback.
final sub = db.notifications('fila_pendente').listen((n) => processarFila());
await db.notificationListener.ready(); // LISTEN is active
await processarFila(); // what was queued before LISTEN

// Notifications sent while the connection was down are lost: re-read.
db.notificationListener.onReconnect.listen((_) => processarFila());
db.notificationListener.onError.listen((e) => log.warning('LISTEN: $e'));

await sub.cancel(); // UNLISTEN (the connection closes with the last channel)
```

All channels share one dedicated connection, outside the pool, that
reconnects with exponential backoff, runs `LISTEN` again and checks itself
with a `SELECT 1` heartbeat (30 s). `db.disconnect()` closes it. Channel names
are case-sensitive, as in `pg_notify`; payloads must be under 8000 bytes. For
other settings create a listener yourself:

```dart
final listener = PostgresNotificationListener(
  db.getPdo().pdoInstance.openNotificationConnection,
  heartbeat: Duration(seconds: 10),
  maxReconnectDelay: Duration(seconds: 15),
);
```

## Direct driver access (COPY, LISTEN/NOTIFY, raw connection)

`db.driver()` (or `queryBuilder.driver()`) returns a `DriverAccess?` — a typed
escape hatch for driver features the query builder cannot express. It is `null`
when the active driver does not support it (only `dpgsql` today).

```dart
final drv = db.table('temp_location').driver();
if (drv != null && drv.supportsCopy) {
  // Bulk load via COPY ... FROM STDIN (much faster than many inserts)
  await drv.copyInRows(
    'temp_location',
    ['id', 'city'],
    [ [1, 'Rio'], [2, 'Niteroi'] ],
  );

  // COPY ... TO STDOUT
  final csv = await drv.copyOutText('COPY (SELECT * FROM temp_location) TO STDOUT');
}

// LISTEN / NOTIFY
final sub = drv!.listen('canal').listen((n) => print(n.payload));
await drv.notify('canal', 'ping');

// Full escape hatch: the native DpgsqlConnection (pipelining, batch, etc.)
await drv.withRawConnection((conn) async {
  // conn is a DpgsqlConnection
});
```
## using connection pool (works for mysql and postgresql)

```dart
    var manager = new Manager();
    manager.addConnection({
      'driver': 'pgsql',
      'driver_implementation': 'postgres_v3',
      'host': 'localhost',
      'port': '5432',
      'database': 'database_name',
      'username': 'user_name',
      'password': 'pass',
      'charset': 'utf8',
      'prefix': '',
      'schema': 'public,other', 
      'pool': true,
      'poolsize': 8,     
    });
   
    final db = await manager.connection();

    final query = db.table('temp_location');
    
    final res = await query
        .select(['temp_location.id', 'city', 'street'])
        .where('temp_location.id', '=', 1)
        .join('people', 'people.id', '=', 'temp_location.id_people', 'inner')
        .limit(1)
        .offset(0)
        .get();


```


## connect and disconnect in loop

```dart
    var manager = new Manager();
    manager.addConnection({
      'driver': 'pgsql',
      'host': 'localhost',
      'port': '5432',
      'database': 'database_name',
      'username': 'user_name',
      'password': 'pass',
      'charset': 'utf8',
      'prefix': '',
      'schema': 'public,other',          
    });

    while (true){
      //connect
      final db = await manager.connection();
      final res = await db.table('temp_location')
          .select(['temp_location.id', 'city', 'street'])
          .where('temp_location.id', '=', 1)
          .join('people', 'people.id', '=', 'temp_location.id_people', 'inner')
          .limit(1)
          .offset(0)
          .get();
      //disconnect    
      await manager.getDatabaseManager().purge();
    }    

```

## using different drivers implementation for postgresql

```dart
    var manager = new Manager();
    manager.addConnection({
      'driver': 'pgsql',
      'driver_implementation': 'postgres_v3', // postgres | postgres_v3 | dargres | dpgsql
      'host': 'localhost',
      'port': '5432',
      'database': 'database_name',
      'username': 'user_name',
      'password': 'pass',
      'charset': 'utf8',
      'prefix': '',
      'schema': 'public,other',          
    });

    
      //connect
      final db = await manager.connection();
      final res = await db.table('temp_location')
          .select(['temp_location.id', 'city', 'street'])
          .where('temp_location.id', '=', 1)
          .join('people', 'people.id', '=', 'temp_location.id_people', 'inner')
          .limit(1)
          .offset(0)
          .get();
      //disconnect    
      await manager.getDatabaseManager().purge();
       

```

## PostgreSQL value types (`pg_types`) and driver options

With `'pg_types': 'uniform'` (the default) the four PostgreSQL adapters
return the same Dart types: `numeric` and `money` as exact `String`
(`'150.50'`), `time`, `interval`, `inet`, ranges and geometric types as the
server's text, arrays as `List<T?>`, `json`/`jsonb` decoded. `'driver'`
keeps each driver's own types (`PgInterval`, `Interval`, `DpgsqlRange`...).

`driver_options` passes settings to the driver as they are; an unknown key
throws an `ArgumentError` with the list of known keys:

```dart
manager.addConnection({
  'driver': 'pgsql',
  'driver_implementation': 'dargres',
  // ...
  'pg_types': 'uniform', // 'uniform' (default) | 'driver'
  'driver_options': {'statementCacheCapacity': 256, 'commandTimeout': 60},
});
```

See the release notes for the full type table and the keys of each adapter.

## DateTime bindings (`datetime_bindings`)

By default (`'datetime_bindings': 'string'`) `Connection.prepareBindings()`
formats every `DateTime` binding with the grammar date format
(`yyyy-MM-dd HH:mm:ss`) before the driver receives it, as Laravel does. The
column type then decides how the text is read. Two things are lost: the
microseconds, and the time zone of a UTC `DateTime`. In a `timestamptz`
column, `DateTime.utc(2024, 3, 10, 12, 34)` is stored as `12:34` in the
session zone (`15:34Z` with `America/Sao_Paulo`). This also happens when you
write back a `timestamptz` value that was read as UTC
(`forceDecodeTimestamptzAsUTC`).

With `'datetime_bindings': 'native'` the `DateTime` goes to the driver
unchanged:

```dart
manager.addConnection({
  'driver': 'pgsql',
  'timezone': 'America/Sao_Paulo',
  'datetime_bindings': 'native', // 'string' (default) | 'native'
  // ...
});
```

| Column | `string` (default) | `native` |
|---|---|---|
| `timestamp` | wall-clock fields, no microseconds | wall-clock fields with microseconds |
| `timestamptz` | the fields read in the session zone, so a UTC `DateTime` shifts | the right instant for local and UTC values |
| `date` | the date | the date |
| MySQL `datetime(6)` | no microseconds | microseconds kept |

The table was checked on postgres, postgres_v3, dargres and dpgsql with an
`America/Sao_Paulo` session. For dpgsql the adapter sends untyped ISO text with
offset and microseconds (`2024-03-10 12:34:56.789123-03:00`): dpgsql would
type the value as `timestamp` with its UTC fields, which shifts both columns.
With `native`, a value read back (for example a `timestamptz` decoded as UTC)
can be written or compared again without moving.

The `timezone` setting configures the PostgreSQL session time zone. The decode
flags `forceDecodeTimestampAsUTC`, `forceDecodeTimestamptzAsUTC` and
`forceDecodeDateAsUTC` control how values that are read come back as Dart
objects.

## mysql example

```dart
import 'dart:io';
import 'package:eloquent/eloquent.dart';

void main(List<String> args) async {
  final manager = Manager();
  manager.addConnection({
    'driver': 'mysql',
    'host': 'localhost',
    'port': '3306',
    'database': 'banco_teste',
    'username': 'root',
    'password': 'pass',
    'sslmode': 'require',
    // 'pool': true,
    // 'poolsize': 2,
  });

  manager.setAsGlobal();

  final db = await manager.connection();

  await db.execute('DROP TABLE IF EXISTS clients');
  await db.execute(''' CREATE TABLE IF NOT EXISTS clients (
    id int NOT NULL AUTO_INCREMENT,
    name varchar(255) NOT NULL,      
    PRIMARY KEY (id)
); ''');

  await db.execute('DROP TABLE IF EXISTS contacts');
  await db.execute(''' CREATE TABLE IF NOT EXISTS contacts (
    id_client int NOT NULL ,
    tel varchar(255) NOT NULL  
); ''');

  await db.table('clients').insert({'name': 'Isaque'});
  await db.table('clients').insert({'name': 'John Doe'});
  await db.table('clients').insert({'name': 'Jane Doe'});

  await db
      .table('clients')
      .where('id', '=', 1)
      .update({'name': 'Isaque update'});

  // await db.table('clients').where('id', '=', 2).delete();

  await db.table('contacts').insert({'id_client': 1, 'tel': '27772339'});
  await db.table('contacts').insert({'id_client': 2, 'tel': '99705498'});

  var res = await db
      .table('clients')
      .selectRaw('id,name,tel')
      .join('contacts', 'contacts.id_client', '=', 'clients.id')
      .get();

  print('res: $res');
  //res: [{id: 1, name: Isaque update, tel: 27772339}, {id: 2, name: John Doe, tel: 99705498}]
  await db.disconnect();

  exit(0);
}

```

## example of all settings

```dart
 final manager = Manager();
  manager.addConnection({
    'driver': 'pgsql',
    'driver_implementation': 'postgres_v3', // postgres | postgres_v3 | dargres | dpgsql
    // 'uniform' (default): the same Dart types on every PostgreSQL adapter
    'pg_types': 'uniform',
    // 'string' (default) | 'native': how DateTime bindings reach the driver
    'datetime_bindings': 'string',
    // settings passed to the driver as they are (keys of each driver)
    // 'driver_options': {'queryTimeoutInSeconds': 60},
    // set connection time zone UTC = default
    'timezone': 'America/Sao_Paulo',   
    // If true, decodes the timestamp with timezone (timestamptz) as UTC = default
    // If false, decodes the timestamp with timezone using the timezone defined in the connection.
    'forceDecodeTimestamptzAsUTC': false,
    // If true, decodes the timestamp without timezone (timestamp) as UTC.
    // If false, decodes the timestamp without timezone as local datetime.
    'forceDecodeTimestampAsUTC': false,
    // If true, decodes the date as UTC.
    // If false, decodes the date as local datetime.
    'forceDecodeDateAsUTC': false,
    // enable connection pool
    'pool': true,
    // Connection pool maximum connection count
    'poolsize': 2,
    'host': 'localhost',
    'port': '5435',
    'database': 'siamweb',
    'username': 'dart',
    'password': 'dart',
    // 
    'charset': 'win1252',
    'prefix': '',
    'schema': ['public'],
    // require | disable
    //'sslmode' : 'require',
  });
```
