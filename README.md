# eloquent
[![CI](https://github.com/insinfo/eloquent_dart/actions/workflows/dart.yml/badge.svg)](https://github.com/insinfo/eloquent_dart/actions/workflows/dart.yml)
[![Pub Package](https://img.shields.io/pub/v/eloquent.svg)](https://pub.dev/packages/eloquent)  

#### Support My Work
[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/isaqueneves)

I’m on @buymeacoffee. If you like my work, you can buy me a ☕ and share your thoughts 🎉 [Buy me a coffee](https://www.buymeacoffee.com/isaqueneves)


eloquent 5.2 query builder port from PHP Laravel to dart

https://laravel.com/docs/5.2/queries

for now it only works with PostgreSQL and MySQL


## Creating a connection executing a simple select
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
final id = await db.transaction((ctx) async {   // id is an int
  return await ctx.table('pedidos').insertGetId({'cliente': 1});
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

> **Driver note:** with `postgres` (postgres_fork) and `postgres_v3`, an
> *SQL error* (for example a duplicate key) inside any part of a transaction
> makes the driver roll back the whole transaction, so a savepoint only
> isolates Dart exceptions there. `dargres`, `dpgsql` and MySQL recover with
> `ROLLBACK TO SAVEPOINT` and the outer transaction continues.

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

## Streaming large result sets (server-side cursor)

`cursor()` streams rows one at a time using the driver's incremental reader,
so memory stays roughly constant even for millions of rows (only the `dpgsql`
driver implementation supports it today; others throw `UnsupportedError`).

```dart
// driver_implementation: 'dpgsql'
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

- **Active Record** (`User extends Model`): the model has its attributes,
  `save()`/`delete()` and relations with eager loading.
- **Data Mapper** (`Repository<T>` + `EntityMapper<T>`, below): plain
  classes and a repository that reads and writes them.

### Active Record

```dart
class User extends Model {
  User(super.state);

  static final definition = ModelDefinition<User>(
    table: 'users',
    create: User.new,                 // the constructor replaces reflection
    timestamps: true,                 // created_at / updated_at
    casts: {'ativo': Casts.boolean},
  );

  // Relations are declared once; the related definition is a function so
  // models can refer to each other.
  static final latestOrder = HasOne<User, Order>('latestOrder',
      () => Order.definition, foreignKey: 'user_id').latestOfMany();
  static final largestOrder = HasOne<User, Order>('largestOrder',
      () => Order.definition, foreignKey: 'user_id')
      .ofMany('price', AggregateFunction.maximum);
  static final orders = HasMany<User, Order>('orders',
      () => Order.definition, foreignKey: 'user_id');

  int get id => readAttribute<int>('id');
  String get name => readAttribute<String>('name');
  set name(String value) => writeAttribute('name', value);
}

class Order extends Model {
  Order(super.state);
  static final definition = ModelDefinition<Order>(
      table: 'orders', create: Order.new, casts: {'price': Casts.decimal});
  static final user = BelongsTo<Order, User>('user', () => User.definition,
      foreignKey: 'user_id');
  double? get price => readAttribute<double?>('price');
}

final user = await User.definition.query(db).findOrFail(10);
user.name = 'Isaque';
await user.save();                       // update ... set name = ? (only what changed)

final novo = User.definition.make(db, {'name': 'Ana'});
await novo.save();                       // insert; id and defaults read back

final latest = await User.latestOrder.fetch(user);   // one user

final users = await User.definition.query(db)        // many users:
    .where('ativo', true)                            // QueryBuilder2 where API
    .withRelation(User.latestOrder)                  // one query per relation
    .withRelation(User.largestOrder)
    .withRelation(User.orders)
    .get();
final Order? o = User.largestOrder.getLoaded(users.first);
return users.first.toMap();              // attributes + loaded relations
```

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

- A column that was not selected throws when read; it is not `null`.
  `save()` writes only the changed columns, so a model read with
  `select([...])` keeps the others.
- `getLoaded` on a relation that was not loaded throws;
  `isLoaded(model)` checks it.
- A model keeps the connection it was read with. Inside `transaction` use
  the `ctx` (`User.definition.query(ctx)`, `make(ctx, ...)`), or
  `save(using: ctx)`.
- Casts: `Casts.boolean` (MySQL `tinyint`), `integer`, `decimal`
  (PostgreSQL `numeric` comes as text), `dateTime`, `json`,
  `enumByName(values)`; implement `AttributeCast` for others.
- `ModelQuery` also has `find`, `findMany`, `firstOrFail`, `paginate`
  (`ModelPage.toMap()`), `count`, `exists`, `lazyById`, bulk `update`/`delete`,
  and `configure((q) => q.join(...))` for the underlying `QueryBuilder2`.

Many-to-many, scopes, soft deletes and observers:

```dart
class Member extends Model {
  Member(super.state);
  static final definition = ModelDefinition<Member>(
    table: 'members',
    create: Member.new,
    softDeletes: true,                                   // deleted_at
    globalScopes: {'tenant': (w) => w.where('members.tenant', tenantAtual)},
  );
  static final roles = BelongsToMany<Member, Role>('roles', () => Role.definition,
      pivotTable: 'member_role', foreignPivotKey: 'member_id',
      relatedPivotKey: 'role_id', pivotColumns: ['level']);

  static void ativos(ModelQuery<Member> q) => q.where('ativo', true); // local scope
}

await Member.roles.attach(member, [10, 20], pivot: {'level': 5});
await Member.roles.sync(member, [20, 30]);   // (attached: [30], detached: [10])
final roles = await Member.roles.fetch(member);
Member.roles.pivot(roles.first)['level'];

await Member.definition.query(db).apply(Member.ativos).get();
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
  attributes before they are written. Bulk `update`/`delete` on a query do
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
      final res = await query
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
      'driver_implementation': 'postgres_v3', // postgres | dargres | postgres_v3
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
      final res = await query
          .select(['temp_location.id', 'city', 'street'])
          .where('temp_location.id', '=', 1)
          .join('people', 'people.id', '=', 'temp_location.id_people', 'inner')
          .limit(1)
          .offset(0)
          .get();
      //disconnect    
      await manager.getDatabaseManager().purge();
       

```

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

  await db.execute('DROP TABLE clients');
  await db.execute(''' CREATE TABLE IF NOT EXISTS clients (
    id int NOT NULL AUTO_INCREMENT,
    name varchar(255) NOT NULL,      
    PRIMARY KEY (id)
); ''');

  await db.execute('DROP TABLE contacts');
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
    'driver_implementation': 'postgres_v3', // postgres | dargres | postgres_v3
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
