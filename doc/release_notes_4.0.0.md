# eloquent 4.0.0 — detailed release notes

Summary in [CHANGELOG.md](../CHANGELOG.md#400). The roadmap that produced most
of this release is in [PERFORMANCE_REWRITE_PLAN.md](PERFORMANCE_REWRITE_PLAN.md).

- [Breaking changes and migration](#breaking-changes-and-migration)
- [Transactions (issue #6)](#transactions-issue-6)
- [Row locks](#row-locks)
- [QueryBuilder2](#querybuilder2)
- [LISTEN / NOTIFY](#listen--notify)
- [DateTime bindings](#datetime-bindings)
- [Query builder](#query-builder)
- [Driver access and streaming](#driver-access-and-streaming)
- [dargres adapter](#dargres-adapter)
- [Migrations, seeders and CLI](#migrations-seeders-and-cli)
- [Doctrine schema port](#doctrine-schema-port)
- [Schema introspection and diff → ALTER](#schema-introspection-and-diff--alter)
- [Active Record](#active-record)
- [Lightweight ORM](#lightweight-orm)
- [Fixes](#fixes)
- [Query builder and driver fixes (4.0 review)](#query-builder-and-driver-fixes-40-review)
- [Ported from Laravel 12](#ported-from-laravel-12)
- [Performance](#performance)
- [Tests, CI and tooling](#tests-ci-and-tooling)

## Breaking changes and migration

### PostgreSQL value types: the same on every adapter (`pg_types`)

The four PostgreSQL adapters returned different Dart types for the same
column: `time` was `PgTime` on postgres, `Time` on postgres_v3 and `String`
on dargres and dpgsql; `numeric` was a `double` on dpgsql; `interval` threw
on postgres and was `Interval`/`String`/`DpgsqlInterval` elsewhere; an `enum`
was bytes on dpgsql. A model read with one driver could break with another.
With `pg_types: 'uniform'` (the default) every adapter returns:

| PostgreSQL | Dart |
|---|---|
| `int2`, `int4`, `int8`, `oid` | `int` |
| `float4`, `float8` | `double` (float4 widened: `1.100000023841858`) |
| `numeric` | `String`, exact (`'150.50'`) |
| `bool` | `bool` |
| `text`, `varchar`, `char`, `name`, `xml`, `uuid`, enums, domains over text | `String` |
| `bytea` | `Uint8List` |
| `json`, `jsonb` | `Map` / `List` / scalar |
| `date`, `timestamp`, `timestamptz` | `DateTime` (UTC, see `forceDecode*AsUTC`) |
| `time`, `timetz`, `interval`, `inet`, `cidr`, `macaddr`, `point`, `line`, `lseg`, `box`, `path`, `polygon`, `circle`, `bit`, `varbit`, `tsvector`, ranges | `String`: the server's text (`'10:20:30.5'`, `'1 day 02:03:04'`, `'10.0.0.1'`, `'(1,2)'`, `'[1,5)'`) |
| `money` | `String`: the decimal amount (`'12.34'`), not the lc_monetary text |
| arrays | `List<T?>` of the element values (`List<int?>`, `List<String?>`...) |
| arrays of user-defined types (`enum[]`) | `String`: the array literal (`'{ok,sad}'`) |

Exceptions:

- `regclass`, `regtype` and the other reg* types are the oid (`int`) on
  postgres and postgres_v3 (the binary form carries only the oid) and the
  name on dargres and dpgsql. Cast them (`::text` or `::oid`).
- A `tstzrange` bound is printed in UTC (`+00`) on postgres and postgres_v3;
  the server prints it in the session time zone.
- `money` assumes 2 fraction digits (lc_monetary's default).

Migration: code that read `PgTime`, `PgInterval`, `PgInet`, `PgPoint`
(postgres), `Time`, `Interval`, `IntRange`, `Point`... (postgres_v3) or
`DpgsqlInterval`, `DpgsqlRange`... (dpgsql) gets a `String`. Parse it, or
set `pg_types: 'driver'` to keep each driver's types:

```dart
manager.addConnection({
  'driver': 'pgsql',
  // ...
  'pg_types': 'driver', // PgInterval, DpgsqlRange, Interval... as before
});
```

`test/pg_type_parity_integration_test.dart` reads about 55 types cold, warm,
in one row and inside a transaction on the four adapters and requires the
same type and value: a driver that changes a decoder fails it.

The drivers produce these types while they decode; the adapters do not walk
the rows afterwards (a first version did, and cost about 12% on a 100-row
result): postgres_fork with `DecodingSettings(interval: text, extendedTypes:
text, nullableArrays: true)`, dpgsql with `Decode Extended Types As Text` and
`Decode Numeric As String`, dargres by its text decoding, postgres_v3 with a
`TypeRegistry` of codecs (its arrays get their list type in the pass the
adapter already made). Measured in the SALI (same configuration as
production, driver postgres, median of 3 rounds of 3000 queries), 4.0 against
3.4.3: `select 1` 1.01x, 100 rows 0.98x, query builder with a join 0.99x,
compiling a query 0.87x, insert + update in a transaction 0.91x.

### `driver_options`

Settings passed to the driver as they are. The keys are each driver's own
names; an unknown key throws an `ArgumentError` listing the known ones.
Durations take a `Duration` or a number of seconds.

```dart
manager.addConnection({
  'driver': 'pgsql',
  'driver_implementation': 'dargres',
  // ...
  'driver_options': {'statementCacheCapacity': 256, 'commandTimeout': 60},
});
```

| Adapter | Keys |
|---|---|
| postgres | `timeoutInSeconds`, `queryTimeoutInSeconds`, `useSSL`, `allowClearTextPassword`, `isUnixSocket`, `cancelQueryOnTimeout`; with pool: `connectTimeout`, `queryTimeout`, `idleTestThreshold`, `maxConnectionAge`, `maxSessionUse`, `maxErrorCount`, `maxQueryCount` |
| postgres_v3 | `connectTimeout`, `queryTimeout`, `queryMode` (`'extended'`/`'simple'`), `ignoreSuperfluousParameters`; with pool: `maxConnectionAge`, `maxSessionUse`, `maxQueryCount` |
| dargres | `connectionTimeout`, `commandTimeout`, `cancelGracePeriod`, `tcpKeepalive`, `statementCacheCapacity`, `queueConcurrentCalls`, `numericAsString`, `sourceAddress` |
| dpgsql | connection-string keywords (`'Max Auto Prepare'`, `'Statement Timeout'`, `'Decode Json As String'`...) |
| mysql | `autoPreparedStatementCacheCapacity`, `allowPublicKeyRetrieval`, `serverPublicKey`, `queueConcurrentCalls`; with pool instead of `queueConcurrentCalls`: `timeoutMs`, `idleTestThreshold`, `maxConnectionAge`, `maxSessionUse`, `maxErrorCount` |

The per-query timeout options (`queryTimeoutInSeconds`/`queryTimeout`,
dargres `commandTimeout`) are also the adapter's default timeout for a query
called without one. Options the adapter sets to keep the types uniform
(`numericAsString`, `Decode Numeric As String`, `Decode Extended Types As
Text`) can be overridden; the types are then the driver's.

`PDOConfig.fromMap` reads the snake_case and camelCase spellings of
`application_name`, `poolsize`, `allowreconnect` and `is_unix_socket`;
`toMap()` wrote camelCase keys that `fromMap()` did not read.

### `ConnectionInterface` (transactions)

Custom implementations of `ConnectionInterface` (test fakes included) must now
implement:

```dart
Future<T> transaction<T>(Future<T> Function(Connection ctx) callback,
    [int? timeoutInSeconds]);
Future<T> transactionIfNeeded<T>(Future<T> Function(Connection ctx) callback,
    [int? timeoutInSeconds]);
bool get isInTransaction;
bool get supportsSavepoints;
```

- `Connection.transactions` is now a deprecated getter; use
  `transactionLevel()` / `isInTransaction`.
- `PostgresConnection` and `MySqlConnection` no longer override `transaction`;
  they override `newConnectionForPdo(PDOExecutionContext)`, the factory used
  for transaction contexts. Subclasses that overrode `transaction` to return
  their own `Connection` type should do the same.
- Existing `db.transaction((ctx) async {...})` code keeps working; casts such
  as `as int` on the result become unnecessary.
- `transaction()` now passes `timeoutInSeconds` to the driver. It was ignored
  before, so pools always used their 30 s default; code that passed a larger
  value (for example 90 or 120 s) now actually gets it.

### `InvalidArgumentException` → `ArgumentError`

- The public custom `InvalidArgumentException` was replaced with Dart's native
  `ArgumentError`, removed from the `eloquent.dart` exports, and
  `lib/src/exceptions/invalid_argument_exception.dart` was deleted.
- `QueryBuilder`, `DatabaseManager`, `ConnectionFactory` and `Container` throw
  `ArgumentError`, `ArgumentError.value` or `ArgumentError.notNull` for invalid
  arguments.
- Replace `catch (InvalidArgumentException)` with `catch (ArgumentError)`.
- Internal Doctrine/DBAL compatibility classes named `InvalidArgumentException`
  remain scoped to `lib/src/doctrine`; they are not the removed public
  exception.

### dargres

`DargresPDO` requires dargres 4.0.1 (new session options).

### dpgsql

`DpgsqlPDO` requires dpgsql 1.1.0: `execute()`/`unprepared()` set
`DpgsqlCommand.simpleQuery`, so a script runs through the simple query
protocol while the other queries keep the extended protocol (binary results,
auto-prepare). postgres_v3's `execute()` passes `QueryMode.simple` for the
same reason. A script that failed with 42601 on these two adapters now runs
as on postgres and dargres.

### Corrected behaviour that code may have relied on

| Before | Now | What to change |
|---|---|---|
| `where(col, '>', null)` (any operator but `=`, `<>`, `!=`) became `col is not null` | `ArgumentError` | Use `whereNull`/`whereNotNull`, or skip the filter when the value is null. |
| `where('status', 'ativo')` became `status is not null` | `status = 'ativo'` (Laravel's two-argument form) | Nothing; the call now does what it says. |
| `value(col)` returned the first row (`Map`) | The column value, or `null` | Drop `row[col]` after `value()`. |
| `count()` with `groupBy`/`having`/`union`/`distinct` returned the first group's count | The number of rows of the query (`CountMode.rows`, the default) | Pass `CountMode.laravel` to keep Laravel's semantics, or use `groupBy(...).get()` for the per-group counts. |
| `update()` returned `Future<dynamic>`; `ConnectionInterface.update` too | `Future<int>` | Custom `ConnectionInterface` implementations return `int`. |
| PostgreSQL `update`/`delete` with a left/right join silently acted as an inner join | `UnsupportedError` | Use a subquery (`whereIn`/`whereExists`). |
| PostgreSQL `update`/`delete` ignored `limit` | Limited through `ctid` | Nothing. |
| `recursionLimit()` was ignored | `UnsupportedError` on PostgreSQL and MySQL | Filter a depth column, or set `cte_max_recursion_depth` / `max_recursive_iterations`. |
| `whereIn(col, [])` produced `in ()` (SQL error) | `0 = 1` (`not in`: `1 = 1`) | Nothing. |
| `update(values, timeout)` / `delete(id, timeout)` defaulted to 300 s and ignored it | Default `null` (driver default, 30 s); a given timeout is applied | Pass a longer timeout where a statement needs it. |
| `t.timestamp('x')` (and `dateTime`, `time`, `timestamps()`, `softDeletes()`) created `timestamp(0)` | No precision: `timestamp without time zone` (microseconds on PostgreSQL) | Nothing for new columns; `SchemaBuilder.defaultTimePrecision = 0` keeps Laravel's `timestamp(0)`, which rounds 10:20:30.6 to 10:20:31. |
| `Blueprint.toSql` printed a warning and skipped a command that did not compile | Throws | Fix the command; the migration no longer passes without its DDL. |
| A unique violation threw the driver's exception (`PostgreSQLException`, `ServerException`, `PostgresqlException`, `PostgresException`, `MySQLServerException`) | `UniqueConstraintViolationException` (a `QueryException`; the driver's exception in `previous`, its text kept in `toString()`) | Catch `UniqueConstraintViolationException` instead of the driver type; code that looks for `23505` or the constraint name in `'$e'` keeps working. |

## Transactions (issue #6)

- `transaction<T>()` is generic: it returns the callback's value with its type.
- `transaction()` called on a transaction context nests through
  `SAVEPOINT eloquent_savepoint_<level>`: `RELEASE` on success,
  `ROLLBACK TO SAVEPOINT` plus rethrow on error. The outer transaction stays
  usable when the caller catches the error. It never opens a second physical
  transaction; contexts without savepoint support throw
  `UnsupportedNestedTransactionException`.
- `transactionIfNeeded<T>()` reuses the current transaction (no SAVEPOINT) or
  opens one.
- `isInTransaction` and `supportsSavepoints`; `transactionLevel()` reports the
  real depth: 0 outside, 1 in the transaction, 2+ in savepoints.
- The state lives in each `PDOExecutionContext`, never in globals, so
  concurrent requests do not interfere:
  - `PDOTransactionContext` — base of every driver's transaction context
    (level 1); SAVEPOINT commands are plain SQL on that transaction.
  - `NestedPDOTransaction` — wraps the enclosing context with the next level;
    it works for any driver without knowing its classes.
- Driver behaviour after an **SQL error** inside a savepoint (verified by
  `test/transaction_savepoint_integration_test.dart`):
  - `postgres`, `dargres`, `dpgsql`, MySQL: `ROLLBACK TO SAVEPOINT` recovers
    and the outer transaction continues. postgres_fork rolls back its whole
    transaction after an SQL error (`_onQueryError`) unless the error happens
    inside a savepoint it knows about, so its adapter opens nested
    transactions with the driver's `savepoint()`
    (`PDOExecutionContext.runInSavepoint`), also through the pool.
  - `postgres_v3`: the driver itself rolls back the whole transaction after
    any SQL error (postgres 3.x `runTx` `_transactionException`), so a
    savepoint only isolates Dart exceptions there.

See the README section "Transactions, nested transactions (SAVEPOINT) and
transactionIfNeeded" for examples.

## Row locks

- `QueryLock` and the builder methods `lockForUpdate({skipLocked, noWait, of})`,
  `sharedLock({skipLocked, noWait, of})`, `skipLocked()` and `noWait()`:

  | Call | PostgreSQL | MySQL 8 / MariaDB 10.6+ |
  |---|---|---|
  | `lockForUpdate()` | `for update` | `for update` |
  | `sharedLock()` | `for share` | `lock in share mode` |
  | `lockForUpdate(skipLocked: true)` / `skipLocked()` | `for update skip locked` | `for update skip locked` |
  | `lockForUpdate(noWait: true)` | `for update nowait` | `for update nowait` |
  | `lockForUpdate(of: ['jobs'])` | `for update of "jobs"` | ``for update of `jobs` `` |
  | `sharedLock(noWait: true)` | `for share nowait` | `for share nowait` |

- `skipLocked()`/`noWait()` without a lock imply `FOR UPDATE`; after
  `sharedLock()` they keep `FOR SHARE`. SKIP LOCKED and NOWAIT cannot be
  combined (`ArgumentError`).
- `lock()` accepts `bool`, `QueryLock` or a raw SQL string used verbatim (for
  example `'for no key update'`). Plain `lockForUpdate()`/`sharedLock()` output
  is unchanged.
- Replaces the workaround `query.lockProp = 'for update skip locked'`.
- Validated against PostgreSQL and MariaDB 10.11 with two concurrent
  transactions: the second skips the row locked by the first.

## QueryBuilder2

`db.table2('t')` (or `QueryBuilder2(connection, 't')`) is a second query
builder with a Dart 3 API. It is additive: `QueryBuilder` is unchanged.

Design rules:

- **Fixed meaning per argument.** `where(column, value, {operator})`: the
  value is always bound. `QueryBuilder.whereFlex('simbolo', '=')` read `=`
  as the operator; `where('simbolo', '=')` here is `"simbolo" = ?` with
  binding `'='`. Subqueries, callbacks and `QueryExpression` are rejected
  as values, with a hint to the right method.
- **Enums.** `ComparisonOperator` (`equalTo`, `notEqualTo`, `greaterThan`,
  `greaterThanOrEqualTo`, `lessThan`, `lessThanOrEqualTo`), `SortDirection`
  and `JoinType`, plus the descriptive methods `whereGreaterThan`, ... for
  literal queries. Dynamic operators use the enum.
- **One method per shape.** IN, NULL, BETWEEN (two required limits), LIKE,
  column vs. column, groups, EXISTS and IN subquery each have their own
  method.
- **Specified edge cases.** `null` with `=`/`<>` means `is [not] null`, and
  other operators with `null` throw. An empty IN is false and an empty
  NOT IN is true. `null` inside IN throws, because `x in (null)` never
  matches.
- **Typed callbacks.** `whereGroup` receives a `WhereBuilder` (only where
  methods), `joinOn` a `JoinBuilder`, `whenNotNull<T>` the non-null value.
- **Typed results.** `get()` returns `List<Map<String, dynamic>>`; also
  `first()`, `sole()`, `value<T>()`, `pluck<T>()`, `count()`, `exists()`,
  `sum/avg/min/max` (`num?`), `insertGetId<T>()`, `update/delete` (`int`)
  and `lazyById()` (`Stream`).
- **Structured conditions.** Conditions are sealed `Predicate` classes
  (`ComparisonPredicate`, `InPredicate`, `GroupPredicate`, ...), readable
  through `wheres`. Subqueries are copied when added, and `clone()` is
  independent.

Compilation: the predicates are written straight into a `QueryBuilder`
(`toQueryBuilder()`), bypassing the argument parsing of
`QueryBuilder.where`, and compiled by the existing grammars. Dialect
features (PostgreSQL `ilike`, update with joins, locks, `toRawSql`) work as
they do there, and a later compiler that works on the predicates directly
would not change the API.

`whereSqlOperator(column, op, value)` takes an operator as text and checks
it against `QueryGrammar.predicateOperators` (new). The PostgreSQL and MySQL
lists contain only operators that yield a boolean. Arithmetic is rejected,
and so are `?`/`?|`/`?&`, which collide with the `?` placeholder.

`having(column, value)` takes an identifier; aggregates go through
`havingRaw('sum(total) > ?', [1000])`, because PostgreSQL does not accept
select aliases in HAVING.

### Pagination, writes, unions and CTEs

| Method | Result |
|---|---|
| `paginate(page:, perPage:)` | `PageResult`: `items`, `total`, `lastPage`, `hasMorePages`, `from`, `to`, `toMap()` (Laravel's JSON keys). The count also works with group/distinct/union |
| `simplePaginate(page:, perPage:)` | `SimplePageResult` (no count; reads one extra row) |
| `insert(values, onConflict:)` | `int` rows inserted (0 when skipped) |
| `insertReturning(values, returning:, onConflict:)` | rows (PostgreSQL) |
| `insertMany(rows)` / `insertOrIgnore(rows)` | `int`; every row must have the same columns |
| `upsert(rows, uniqueBy:, update:)` | `update` lists the columns taken from the inserted row (default: all but `uniqueBy`) |
| `updateReturning(values, returning:)` / `deleteReturning(returning:)` | rows (PostgreSQL) |
| `union(q)` / `unionAll(q)` | order/limit/offset apply to the combined result; parts with their own window are wrapped |
| `withExpression(name, q, columns:, materialized:)` / `withRecursiveExpression` | CTE |

`OnConflict.doNothing({columns, constraint})` and
`OnConflict.doUpdate({columns, constraint, set, whereRaw})` replace the
`onConflict()/doUpdate()/doNothing()` chain. `doUpdate` without a conflict
target, or with both columns and a constraint, throws. On MySQL it compiles to
`on duplicate key update`; `doNothing` becomes a no-op update of a key column,
so only duplicate keys are skipped, unlike `insert ignore`.

The page is a required argument: `QueryBuilder.paginate` reads it from
global HTTP state (`PaginationUtils`), which a Dart server does not have.

Found while doing this (they also affected `QueryBuilder`):

- `union` + `orderByRaw(sql, bindings)` put the order bindings before the
  union parts' bindings while the SQL has them after. A `unionOrder` binding
  bucket now comes last, as in Laravel.
- The pagination count of a union kept the union's order and limit.
- `returning()` was documented for insert/update/delete/upsert but only
  `insert` read it. `QueryBuilder2.updateReturning`/`deleteReturning` use
  `compileReturning`.
- `onConflict()` on MySQL emitted PostgreSQL's `on conflict ...` (syntax
  error); `QueryMySqlGrammar.compileInsertWithClauses` now maps it.
- `QueryBuilder.insertMany` filled a column missing from a later row with
  `null` without a warning; `QueryBuilder2.insertMany` checks that every row
  has the same columns.

Tests: `test/query_builder2_test.dart` (SQL and bindings for PostgreSQL and
MySQL), `test/query_builder2_union_cte_test.dart`,
`test/query_builder2_integration_test.dart` and
`test/query_builder2_writes_integration_test.dart` (the four PostgreSQL
adapters and MariaDB).

## LISTEN / NOTIFY

Available on the four PostgreSQL adapters; MySQL throws `UnsupportedError`
(`db.supportsNotifications` is `false`).

| API | Notes |
|---|---|
| `db.notify(channel, [payload])` | `select 1 from pg_notify(?, ?)` on the write connection; on a transaction `ctx` it is delivered on COMMIT only |
| `db.notifications(channel)` | broadcast `Stream<DriverNotification>` (`channel`, `payload`, `processId`); `LISTEN` on the first subscriber, `UNLISTEN` after the last cancel |
| `db.notificationListener` | the shared `PostgresNotificationListener`: `ready()`, `onReconnect`, `onError`, `listening`, `isConnected`, `close()` |
| `PDOInterface.openNotificationConnection()` | a dedicated connection outside the pool; `supportsNotifications` |

`PostgresNotificationListener`:

- One dedicated connection for all channels, opened on the first
  subscription and closed when no channel is left; `db.disconnect()` (and
  `purge`) close it. Transaction connections share the listener of their
  connection.
- Lost connections are detected by the driver (postgres, postgres_v3,
  dargres, dpgsql 1.0.3) and by a `SELECT 1` heartbeat (30 s, configurable),
  which also catches a dropped network that leaves the socket open.
- Reconnects with exponential backoff (1 s doubling up to 30 s), runs
  `LISTEN` again for every subscribed channel and then emits `onReconnect`.
  Notifications sent while it was disconnected are lost, so `onReconnect`
  means "re-read the state" (poll the queue).
- `ready()` completes when every subscribed channel has an active `LISTEN`;
  subscribe, await `ready()`, then read what was queued before.
- Failures are reported as data on `onError`; channel streams never get
  errors.
- Channel names are quoted (`LISTEN "Fila"`), so they are case-sensitive and
  match `pg_notify('Fila', ...)`.

dpgsql 1.0.3 is required for the `dpgsql` adapter: older versions delivered a
notification only when the next command ran on the listening connection, and
decoded payloads with accents as Latin-1.

## DateTime bindings

New config key `datetime_bindings`: `'string'` (default, unchanged) or
`'native'`; anything else throws `ArgumentError`. It is also exposed as
`PDOConfig.dateTimeBindings` (`DateTimeBindings.string`/`.native`).

- `string` formats DateTime bindings with the wall-clock fields and no zone
  (`Grammar.formatDateTime`): `yyyy-MM-dd HH:mm:ss` (Laravel), plus the
  fraction on PostgreSQL when there is one (`12:34:56.789123`; 3.x dropped
  it). MySQL keeps whole seconds: `DATETIME` without fsp rounds a fraction,
  so sending one would move values to the next second. Without the zone,
  with an `America/Sao_Paulo` session, a UTC DateTime written to
  `timestamptz` is stored 3 hours off. The same shift happens when you write
  back a `timestamptz` value that was read as UTC.
- `native` passes the DateTime to the driver. On postgres, postgres_v3 and
  dargres, a `timestamp` column gets the fields and a `timestamptz` column
  gets the instant, with microseconds. On MySQL microseconds are kept;
  mysql_dart writes the fields and ignores `isUtc`.
- The dpgsql adapter converts DateTime parameters to untyped ISO text with
  offset and microseconds, so it has the same semantics as the other three
  adapters. Before, a direct PDO DateTime was formatted without microseconds
  and zone, and dpgsql's own inference typed it as `timestamp` from its UTC
  fields.

`test/datetime_bindings_integration_test.dart` covers both modes on the
four PostgreSQL adapters and MariaDB, including a value written back after
being read and `where` on `timestamp`/`timestamptz`.

## Query builder

### UPSERT / ON CONFLICT / RETURNING

- `upsert(values, uniqueBy, [update])` — PostgreSQL
  `INSERT ... ON CONFLICT (uniqueBy) DO UPDATE SET ...`; MySQL
  `INSERT ... ON DUPLICATE KEY UPDATE ...`. Without `update`, every
  non-`uniqueBy` column is updated from the would-be-inserted row.
- `insertOrIgnore(values)` — PostgreSQL `ON CONFLICT DO NOTHING` / MySQL
  `INSERT IGNORE`; returns the number of rows actually inserted.
- Low-level fluent API applied to `insert(...)`: `onConflict([columns],
  [constraint])`, `doUpdate(values, [whereRaw])`, `doNothing()` and
  `returning([columns])`. Lock-free sequence example:

  ```dart
  final rows = await db.table('processos_sequences')
    .onConflict(['ano'])
    .doUpdate({'last_id': db.raw('processos_sequences.last_id + 1')})
    .returning(['last_id'])
    .insert({'ano': 2026, 'last_id': 1});
  final seq = rows.first['last_id']; // like PL/pgSQL "RETURNING ... INTO"
  ```

### PostgreSQL JSON, full-text, DISTINCT ON and arrays

- JSON/JSONB:
  - `whereJsonContains(column, value)` / `orWhereJsonContains` /
    `whereJsonDoesntContain` / `orWhereJsonDoesntContain` →
    `("column")::jsonb @> ?` (value JSON-encoded and bound).
  - `whereJsonLength(column, operator, value)` / `orWhereJsonLength` →
    `jsonb_array_length(("column")::jsonb) <op> ?`.
  - The `->` selector (`where('meta->name', '=', ...)` → `"meta"->>'name'`)
    already worked in `wrap()` and is now covered by tests.
- Full-text: `whereFullText(columns, value, {language, mode})` /
  `orWhereFullText` → `to_tsvector(lang, col) [|| ...] @@ <tsquery>(lang, ?)`,
  `mode` = `plain` (default), `phrase` or `websearch`.
- `distinctOn(columns)` → `SELECT DISTINCT ON (columns) ...`.
- Arrays: `whereArrayContains` (`@>`), `whereArrayContainedBy` (`<@`),
  `whereArrayOverlaps` (`&&`) and the `orWhere...` variants. The list is bound
  as a single array parameter (not spread).
- Implemented in `QueryPostgresGrammar`; the base grammar throws
  `UnsupportedError` on dialects without support. Validated with unit tests and
  live PostgreSQL tests.

### `get()` fast path

`get()` no longer clones/restores `columnsProp` when the columns are already
set, removing a list allocation per query.

## Driver access and streaming

- `db.driver()` / `queryBuilder.driver()` return a typed `DriverAccess?` for
  capabilities the SQL abstraction cannot express (`null` when unsupported).
  The `dpgsql` implementation (`DpgsqlDriverAccess`) provides:
  - `copyInRows(table, columns, rows)` / `copyInRaw(sql, byteStream)` — bulk
    `COPY ... FROM STDIN`, far faster than row-by-row inserts;
  - `copyOutText(sql)` — `COPY ... TO STDOUT`;
  - `notify(channel, [payload])` / `listen(channel)` — `LISTEN`/`NOTIFY`;
  - `withRawConnection(action)` — the native `DpgsqlConnection` (pipelining,
    batch, large objects, ...);
  - `DriverAccess.formatCopyTextRow(...)` — COPY text escaping helper.

  Plumbed through `PDOExecutionContext.driverAccess()` and
  `Connection.driver()`.
- `QueryBuilder.cursor([fetchSize])` (alias `lazy()`) returns a
  `Stream<Map<String, dynamic>>` backed by an incremental reader, keeping
  memory roughly constant for very large results (unlike `chunk`/`each`, which
  page with LIMIT/OFFSET). Plumbed through `ConnectionInterface.cursor`,
  `Connection.cursor` and `PDOExecutionContext.queryStream`. Implemented for
  `dpgsql` (`executeReader`); the other PostgreSQL adapters use an SQL cursor
  (`DECLARE ... NO SCROLL CURSOR` + `FETCH FORWARD n`, inside the current
  transaction or one held while the stream is read, closed when it ends or is
  cancelled); MySQL throws `UnsupportedError` (use `lazyById`).

## dargres adapter

- `DargresPDO` compiles against dargres 4.x (immutable `TimeZoneSettings`;
  `PostgreSqlPool` no longer implements `ConnectionInterface`).
- It now applies the same session as the postgres_fork adapter: `search_path`
  from `schema`, `client_encoding`, `timezone`, `application_name` (also
  without pool) and the `statementTimeout` / `lockTimeout` /
  `idleInTransactionSessionTimeout` options — on every physical connection,
  pool slots and reconnects included (dargres 4.0.1 `searchPath` /
  `sessionStatements`).
- Reconnect follows `allowreconnect`; every command has a 30 s timeout, and the
  pool honours per-call and per-transaction timeouts.
- `numeric` is returned as an exact `String`, like postgres_fork, so switching
  drivers does not change result types.

## Migrations, seeders and CLI

- End-to-end migrations against a live database, with no code generation:
  migrations are registered explicitly in a
  `Map<String, Migration Function()>`. `Migrator` injects the
  `DatabaseManager` into each migration so `migration.schema` works.
- Transactional migrations: each `up`/`down` runs inside a transaction
  (PostgreSQL DDL is transactional), so a failure rolls the migration back. Opt
  out per migration with `withinTransaction = false` (for example
  `CREATE INDEX CONCURRENTLY`).
- Seeders: `Seeder` base class and `SeederRunner`, with the `DatabaseManager`
  injected (`db!.connection(...).table(...)`) and nested `call(otherSeeder)`.
- Migration and seeder classes are exported from the package barrel.
- Scaffolding CLI (`bin/eloquent.dart`, `executables: eloquent`):
  `make:migration <name> [--create=<t> | --table=<t>] [--path=]` and
  `make:seeder <ClassName> [--path=]`. It only generates files; running
  migrations/seeding is driven by the application's registry. The migration
  stubs now `await` the async `schema` getter.
- Working PostgreSQL schema DDL: the previously stubbed `compileCreate`
  (`CREATE TABLE`, `bigserial primary key` for `increments`), `compileAdd`
  (`ALTER TABLE ADD COLUMN`), `compileDrop` and `compileDropIfExists`.

- Runner for production (4.0 review): `Migrator.runPending()` runs the
  registered migrations not in the log, reading only the registry (an AOT
  build has no source files); `pending()` lists them; `markAsRan(names)`
  records a baseline without running it. Each transactional migration runs
  in a `transactionScope` that takes `pg_advisory_xact_lock` (`isolated`,
  PostgreSQL), checks the log again, runs `up` and writes the log, so two
  migrators running at the same time apply it once and a failure rolls back
  the DDL and the log together (the log was written afterwards, on another
  connection). `Migration.connection` and `Migration.statement(sql,
  [bindings])` run raw SQL in the migration's transaction. The migration
  table gets an `id` primary key.
- PostgreSQL `comment(...)` on a column is compiled to `COMMENT ON COLUMN`
  after `create`/`add`/`change` (it was ignored). MySQL `increments()` is
  declared `primary key` (error 1075 before) and time columns take
  `precision:`.

## Doctrine schema port

The schema objects (`Schema`, `Table`, `Column`, `Index`,
`UniqueConstraint`, `ForeignKeyConstraint`, `Sequence`) now produce SQL
through platforms, and a whole schema can be compared and migrated.

- **Platforms.** `AbstractPlatform` was rewritten: column types and
  modifiers come from the dialect's schema grammar, so a column has the
  same DDL in migrations and in `toSql()`. `PostgreSQLPlatform`,
  `MySQLPlatform` and `MariaDBPlatform` implement types, expressions, view
  and sequence listing, isolation levels and the reserved keywords;
  `db.getDatabasePlatform()` picks one from the driver. The folder
  `patforms` became `platforms`.
- **DDL.** `getCreateTableSQL(Table)`, `getCreateTablesSQL` (foreign keys
  after every table), `getDropTablesSQL`, indexes (partial on PostgreSQL;
  FULLTEXT/SPATIAL on MySQL), unique constraints, foreign keys with
  `MATCH` and `DEFERRABLE [INITIALLY DEFERRED]` on PostgreSQL, comments,
  sequences, schemas, renames, truncate and `getAlterSchemaSQL(SchemaDiff)`.
- **Schema.** `toSql`/`toDropSql`, namespaces from qualified names
  (`vendas.pedido`), default table options from `SchemaConfig`, `clone`.
  `AbstractAsset` has `getNamespaceName`, `getShortName`,
  `isInDefaultNamespace` and `getShortestName`.
- **Comparison.** `Comparator.compareSchemas` (namespaces, tables,
  sequences) and `AbstractSchemaManager.introspectSchema`.

Introspection bugs found by the round trip:

| Bug | Effect |
|---|---|
| PostgreSQL `listTableNames` derived its query from `compileTableExists` with a replace that no longer matched | it never returned a table name |
| PostgreSQL serial columns were not auto-increment (only IDENTITY was) | a serial column came back as a plain integer |
| `Utils.map_change_key_case_sd` never changed the key case | MySQL index parsing failed and `EXTRA` (auto_increment) was never read |
| MySQL `NON_UNIQUE` was cast to `bool` | every index was skipped |
| MySQL column collation equal to the table's and empty comments were read as options | spurious diffs |
| `Column.clone()` lost `autoIncrement` (`toArray` writes `autoincrement`) | cloned tables were not auto-increment |
| MySQL `modifyIncrementing` compared the type case-sensitively | introspected `biginteger` lost `auto_increment` |
| PostgreSQL foreign keys did not read `DEFERRABLE`/`INITIALLY DEFERRED`/`MATCH` | lost on a round trip |
| PostgreSQL column collation read from `collcollate` (a locale string, empty for the default collation on PostgreSQL 14) | `collate ""` and a syntax error when recreating; it reads `collname`, only when not the type default |

Tests: `test/doctrine_platform_test.dart` (SQL for both platforms) and
`test/doctrine_platform_integration_test.dart`. The integration test
creates a schema from memory, introspects it (A), drops it and creates it
again from A, introspects it (B), and checks that A and B do not differ.
It also migrates a live schema with `compareSchemas` +
`getAlterSchemaSQL`, on PostgreSQL (postgres, dpgsql) and MariaDB.

## Schema introspection and diff → ALTER

- Live introspection works. Three bugs in `PostgreSQLSchemaManager` made
  `listTableDetails` throw against a real database:
  - `listTableColumns` referenced the non-existent `pg_attrdef.adinhcount`
    (`42703`);
  - `listTableIndexes` bound a table `oid` back as a parameter
    (`operator does not exist: oid = bytea`); columns are now looked up by
    `relname`/`nspname`;
  - `i.indkey` (`int2vector`) was decoded as raw bytes; it is now cast to
    `::text`.
- `listTableIndexes` exposes the access method (`USING btree|hash|gist|gin|...`)
  as `index.getOption('using')`.
- The pipeline works end to end:
  `connection.getDoctrineSchemaManager().listTableDetails(...)` →
  `Comparator().compareTables(...)` / `grammar.getChangedDiff(blueprint, sm)` →
  `SchemaPostgresGrammar.compileTableDiff(diff, blueprint)` → executable
  `ALTER TABLE ...` (add/drop/rename/retype/nullable/default, indexes, foreign
  keys, unique constraints).
- `ColumnDiff` compares `platformOptions` with deep, key-order-independent
  equality instead of `toString()`.
- MySQL ENUM/SET introspection: multi-value enums were never parsed (the
  arguments were comma-split before the enum branch, so `allowedValues` stayed
  null). Enum/set are handled first, with a single-pass unescaper for `''`,
  `\\`, `\'`, `\"`, `\n`, `\t`, `\r`, `\0`, `\b`, `\Z`.
- Exported from the barrel: `Comparator`, `Table`, `Column`, `TableDiff`,
  `ColumnDiff`, `Index`, `ForeignKeyConstraint`, `UniqueConstraint`,
  `AbstractSchemaManager`.
- `schema:diff` CLI command (`bin/eloquent.dart`): introspects two tables and
  prints the `ALTER TABLE <a> ...` statements that make `<a>` match `<b>`;
  dry-run by default, `--apply` to execute; connection via
  `--database/--username/--password/--host/--port/--schema/--driver-impl`.

## Active Record

`lib/src/orm/active_record.dart` (exported). It has no code generation and
no reflection: `ModelDefinition(create: User.new)` gives the constructor,
and the model exposes typed getters and setters over
`readAttribute<T>`/`writeAttribute`.

- **State.** A model keeps its raw attributes, the values last read or
  saved, whether it exists, its connection and its loaded relations.
  `getDirty()` compares them with deep equality. A column that was not
  selected throws on read, and `save()` updates only dirty columns.
  `save()` on a new model inserts it; on PostgreSQL it reads the row back
  with `insert ... returning *`, which brings the key and the defaults.
  `timestamps: true` fills `created_at`/`updated_at`.
- **Queries.** `ModelQuery<T>` mixes in `WhereConditions`, so it has the
  whole `QueryBuilder2` where API, plus `find`, `findMany`, `firstOrFail`,
  `paginate` (`ModelPage`), `count`, `exists`, `lazyById` and bulk
  `update`/`delete`. `configure()` reaches the underlying builder.
- **Relations.** `HasOne`, `HasMany` and `BelongsTo` are declared once,
  as static fields with a name. The same object builds one parent's query
  (`of`), runs and keeps it (`fetch`), loads it for many parents
  (`ModelQuery.withRelation`) and reads it (`getLoaded`, `isLoaded`), so
  no per-instance callback can build different filters for each parent.
- **One of many.** `latestOfMany`, `oldestOfMany` and `ofMany(column,
  minimum/maximum)` follow Laravel. The default column is the related
  primary key; rows with a null column are not candidates; ties go to the
  highest primary key. In batches it uses `row_number() over (partition by
  fk order by column, pk desc)`, one query per relation, with keys in chunks
  of 5000.
- **Casts.** `Casts.boolean`, `integer`, `decimal`, `dateTime`, `json` and
  `enumByName`; `AttributeCast<T>` for others.

Also:

- **`BelongsToMany`** joins the pivot table and reads its keys and
  `pivotColumns` as `__pivot_<column>`. `hydrate` moves those into the
  model's pivot, so they never reach `save()`; `pivot(model)` returns them.
  `attach`, `detach` and `sync` (which returns `(attached:, detached:)`)
  write the pivot table and forget the loaded relation on the parent.
- **Scopes.** `globalScopes: {'name': (w) => ...}` apply to every query,
  relations included, and `withoutGlobalScope(name)`/`withoutGlobalScopes()`
  remove them. Local scopes are plain functions, applied with
  `apply(scope)`. When scopes or soft deletes add conditions, a query's own
  conditions are grouped if they contain an `or`.
- **Soft deletes.** With `softDeletes: true`, `delete()` sets `deleted_at`
  (and `updated_at` when timestamps are on), and `restore()`,
  `forceDelete()` and `trashed` are available. Queries leave the deleted
  rows out (`withTrashed()`, `onlyTrashed()`), and so do relations,
  including the ranked "one of many" query, which is now built from the
  related `ModelQuery`. Bulk `delete()` on a query is soft, `forceDelete()`
  removes, and `restore()` touches only the deleted rows.
- **Observers.** `ModelObserver<T>` has `saving/saved`, `creating/created`,
  `updating/updated`, `deleting/deleted` and `restoring/restored`. Register
  one with `definition.observe(...)` and remove it with `unobserve(...)`.
  An exception in a callback stops the operation.

Tests: `test/active_record_step4_integration_test.dart` on the five
drivers.

`QueryBuilder2`'s `WhereConditions` hooks became `@protected`
(`whereClauseList`, `whereSelf`) so other libraries can mix it in, and
`addWhereClause` adds a prebuilt condition.

Tests: `test/active_record_integration_test.dart` on the four PostgreSQL
adapters and MariaDB. It covers insert, partial select and save, the two
"one of many" relations with a price tie, a user with only null prices and a
user without orders, eager loading with one query per relation, `belongsTo`,
filters, pagination, delete, refresh and rollback. Also
`test/active_record_casts_test.dart`.

## Lightweight ORM

`Repository<T>` + `EntityMapper<T>`: a thin data mapper over the query builder,
without code generation or reflection. The application supplies `fromRow` /
`toRow` / `getId`; the repository provides `find`, `findOrFail`, `all`,
`findBy`, `firstBy`, `insert`, `update`, `save` (insert or update by primary
key), `delete`, `deleteById`, `count` and `cursor` (streamed, hydrated
entities). Validated with live PostgreSQL tests.

## Fixes

- `QueryPostgresGrammar.compileInsert` emitted a stray `}` for empty inserts
  (`insert into <table>} DEFAULT VALUES`).
- `SchemaBuilder` failed when the connection `schema` was a `List` (search
  path); `_getSchemaName` normalizes String/List/CSV to the first schema
  (previously `type 'List<String>' is not a subtype of String?`).
- `DatabaseMigrationRepository.getMigrations(steps)` selects by batch (Laravel
  semantics: one rollback step reverts the whole last batch) instead of by row
  count.
- `DatabaseMigrationRepository._getConnection` and
  `Migrator._resolveConnection` fall back to the resolver's default connection
  instead of dereferencing a null name.
- `transaction()` ignored `timeoutInSeconds` (see
  [Breaking changes](#breaking-changes-and-migration)).

## Query builder and driver fixes (4.0 review)

Every item was reproduced first and has a regression test:
`test/regression_group_a_test.dart` (generated SQL and bindings, no database)
and `test/regression_group_a_integration_test.dart` (PostgreSQL with
postgres, postgres_v3, dargres and dpgsql, and MariaDB 10.11).

### Query builder

- **`where` and null.** `where(col, op, null)` turned every operator except `=`
  into `is not null`, so `where('a', '>', null)` returned the rows where `a` is
  not null. Now `=` → `is null`, `<>`/`!=` → `is not null`, other operators
  throw `ArgumentError`.
- **Two-argument `where`.** `where('name', 'John')` put `'John'` in the
  operator slot and became `"name" is not null`. A sentinel default now
  detects the two-argument call, as Laravel's `func_num_args()` does; `orWhere`
  too.
- **`groupBy` / `groupByRaw`.** `groupBy` only kept `String`/`List` values,
  so `groupBy(db.raw('date(created_at)'))` was dropped silently and the query
  ran without GROUP BY. It now accepts `QueryExpression` (alone or in a list)
  and throws on anything else. New `groupByRaw(sql, [bindings])`; its bindings
  go to a `groupBy` bucket placed between `where` and `having`, the SQL order
  (as in Laravel). Note that PostgreSQL treats `x % $1` in the select and
  `x % $3` in the GROUP BY as different expressions: do not repeat a
  parameterized expression in both.
- **`whereIn([])`** produced `in ()`, an SQL error (`Utils.empty` ignores empty
  lists). Now `0 = 1` / `1 = 1`. Sets and other iterables are accepted.
- **`count()`** returned `results[0]['aggregate']`, the first group's count,
  for grouped queries; `distinct()` with `*` ignored the distinct; pagination
  fetched every group row to count them. Grouped, `having`, union and
  `distinct` queries now run
  `select count(*) as aggregate from (<query>) as "aggregate_table"` (orders,
  limit and offset removed for pagination; kept by `count()` when they change
  the result). A grouped query without explicit columns selects the constant
  `1` (one row per group; `select *` with `GROUP BY` is invalid on PostgreSQL,
  and repeating raw group expressions would duplicate their bindings).
  `distinct().count('id')` keeps `count(distinct "id")`. Aggregates given as
  `String` are parsed.
- **`CountMode`.** `count(columns, mode)` chooses the semantics:

  | Query | `CountMode.rows` (default) | `CountMode.laravel` (Laravel 12) |
  |---|---|---|
  | `groupBy` only | rows (groups) of the query, via subquery | first group's count |
  | `distinct()` + `select(...)` | distinct rows, via subquery | `count(*)` of every row |
  | `having` or `union` | via subquery | via subquery (as Laravel's `compileUnionAggregate`) |
  | plain query, `count('col')`, `distinct().count('col')` | same SQL in both modes | same |

  Pagination always counts through a subquery for grouped/`having` queries,
  as Laravel's `runPaginationCountQuery` does.
- **Builder state.** `aggregate()` and `getCountForPagination()` restore the
  builder in `finally`; `paginate`/`simplePaginate` paginate a clone, so the
  page's `limit`/`offset` no longer stay on the builder.
- **`exists()`** passed `useWritePdo` where `Connection.select` expects
  `useReadPdo`, reading from the write connection by default.
- **`value(col)`** returned the whole row; it returns the column value
  (`'t.col'` and `'col as alias'` accepted).
- **`union(Function)`** stored the function and then called
  `getBindings()` on it (crash); the built query is stored. `unionAll` returns
  `QueryBuilder`.
- **`updateOrInsert`** added the attribute wheres twice (duplicated bindings,
  builder left modified); an empty `values` map no longer runs an invalid
  `update`.
- **`clone()`** now copies `aggregateProp`, `useWritePdoProp`,
  `onConflictProp` and `returningProp`.

### UPDATE and DELETE

- **Binding order.** `update()` sent `[SET values, ...getBindings()]`, wrong
  whenever a CTE or join binding precedes `SET`. Each grammar now builds the
  list in its SQL order (`prepareBindingsForUpdate` / `prepareBindingsForDelete`):
  PostgreSQL `CTE, SET, where, join`; MySQL `CTE, join, SET, where, order`.
- **PostgreSQL `delete` with joins** ignored the joins (`delete from "a" where
  ...`), deleting rows that did not match them, and misaligned join bindings.
  It now emits `delete from "a" using "b" where <wheres> and <join conditions>`.
  Left/right joins throw instead of silently acting as inner joins (also on
  `update ... from`).
- **PostgreSQL `limit`** was ignored by `update`/`delete` (so
  `updateOrInsert` updated every match). Now
  `... where ctid in (select ctid from t <wheres> <order> limit n)`.
- **CTEs** were dropped by the PostgreSQL `update` (bindings still sent) and by
  every MySQL statement (`select`/`update`/`delete`); MySQL also places the
  `WITH` before a parenthesized `union`.
- **`recursionLimit()`** was never compiled (and its base form is SQL Server
  syntax). PostgreSQL and MySQL now throw `UnsupportedError` with the
  alternative.

### Timeouts

- The builder dropped its timeout: `get(columns, timeoutInSeconds)` →
  `runSelect` → `select`, `insert/update/delete(..., Duration)` and
  `Connection.selectOne` never forwarded it. All of them do now (`Duration`
  rounded up to whole seconds).
- postgres_v3 ignored `statementTimeout`/`lockTimeout`/
  `idleInTransactionSessionTimeout` and computed but never used the
  transaction timeout (now `TransactionSettings.queryTimeout`).
- `PDOConfig.fromMap` read only the camelCase timeout keys; `statement_timeout`,
  `lock_timeout` and `idle_in_transaction_session_timeout` are accepted too.
  The three copies of the timeout parser are now
  `PDOConfig.normalizePgTimeout`/`postgresTimeoutStatements()`.
- dargres without pool ignored per-call timeouts; it now cancels the command
  (`cancelCurrentQuery`) and waits for it to settle.
- dpgsql used `Future.timeout`, which abandoned the protocol read: the next
  command failed with "Buffer interno menor que o esperado" or read the
  cancelled command's leftovers. It now sends a CancelRequest, waits for the
  response, discards the socket and, without pool, reopens the connection.
- MySQL: `lockTimeout` → `lock_wait_timeout`; `statementTimeout` →
  `max_statement_time` (MariaDB) or `max_execution_time` (MySQL, SELECT only).

### Connections and drivers

- **MySQL pool session.** `use`, `set names`, `time_zone` and `sql_mode` ran
  once, on whichever pool connection served them. They now run on every
  physical connection (`onConnectionOpen`); a missing `await` in `setModes` is
  gone.
- **dpgsql `WITH ... UPDATE/DELETE`** reported 0 affected rows (treated as a
  row-returning query); statements starting with `with` use a reader and fall
  back to the command's affected-row count.
- **postgres_fork duplicate columns.** Inside a transaction rows were merged
  per table (`toTableColumnMap` + `reduce`), so `select a.id, b.id` returned a
  different `id` than outside and an empty row threw. Both paths use
  `toColumnMap()` (last column wins, like every other driver).
- **`prepareBindings`** converted `DateTime`/`false` in the caller's list (often
  a builder's binding bucket); it now works on a copy.
- **Lost connection retry** reset its counter right after reconnecting and
  retried inside transactions (where the transaction is gone);
  `tryAgainIfCausedByLostConnection` incremented the limit instead of the
  count. One loop now retries up to `tryReconnectLimit` times with backoff,
  only outside transactions and with a reconnector, keeping the original stack
  trace.
- **`exists()` on MySQL** compared the `1`/`0` that MySQL returns with `true`,
  so it was always false and `updateOrInsert` always inserted a duplicate.
  `true`, `1`, `'1'` and `'t'` now count as existing.
- **`whereColumn([...])`** (list or map of conditions) fell back to `where`,
  binding the second column as a string value; it now compares columns.
- **Single connection, concurrent callers.** dpgsql and mysql_dart run one
  command per connection and rejected a second one ("another command is still
  running" / "connection is busy"), while the postgres, postgres_v3 and dargres
  adapters queue them. `DpgsqlPDO` and `MySqlClientPDO` without pool now
  serialize operations (`OperationLock`): queries, `execute`, whole
  transactions and, for dpgsql, an open `cursor()` stream. As with the other
  adapters, calling the outer connection from inside its own transaction
  callback waits forever; use the `ctx` connection.
- `PDOInterface.getConfig()` threw the config instead of returning it;
  `DatabaseManager` called `extensions[name]` for a driver extension.

## Ambient transaction: `transactionScope`

`db.transaction((ctx) ...)` only covers what runs through `ctx`. A query on
`db` inside the callback runs elsewhere: with a pool, on another connection
(it does not see the transaction's rows and is not rolled back); without a
pool, it waits for the transaction to end, which waits for it (verified on
the five adapters: a timeout). `transactionScope` makes the transaction
ambient for the callback:

```dart
await db.transactionScope((ctx) async {
  await processoRepository.encaminhar(dados); // uses `db`: in the transaction
  await db.transaction((inner) async { ... }); // a SAVEPOINT of it
  await db.outsideTransaction(() => log.gravar(evento)); // survives a rollback
});
```

- The scope is a `Zone` value: it covers the async calls of the callback only;
  other requests on the same `db` are not affected. While no scope is open
  the cost per query is one integer check.
- Inside it `db.transaction` is a SAVEPOINT, `db.transactionIfNeeded` joins
  the transaction, `db.isInTransaction` and `db.isInTransactionScope` are
  true, `db.cursor()` and `db.driver()` use the transaction's connection.
  Concurrent calls (`Future.wait`) share that connection, one at a time.
- Work still running after the scope (an unawaited future, a timer) uses `db`
  normally again.
- `outsideTransaction` needs a pool: with a single connection there is no
  other connection, and it throws `StateError` instead of waiting forever.
- `transaction()` is unchanged; the scope is opt-in.

## Search, filters and client ordering

- `whereSearch(columns, term, {match, unaccent, caseSensitive, everyWord})`:
  `(col1 ilike ? or col2 ilike ?)` with the term matched literally (`%`, `_`
  and `\` escaped; `SearchMatch.contains`/`startsWith`/`endsWith`/`exact`,
  or `wordsInOrder`: `%maria%da%`, the words in order with anything between).
  A null or blank term adds nothing. `unaccent: true` (PostgreSQL, extension
  `unaccent`) compares `unaccent(col::text) ilike unaccent(?)`;
  `QueryPostgresGrammar.unaccentFunction` names another function (e.g. an
  IMMUTABLE `f_unaccent` an expression index can use). `everyWord` requires
  every word in some column. Columns are identifiers, or `db.raw(...)` in
  QueryBuilder; MySQL leaves case and accents to the collation.
- `lower: true` compares `lower(col) like lower(?)` (with `unaccent`:
  `lower(unaccent(col::text)) like lower(unaccent(?))`) instead of `ilike`:
  the same rows, but an expression index can serve it, e.g. with an
  IMMUTABLE wrapper set as `unaccentFunction`:
  `create index on cgm (lower(f_unaccent(nom_cgm::text)) text_pattern_ops)`
  for `match: SearchMatch.startsWith`. Name the schema inside the wrapper
  (`select public.unaccent($1)`): since PostgreSQL 17, CREATE INDEX runs
  index functions with `search_path = pg_catalog, pg_temp`. On MySQL it ignores case even with a
  `_bin`/`_cs` collation. It cannot be combined with `caseSensitive`.
- `whereAnyLike(columns, pattern)`: the same group with the pattern as given;
  `whereLike(..., unaccent: true, lower: true)`;
  `QueryBuilder.escapeLike`/`likePattern`.
- `orderByInput(field, direction, allowed: {'nome': 'c.nom_cgm'}, fallback:)`:
  the client's field is looked up in the allow-list (values: a column, a list
  of columns, or `db.raw` in QueryBuilder); unknown or empty fields use the
  fallback; `desc`/`descending` in any case is descending, anything else
  ascending. The client's text never reaches the SQL.

## Composite keys, arrays and ranges

- `whereInTuple(['cod_processo', 'ano_exercicio'], [[10, '2024'], ...])` →
  `("cod_processo", "ano_exercicio") in ((?, ?), ...)`; `whereNotInTuple`;
  `whereRowValues(columns, operator, values)` → `(a, b) > (?, ?)`.
- `whereAnyArray('id', ids)` → `"id" = any(?)` with ONE array parameter
  (PostgreSQL): the same SQL for any number of ids (one prepared statement)
  and no 65535-parameter limit; `elementType: 'uuid'` casts it
  (`?::uuid[]`); `whereNotAnyArray` → `<> all(?)`. MySQL compiles `in (...)`.
- `whereBetweenColumns('valor', ['minimo', 'maximo'])`,
  `whereValueBetween(hoje, ['data_inicio', 'data_fim'])` (Laravel 12), and the
  `or`/`not` forms.

## Pagination

- `cursorPaginate({perPage, cursor})`: keyset pagination on the orders of the
  query (no OFFSET, no count): order by unique plain columns (end with the
  key), select them; the opaque `CursorPage.nextCursor`/`previousCursor` go
  back as `cursor`. Values (including DateTime) are only bound as parameters;
  an invalid cursor throws `FormatException`.
- `paginateWithWindowCount(...)`: `paginate` in one query with
  `count(*) over ()`. Opt-in and not always faster: the database still finds
  every matching row to count them, while the separate count query of
  `paginate` can skip the joins and the select list; measure first. An empty
  page past the first falls back to the count; `distinct`/unions use
  `paginate`.

## Other query builder additions

- `explain({analyze})`: the rows of `EXPLAIN [ANALYZE]`.
- `afterQuery(callback)`: transforms the rows of `get` (and `first`,
  `paginate`, `chunk`...), not of aggregates.
- `updateFrom(values)`: Laravel's name for an update whose inner joins become
  `update ... from ...`; `update()` already compiles joins this way here.

## Bulk inserts and numbering

- `copyInto(rows, {columns, batchSize})`: `COPY ... FROM STDIN` when the
  driver supports it (dpgsql), otherwise multi-row INSERTs within the
  parameter limit. Rows with lists, maps or bytes use the INSERT path.
- `insertUnnest(rows, types: {'id': 'int', 'nome': 'text'})`:
  `insert into t (id, nome) select * from unnest(?::int[], ?::text[])`, one
  array literal per column (PostgreSQL; MySQL uses multi-row INSERTs).
- `nextValue(column, {start, lock})`: `coalesce(max(column), start - 1) + 1`
  in the rows of the query (its where clauses are the scope). With `lock`
  (default) concurrent transactions with the same scope take turns on a
  `pg_advisory_xact_lock` held until commit; it must run in the transaction
  that inserts the number (`StateError` otherwise). PostgreSQL only with the
  lock (`select max ... for update` deadlocks on InnoDB); `lock: false` is a
  plain max + 1.

## Unique violations, createOrFirst and explicit locks

- `UniqueConstraintViolationException` (Laravel 10+): a `QueryException`
  thrown for PostgreSQL SQLSTATE `23505` and MySQL/MariaDB errors 1062/1586,
  on the five adapters. `constraint` is the violated constraint or unique
  index (PostgreSQL's constraint name; MySQL's key name without the table),
  `sql`/`bindings` the statement, `previous` the driver's exception. Other
  driver errors are not wrapped. On postgres and postgres_v3 the transaction
  ends with the driver's exception; `transaction()` rethrows it as the
  mapped exception, so the caller of `db.transaction` sees the same type on
  every adapter.

  With a unique index the database enforces the rule, and the check in Dart
  is only for the message:

  ```dart
  // CREATE UNIQUE INDEX tipo_norma_nome_uq
  //   ON normas.tipo_norma (lower(public.immutable_unaccent(trim(nom_tipo_norma))));
  try {
    await db.table('normas.tipo_norma').insert(item.toMap());
  } on UniqueConstraintViolationException catch (e) {
    if (e.constraint != 'tipo_norma_nome_uq') rethrow;
    throw TipoNormaOperacaoException('Já existe um tipo de norma com esse nome.',
        statusCode: 409);
  }
  ```

- `createOrFirst(attributes, [values])` / `firstOrCreate(attributes,
  [values])` on `QueryBuilder` and `QueryBuilder2` (Laravel's semantics, the
  row as a `Map`): insert, or return the row of `attributes` when a unique
  index refuses it, with no lock and no race. On PostgreSQL the insert is
  `insert ... on conflict do nothing returning *`, so a conflict is not an
  error and a surrounding transaction stays usable on every adapter
  (postgres_v3 ends the transaction on any SQL error, even in a SAVEPOINT);
  on MySQL it runs in a SAVEPOINT inside a transaction. If the row of
  `attributes` is not found after a conflict (another unique index refused
  it), the `UniqueConstraintViolationException` is thrown.
- `db.advisoryLock(key)` / `db.tryAdvisoryLock(key)` (PostgreSQL,
  `pg_advisory_xact_lock` / `pg_try_advisory_xact_lock`): serializes the
  transactions that ask for the same key until they commit or roll back,
  without blocking reads, other writes or foreign key checks as `LOCK TABLE`
  does. The key is a String (hashed with `hashtextextended`) or a bigint.
  `StateError` outside a transaction, `UnsupportedError` on MySQL (whose
  `GET_LOCK` is per session, not per transaction). Not in Laravel, which
  uses cache locks (`Cache::lock`) outside the database transaction.
- `lockTable(TableLockMode mode, {noWait, timeout})` on `QueryBuilder` and
  `QueryBuilder2`: `lock table "schema"."table" in <mode> mode [nowait]`,
  with the mode from an enum (no SQL text) and the table quoted.
  `StateError` outside a transaction, `ArgumentError` for an alias or
  subquery, `UnsupportedError` on MySQL (`LOCK TABLES` commits the current
  transaction). Laravel has no equivalent (`DB::statement('LOCK TABLE ...')`).
- `QueryGrammar.supportsReturning` and `compileLockTable`.

Which one to use:

| Need | Tool |
|---|---|
| A value must be unique (name, code per year) | Unique index + `UniqueConstraintViolationException` or `createOrFirst` |
| Lock the rows that will be changed | `lockForUpdate()` |
| One transaction at a time in a piece of code (max + 1 plus checks) | `advisoryLock(key)`, or `nextValue()` for the max + 1 alone |
| Block writes to the whole table (maintenance, bulk reload) | `lockTable(...)` |

## QueryBuilder2 additions

`whereAny`/`whereAll`/`whereNone`, `whereDate`/`whereTime`/`whereDay`/
`whereMonth`/`whereYear`, `whereJsonContains`/`whereJsonDoesntContain`/
`whereJsonLength`, `whereArray` (`ArrayOperator.contains`/`containedBy`/
`overlaps`), `whereFullText`, `distinctOn`, `joinSub`/`leftJoinSub`,
`joinLateral`/`leftJoinLateral`, `latest`/`oldest`/`inRandomOrder`,
`cursor`, `chunk`, `chunkById`, `insertUsing`, `firstOrFail`, plus everything
in the sections above (`whereSearch`, `orderByInput`, `whereInTuple`,
`whereAnyArray`, between columns, `cursorPaginate`,
`paginateWithWindowCount`, `explain`, `afterQuery`, `updateFrom`,
`copyInto`, `insertUnnest`, `nextValue`, `createOrFirst`, `firstOrCreate`,
`lockTable`).

## Ported from Laravel 12

The query builder is a port of Laravel 5.2. These are the Laravel 12
features that are useful in Dart code; all of them are additive.

### Query log, listeners and dry run

```dart
final stop = db.listen((QueryExecuted q) {
  print('${q.time.inMilliseconds} ms ${q.toRawSql()}');
  if (q.failed) print(q.error);
});
final stopSlow = db.onSlowQuery(Duration(milliseconds: 200), (q) => log(q.sql));

db.totalQueryDuration();      // time spent while a log/listener was active
db.resetTotalQueryDuration();
stop();                       // removes the listener
```

- `QueryExecuted` has `sql`, `bindings`, `time`, `connection`, `error`,
  `failed`, `connectionName` and `toRawSql()`. Failed statements are reported
  too.
- Statements run on the `ctx` connection of a `transaction()` callback are
  reported to the listeners and query log of the outer connection (they
  share the observers).
- Time is only measured while a query log or a listener is active, so there
  is no cost otherwise.
- `pretend(callback)` now awaits the callback, returns the statements it
  would run, returns empty results for `select` (it used to run them) and
  restores the previous query log, also when the callback throws.

### `toRawSql()`

`query.toRawSql()` returns the SQL with the bindings inlined, escaped for the
dialect (PostgreSQL `true`/`false`, `'\x..'::bytea` and array literals;
MySQL `1`/`0`, `x'..'` and backslash escaping). `?` inside string literals is
left alone. `dumpRawSql()` prints it and returns the builder. It is meant for
logs and debugging; never execute it.

### Conditional building

```dart
db.table('processo')
    .when(filtro.situacao, (QueryBuilder q, situacao) => q.where('situacao', situacao))
    .unless(incluirArquivados, (QueryBuilder q) => q.whereNull('arquivado_em'))
    .tap((q) => aplicarPermissoes(q));
```

The condition is "truthy" when it is not `null`, `false`, `0`, `''` or an
empty collection; the callback may take the builder only or the builder and
the condition value. `when` takes an optional `otherwise` callback.

### Where helpers

| Method | SQL |
|---|---|
| `whereAny(['nome', 'email'], 'like', '%ana%')` | `("nome" like ? or "email" like ?)` |
| `whereAll(['a', 'b'], '>', 0)` | `("a" > ? and "b" > ?)` |
| `whereNone(['a', 'b'], 'x')` | `not ("a" = ? or "b" = ?)` |
| `whereNot('situacao', 'C')` / `whereNot((q) => ...)` | `not "situacao" = ?` / `not (...)` |
| `whereLike('nome', 'joão%')` | PostgreSQL `"nome"::text ilike ?`; MySQL `like ?` |
| `whereLike(..., caseSensitive: true)` | PostgreSQL `like ?`; MySQL `like binary ?` |
| `whereIntegerInRaw('id', ids)` | `"id" in (1, 2, 3)` with the integers inlined |

All of them have `or*` forms (`orWhereAny`, `orWhereNotLike`,
`orWhereIntegerNotInRaw`, ...). `whereLike` is case-insensitive by default,
as in Laravel; on MySQL the column collation decides. `whereIntegerInRaw`
has no bind-parameter limit (PostgreSQL rejects more than 65535 parameters)
and throws `ArgumentError` for values that are not integers.

### Ordering, selects and subqueries

- `orderByDesc(column)`, `reorder([column, direction])` (removes the orders
  and their bindings), `reorderDesc(column)`.
- `orderBy` accepts a `QueryBuilder`, a `Function(QueryBuilder)` or a raw
  expression as the column, and throws for a direction other than
  `asc`/`desc`.
- `select({'alias': subquery})` and `addSelect({'total': subquery})` add
  `(select ...) as "alias"` with the subquery bindings in the select bucket.
- `fromSub(query, alias)`, `leftJoinSub`, `rightJoinSub`, `crossJoinSub`.

### Iteration

| Method | Notes |
|---|---|
| `lazyById([chunk, column, alias])` | `Stream` of rows by keyset pagination; works on every driver |
| `lazyByIdDesc(...)` | same, descending |
| `eachById(callback, {count, column, alias})` | row callback; returning `false` stops |
| `chunkById` / `chunkByIdDesc` | each page uses a fresh clone; `StateError` if the id column is missing from the rows |
| `chunkMap(mapper, [count])` | maps every row, chunk by chunk |
| `forPageBeforeId(perPage, lastId, column)` | keyset page in descending order |

### Single results and existence

- `sole([columns])` returns the only row; it throws
  `RecordsNotFoundException` for none and `MultipleRecordsFoundException`
  (with `count`) for more than one. `soleValue(column)` returns its column.
- `firstOrFail([columns])` and `findOr(id, callback)`.
- `doesntExist()`, `existsOr(callback)`, `doesntExistOr(callback)`.

### Having

- `having(column, value)` (two-argument form means `=`) and
  `having((QueryBuilder q) => ...)` / `havingNested(...)` for groups.
- `havingBetween`, `havingNotBetween`, `havingNull`, `havingNotNull` and
  their `or*` forms.

### Updates

`incrementEach({'n': 1, 'm': 2}, [extra])` and `decrementEach(...)` update
several counters in one statement.

### MySQL full-text

`whereFullText(['titulo', 'corpo'], 'termo')` compiles to
`match (...) against (? in natural language mode)`; the options
`{'mode': 'boolean'}` and `{'expanded': true}` select boolean mode and
query expansion. On PostgreSQL the `language` option is now validated,
because it is inlined in the SQL.

### Fix found while porting

`where(column, value)` and `having(...)` with a `List` value (`Uint8List`, a
PostgreSQL array for `@>`, a JSON list) added one binding per element for a
single placeholder. The value is now one binding.

### Not ported

`cursorPaginate()` and `groupLimit()` (window-function eager-load limits) are
not part of this release.

## Fixes found while resolving the TODOs

### Lost-connection detection

`causedByLostConnection` decides when a statement is retried on a new
connection (outside transactions). It matched a few substrings, `'57P'`
among them. Killing the session with `pg_terminate_backend`/`KILL` showed
what each adapter reports:

| Adapter | Error after the session ends | Detected before |
|---|---|---|
| postgres, postgres_v3 | `Attempting to execute query, but connection is not open.` | yes |
| dargres | `FATAL 57P01 ...` | yes |
| dpgsql | `SocketException`, then `EOF antes de ler 5 bytes` | **no**: every later query failed |
| mysql_dart | `Can not execute query: connection closed` | **no**: every later query failed |

The check now uses:

- `SocketException`/`TlsException`;
- the structured code: `sqlState`/`code` of class `08` or `57P01`-`57P03`,
  and MySQL `errorCode` 2002, 2006, 2013, 1053, 1927 or 4031;
- the messages above plus the PostgreSQL/MySQL entries of Laravel's list.

Codes are not matched as loose numbers, so `(cep)=(08001-000)` in a
unique violation or `'2013-02-30'` in a MySQL data error does not trigger a
retry. `test/lost_connection_integration_test.dart` covers the five adapters,
with and without pool. `disconnect()` after the session was killed used to
hang on MySQL; that is fixed in mysql_dart 3.0.1.

### Migrations

| Command | Before | Now |
|---|---|---|
| `foreign()` (PostgreSQL, MySQL) | no SQL | `alter table ... add constraint {table}_{columns}_foreign foreign key ... references ... [on delete/update]` |
| `deferrable()`, `initiallyDeferred()` (PostgreSQL) | ignored | `deferrable [initially deferred/immediate]` |
| `schema.create()` (MySQL) | empty query (MySQL error 1065) | `create table ...` |
| `dropColumn()`, `dropForeign()`, `rename()` (PostgreSQL) | no SQL | `drop column`, `drop constraint`, `rename to` |

The `on delete`/`on update` action is validated (`cascade`, `restrict`,
`set null`, `set default`, `no action`) because it is inlined in the SQL.
`foreign()` without a name now gets Laravel's default name, the one that
`dropForeign([...])` generates. Covered by
`test/schema_foreign_key_integration_test.dart` on PostgreSQL and MariaDB.

### Doctrine schema

- `Table.addForeignKey()` always threw `NoSuchMethodError` (the implicit index
  read `getColumns()` from the foreign key).
- `Table.renameColumn()` left indexes, unique constraints and foreign keys
  on the old name, and printed "Error/TODO" for foreign keys.
- `QueryBuilder.getProperty()` printed and returned the property name for an
  unknown property; it throws `ArgumentError`.

## Stress test (REST API with isolates)

`test/stress_rest_api_integration_test.dart` runs a small REST API on
`dart:io` `HttpServer`, served by several isolates on one shared port
(`shared: true`), each with its own `Connection`. Several client isolates use
`HttpClient` against it, concurrently. Each client creates items (in a
transaction that also bumps a counter row), reads them back, increments them
in parallel, rereads them, and writes and reads notes created with
`insertGetId` outside a transaction. At the end the test checks counts, sums
and the counter in the database. It covers the five drivers, with and
without pool. Size with `STRESS_SERVERS`, `STRESS_CLIENTS`, `STRESS_ITEMS`,
`STRESS_INCREMENTS` and `STRESS_POOL_SIZE` (defaults 4/6/20/3/4; checked
with 6/12/50/5).

It found three bugs:

| Bug | Fix |
|---|---|
| MySQL `insertGetId` returned another request's id: the processor ran `SELECT LAST_INSERT_ID()` as a second statement, which could use another pooled connection, or come after another caller's insert on the single connection | `PDOResults.insertId` from the OK packet; the SELECT is only a fallback |
| postgres_v3 single connection: queries during another caller's `runTx` failed | `OperationLock` around query/execute/transaction |
| dargres single connection: queries during another caller's transaction failed | `OperationLock` in `_onCore` |

The drivers that are part of this project now queue concurrent callers of
one connection themselves (dargres 4.0.1, dpgsql 1.0.3, mysql_dart 3.0.1):
commands wait for their turn, and a transaction run through the driver's
callback API holds the connection until it commits. The test runs dargres,
dpgsql and mysql a third time, on a single connection with the adapter's
lock off (`OperationLock.enabled`, tests only), and passes; with mysql_dart
3.0.0 that run fails with "connection is busy". The adapters keep their lock:
it measures each call's timeout from when the call starts running, and a
timeout's cancel (dargres) or connection replacement (dpgsql) cannot hit
another caller's command. The dpgsql adapter runs single-connection
transactions through `DpgsqlConnection.runInTransaction`, so other callers'
commands never run inside them.

## Performance

Query compilation hot path: about 17% faster `toSql()` on a medium query in an
AOT micro-benchmark, with byte-identical SQL
(`benchmark/query_compile_benchmark.dart`):

- `compileComponents` and `compileWheres` dispatch through a direct `switch`
  instead of building a `'compile' + ucfirst(...)` / `"where" + type` name and
  looking it up in a `Map<String, Function>` for every component/clause (the
  string-keyed `_methodMap` remains for compatibility and as the fallback).
- `wrap()` skips the per-call `strtolower` copy (case-insensitive `" as "` scan)
  and has a fast path for non-dotted identifiers, avoiding `explode`/`implode`
  list allocations.
- `wrapValue()` only runs the quote-doubling replace when a `"` is present.

## Tests, CI and tooling

- `test/transaction_savepoint_integration_test.dart` — transaction levels,
  savepoints, `transactionIfNeeded`, generic results and SKIP LOCKED for
  `postgres` (with and without pool), `postgres_v3`, `dargres` (with and
  without pool), `dpgsql` and MySQL (with and without pool).
- `test/query_builder_lock_test.dart` — lock SQL for PostgreSQL and MySQL.
- `test/notification_listener_test.dart` (listener with an in-memory
  connection: LISTEN/UNLISTEN, dispatch, reconnection, heartbeat, `ready`,
  `close`) and `test/notifications_integration_test.dart` (NOTIFY across
  connections, delivery on COMMIT only, UNLISTEN, reconnection after
  `pg_terminate_backend`, on the four PostgreSQL adapters; MySQL unsupported).
- `test/laravel12_port_test.dart` and
  `test/laravel12_port_integration_test.dart` — SQL of the ported methods and
  live runs of listeners, `pretend`, `whereLike`, `lazyById`/`chunkById`,
  `whereIntegerInRaw` with 70 000 ids, `incrementEach`, `sole`, having
  variants and subqueries on the four PostgreSQL drivers and MariaDB.
- `test/regression_bugs_test.dart` — schema DDL (`compileCreate`,
  `compileAdd`, `compileDrop`, `compileDropIfExists`, previously stubbed to
  `['']`), empty `compileInsert`, `SchemaBuilder._getSchemaName` List/CSV and
  the `wrap()`/`wrapValue()` fast paths.
- `test/doctrine_diff_alter_integration_test.dart` — live introspection, empty
  round-trip diff, type/nullability changes, added/dropped columns
  (PostgreSQL 17).
- `test/mysql_upsert_integration_test.dart` — MySQL UPSERT / `INSERT IGNORE`
  against MariaDB.
- QueryBuilder tests expect `ArgumentError`.
- `dart_test.yaml` pins `concurrency: 1` (as in CI), because the database
  suites share fixtures; integration files are tagged
  `@Tags(['integration'])`, so `dart test -x integration` runs only unit tests.
- CI (`.github/workflows/dart.yml`) also runs on the `performace` branch and
  creates the `dart_test` database.
- `analysis_options.yaml` ignores `unnecessary_import` (tripped by the barrel
  re-exports); unnecessary imports were removed with `dart fix`, and
  `dart analyze lib test` is clean.
- pubspec: `repository`, `issue_tracker`, `documentation` and `topics`, so
  pub.dev links the GitHub repository and issues.
