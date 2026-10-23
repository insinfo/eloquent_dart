## 4.0.0

Details and migration notes: [doc/release_notes_4.0.0.md](doc/release_notes_4.0.0.md).

### Breaking changes

- `ConnectionInterface`: `transaction<T>()` is generic, and implementations
  must add `transactionIfNeeded<T>()`, `isInTransaction` and
  `supportsSavepoints`.
- `transaction()` inside a transaction now creates a SAVEPOINT instead of a
  new transaction, and `timeoutInSeconds` is passed to the driver.
- `InvalidArgumentException` replaced by `ArgumentError`.
- Time columns (`timestamp`, `dateTime`, `time` and the `Tz` forms,
  `timestamps()`, `softDeletes()`) have no precision by default
  (`timestamp without time zone`, microseconds on PostgreSQL); they were
  `timestamp(0)`, which rounds the fractions that 4.0 writes to the next
  second. `SchemaBuilder.defaultTimePrecision = 0` restores Laravel's
  default; `precision:` sets one column.
- `Blueprint.toSql` throws for a command that does not compile or is
  unknown (it printed a warning and skipped the DDL).
- `Manager.bootEloquent()` (empty) and `Manager.setFetchMode()` (wrote a
  `database.fetch` setting nothing read) removed.
- `Container` stubs that returned null (`getMethodDependencies`,
  `getCallReflector`, `getDependencies`, `resolveNonClass`, `resolveClass`,
  `keyParametersByArgument`, `getFunctionHint`) and the static
  `Container.object` removed.
- The dargres adapter requires dargres 4.0.1.
- The dpgsql adapter requires dpgsql 1.1.0 (`DpgsqlCommand.simpleQuery`).
- The mysql adapter requires mysql_dart 3.0.3. A DATE/DATETIME that
  `DateTime` cannot represent (the zero date `0000-00-00`, a zero month or
  day, `2024-02-30` under ALLOW_INVALID_DATES) reads as `null`; it came back
  as another day (`0000-00-00` as `-0001-11-30`). `driver_options`
  `zeroDateBehavior: 'exception'` throws instead.
- `where(col, op, null)` with an operator other than `=`, `<>` or `!=` throws
  (it silently became `is not null`); `where(col, value)` means `= value`.
- `value(col)` returns the column value instead of the row; `update()` and
  `ConnectionInterface.update` return `Future<int>`.
- `count()` on grouped/distinct/union queries counts their rows (it returned
  the first group's count); `count('*', CountMode.laravel)` keeps Laravel's
  semantics.
- PostgreSQL `update`/`delete` with a left join and `recursionLimit()` on
  PostgreSQL/MySQL throw instead of producing wrong or ignored SQL.
- PostgreSQL values are the same Dart types on the four adapters
  (`pg_types: 'uniform'`, the default): the types without a natural Dart type
  (`time`, `timetz`, `interval`, `inet`, `cidr`, `macaddr`, geometric types,
  `bit`, `tsvector`, ranges) are the server's text (postgres_fork returned
  `PgTime`, `PgInterval`, `PgInet`, `PgPoint`; postgres_v3 `Time`,
  `Interval`, `IntRange`...; dpgsql `DpgsqlInterval`, `DpgsqlRange`...),
  `money` the decimal amount, arrays `List<T?>`, arrays of user-defined types
  (`enum[]`) the array literal. `pg_types: 'driver'` keeps each driver's
  types. See the release notes.
- A unique violation (PostgreSQL `23505`, MySQL 1062/1586) throws
  `UniqueConstraintViolationException` (a `QueryException` with the driver's
  exception in `previous` and its text in `toString()`) instead of the
  driver's exception; other errors are not wrapped.

### Added

- `pg_types` (`'uniform'` | `'driver'`) and `driver_options` (settings passed
  to the driver; an unknown key throws with the list of known ones) config
  keys; `PDOConfig.fromMap` reads snake_case and camelCase spellings
  (`application_name`/`applicationName`, `poolsize`/`poolSize`,
  `allowreconnect`/`allowReconnect`, `is_unix_socket`/`isUnixSocket`), so
  `PDOConfig.fromMap(config.toMap())` round-trips.
- MySQL `driver_options` `zeroDateBehavior` (`'convertToNull'`, the default,
  or `'exception'`; also the `ZeroDateBehavior` value) for dates `DateTime`
  cannot represent.
- `test/pg_type_parity_integration_test.dart`: ~55 PostgreSQL types read cold,
  warm, in one row and inside a transaction must give the same Dart type and
  value on the four adapters.
- `QueryBuilder2` (`db.table2()`): Dart 3 API with fixed-meaning arguments
  (`where(column, value, {operator})`), `ComparisonOperator`/`SortDirection`
  enums, typed group/join builders, `whereSqlOperator` validated per dialect
  and typed results, `paginate`/`simplePaginate` (`PageResult`),
  `OnConflict`, `insertReturning`/`updateReturning`/`deleteReturning`,
  `upsert`, `insertOrIgnore`, `union` and (recursive) CTEs; compiled by the
  existing grammars.
- `datetime_bindings: 'native'` sends DateTime bindings to the driver
  unchanged (microseconds kept, correct instant for `timestamptz`); the
  default `'string'` keeps Laravel's `yyyy-MM-dd HH:mm:ss` formatting.
- PostgreSQL, `datetime_bindings: 'string'` (default): a DateTime with
  fractional seconds keeps them (`2024-03-10 12:34:56.789123`; 10:20:30.123
  was stored as 10:20:30). Whole seconds are formatted as before. MySQL keeps
  whole seconds (its `DATETIME` would round a fraction instead of truncating
  it). New `Grammar.formatDateTime`, also used by `toRawSql()`.
- PostgreSQL LISTEN/NOTIFY on every PostgreSQL adapter: `db.notify()`
  (transactional, via `pg_notify`), `db.notifications(channel)` and
  `PostgresNotificationListener` (one dedicated connection, reconnection,
  heartbeat, `ready()`, `onReconnect`).
- Nested transactions via SAVEPOINT, `transactionIfNeeded()`,
  `isInTransaction` and a real `transactionLevel()` (issue #6).
- Row locks: `lockForUpdate({skipLocked, noWait, of})`, `sharedLock(...)`,
  `skipLocked()`, `noWait()`.
- `groupByRaw(sql, bindings)`; `groupBy` accepts `db.raw(...)` (it was
  silently ignored) and rejects other values.
- `upsert()`, `insertOrIgnore()`, `onConflict()`/`doUpdate()`/`doNothing()`
  and `returning()`.
- PostgreSQL JSON, full-text, `distinctOn()` and array operators
  (`whereArrayContains`, `whereArrayContainedBy`, `whereArrayOverlaps`).
- `cursor()`/`lazy()` streaming and `driver()` access (COPY, LISTEN/NOTIFY)
  for dpgsql.
- Migrations, seeders and CLI (`make:migration`, `make:seeder`,
  `schema:diff`); transactional migrations.
- Working schema introspection and diff → `ALTER TABLE` for PostgreSQL.
- Doctrine schema port completed: `Schema.toSql()`/`toDropSql()`,
  `PostgreSQLPlatform`, `MySQLPlatform`, `MariaDBPlatform`
  (`db.getDatabasePlatform()`), `Comparator.compareSchemas()` +
  `getAlterSchemaSQL()`, `introspectSchema()`, namespaces, MATCH/DEFERRABLE
  foreign keys, UNLOGGED tables.
- ORM without code generation or reflection, in two styles: Active Record
  (`Model<T>` with plain fields, `toMap()`/`fill()` and `modelDefinition`;
  or `AttributeModel<T>` with the columns in a map and typed getters/setters;
  `ModelDefinition` with `fillable` (`assign()`), `hidden` (`toJson()`) and
  `insertNulls`,
  `ModelQuery`, casts, `save()` of the changed
  columns, `HasOne`/`HasMany`/`BelongsTo`/`BelongsToMany`,
  `latestOfMany`/`ofMany`, eager loading in batches, global and local scopes,
  soft deletes, observers) and Data Mapper (`Repository<T>`,
  `EntityMapper<T>`).
- `DargresPDO` applies `search_path`, encoding, time zone, application name
  and timeouts like the postgres_fork adapter; `numeric` as exact `String`.
- pubspec `repository`, `issue_tracker`, `documentation` and `topics`.
- From Laravel 12: `db.listen()`, `onSlowQuery()`, `totalQueryDuration()`
  and the `QueryExecuted` event; `toRawSql()`/`dumpRawSql()`; `when()`,
  `unless()`, `tap()`; `whereAny`/`whereAll`/`whereNone`/`whereNot`;
  `whereLike` (case-insensitive by default); `orderByDesc`, `reorder` and
  `orderBy` with a subquery; `select`/`addSelect` with subqueries,
  `fromSub`, `leftJoinSub`/`rightJoinSub`/`crossJoinSub`; `lazyById`,
  `eachById`, `chunkByIdDesc`, `chunkMap`; `sole`, `soleValue`,
  `firstOrFail`, `findOr`, `doesntExist`, `existsOr`; `havingBetween`,
  `havingNull`, nested `having`; `whereIntegerInRaw` (no 65535 parameter
  limit); `incrementEach`/`decrementEach`; MySQL `whereFullText`.
- `db.transactionScope((ctx) ...)`: an ambient transaction; inside it, code
  that uses `db` (a repository called from the callback) runs in the same
  transaction instead of another pooled connection (or waiting forever on a
  single connection), `db.transaction` becomes a SAVEPOINT and
  `db.isInTransaction` is true. `db.outsideTransaction(...)` leaves the scope
  on purpose (needs a pool); `isInTransactionScope`.
- Search and filters: `whereSearch(columns, term, {match, unaccent,
  everyWord})` (the term matched literally: `%`/`_` escaped; a null or blank
  term adds nothing), `whereAnyLike`, `unaccent: true` on `whereLike`
  (PostgreSQL `unaccent(col::text) ilike unaccent(?)`,
  `QueryPostgresGrammar.unaccentFunction`), `lower: true` (`lower(col) like
  lower(?)`, for expression indexes and case-sensitive MySQL collations),
  `QueryBuilder.escapeLike` and
  `likePattern`; `orderByInput(field, direction, allowed: {...}, fallback:)`
  orders by a client parameter through an allow-list.
- `whereInTuple`/`whereNotInTuple` (`(a, b) in ((?, ?), ...)`),
  `whereRowValues` (`(a, b) > (?, ?)`), `whereAnyArray`/`whereNotAnyArray`
  (`col = any(?)` with one array parameter, `in (...)` on MySQL),
  `whereBetweenColumns`, `whereValueBetween`.
- Migrations: `Migrator.runPending()` (the registered migrations not run
  yet, from the registry alone, so it works in an AOT build) and
  `pending()`; `markAsRan()` (baseline of an existing database);
  `Migrator.isolated` (default on PostgreSQL: each migration takes an
  advisory lock and checks the log again, so concurrent deploys apply it
  once); the log is written in the migration's transaction
  (`transactionScope`), so a failure rolls both back;
  `Migration.connection` and `Migration.statement(sql)` for raw SQL; the
  migration table gets an `id` primary key.
- PostgreSQL column comments (`comment(...)`) become `COMMENT ON COLUMN`
  (they were ignored); MySQL time columns take `precision:` (`datetime(3)`).
- `cursorPaginate()` (keyset pagination with opaque cursors, `CursorPage`),
  `paginateWithWindowCount()` (opt-in one-query pagination with
  `count(*) over ()`), `explain({analyze})`, `afterQuery(callback)`,
  `updateFrom()`.
- Bulk: `copyInto(rows)` (COPY on dpgsql, multi-row INSERTs elsewhere),
  `insertUnnest(rows, types:)` (`insert ... select * from unnest(?::int[],
  ...)`, PostgreSQL); `nextValue(column)` (max + 1 per scope under
  `pg_advisory_xact_lock`).
- `cursor()` on every PostgreSQL adapter: the adapters without an
  incremental reader use an SQL cursor (`DECLARE ... FETCH` in a
  transaction); `PDOExecutionContext.supportsQueryStream`.
- `QueryBuilder2`: `whereAny`/`whereAll`/`whereNone`, `whereDate`/`Time`/
  `Day`/`Month`/`Year`, JSON (`whereJsonContains`, `whereJsonLength`),
  arrays (`whereArray`), `whereFullText`, `distinctOn`, `joinSub`,
  `joinLateral`/`leftJoinLateral`, `latest`/`oldest`/`inRandomOrder`,
- `db.unprepared(sql)` and `db.execute(sql)` (Laravel's `DB::unprepared`,
  PHP's `PDO::exec`) use the simple query protocol on the four PostgreSQL
  adapters, so a script with several statements, dollar-quoted bodies and
  its own `BEGIN`/`COMMIT` runs the same everywhere; postgres_v3 and dpgsql
  sent it through the extended protocol, which refuses more than one
  statement (42601). Queries with bindings keep the extended protocol.
- `UniqueConstraintViolationException` (Laravel 10+) with the violated
  `constraint`, on the five adapters, also when it ends a transaction on
  postgres/postgres_v3. `createOrFirst()`/`firstOrCreate()` (insert or return
  the row a unique index already has; `on conflict do nothing returning *` on
  PostgreSQL, so a surrounding transaction stays usable).
- PostgreSQL locks: `db.advisoryLock(key)`/`db.tryAdvisoryLock(key)`
  (`pg_advisory_xact_lock`, held until the transaction ends) and
  `lockTable(TableLockMode, {noWait})` (`LOCK TABLE`, mode from an enum).
  `cursor`, `chunk`, `chunkById`, `insertUsing`, `firstOrFail`,
  `createOrFirst`, `firstOrCreate`, `lockTable`, and every item above.

### Fixed

- A connection the server closed for being idle was not always seen as lost:
  PostgreSQL 14+ `idle_session_timeout` (SQLSTATE 57P05, "terminating
  connection due to idle-session timeout") made every later query fail on
  dargres; it reconnects, as MySQL/MariaDB `wait_timeout` already did
  (issue #2). Tested on every adapter, with and without a pool.
- postgres (postgres_fork): an SQL error inside a nested `transaction()`
  (SAVEPOINT) rolled back the whole transaction, as the driver did not know
  a savepoint was active; nested transactions use the driver's own
  `savepoint()` (also through the pool), so the error rolls back to the
  savepoint and the outer transaction goes on, as on dargres, dpgsql and
  MySQL. New `PDOExecutionContext.runInSavepoint` for such drivers.
- `unprepared()` in `pretend()` threw a `TypeError` (it returned `true` as
  the affected rows); it returns 0.
- MySQL `increments()` in a create or add failed with error 1075 (the
  auto_increment column was not declared a key); it is `primary key` inline,
  as in Laravel.
- `Manager.connection()`, `table()` and `schema()` used the global instance
  (`instance!`), so they failed with a null check without `setAsGlobal()`;
  they use the manager they are called on.
- IoC `Container`: factories were called with the wrong arguments (every
  closure binding failed); they are called with `()`, `(container)` or
  `(container, parameters)`. `extend`, `rebinding`, contextual bindings
  (`when().needs().give()`, which also passed a method instead of the
  abstract) and `[]=` with a value crashed; `share` cached one value for all
  closures; `make` of an unknown type crashed with `NoSuchMethodError`
  (`BindingResolutionException` now); a binding to another name threw
  `UnimplementedError`; `resolving`/`afterResolving` did nothing; empty
  list/map instances were not `bound`; `call`/`wrap` passed `null` instead
  of the parameters; `refresh` and `Class@method` throw `UnsupportedError`
  (they need reflection).
- dpgsql: `EXPLAIN`, `VALUES`, `TABLE`, `FETCH` and parenthesized `SELECT`s
  returned no rows (they were run as statements without a result).
- postgres_v3: `inet`, `cidr`, `macaddr` and `oid` came back as garbage
  strings (binary bytes decoded as text) and `money`, `timetz`, `bit`,
  `regclass`, `enum[]` and arrays of `numeric`, `money` and `interval` threw
  `FormatException`.
- postgres_fork: `driver_options` `queryTimeoutInSeconds` (or the pool's
  `queryTimeout`) is the default per-query timeout; each query passed its own
  30 s, so the connection's default never applied. Same for postgres_v3
  `queryTimeout` and dargres `commandTimeout` (pool).
- dpgsql: a statement on a connection the server closed is detected as a lost
  connection and retried on a new one (dpgsql 1.0.3 reports it as "the
  connection to the server was lost").
- Query builder: `groupBy(raw)` ignored, `whereIn([])`, `exists()` read connection, `union(Function)`,
  `updateOrInsert`, `clone()`, `paginate` side effects, builder left without
  orders/limit after a failed count.
- PostgreSQL: `delete` with joins (`USING`), `update`/`delete` with `limit`
  (`ctid`), CTEs in `update`/`delete`, update binding order.
- MySQL: CTEs in `select`/`update`/`delete`; session settings (`set names`,
  `time_zone`, `sql_mode`) on every pool connection.
- Timeouts: forwarded by `get`/`insert`/`update`/`delete`/`selectOne`; session
  timeouts on postgres_v3 and MySQL; snake_case timeout keys; per-call
  timeouts on dargres without pool; dpgsql cancels timed-out commands and
  replaces the connection.
- dpgsql: affected rows of `WITH ... UPDATE/DELETE`.
- MySQL: `exists()` was always false (`1 == true`), so `updateOrInsert`
  always inserted.
- `whereColumn([...])` bound the second column as a value.
- MySQL `insertGetId` could return another request's id (a separate
  `SELECT LAST_INSERT_ID()` ran on another pooled connection, or after
  another caller's insert); the id now comes with the INSERT result
  (`PDOResults.insertId`).
- postgres_v3 and dargres without pool: a request that arrived during
  another one's transaction failed; callers of the single connection are
  serialized, like dpgsql and MySQL.
- dpgsql: `numeric` comes back as the exact server text (`'150.50'`), as
  on postgres, postgres_v3 and dargres; it was a `double` (`150.5`, digits
  lost beyond ~15). Uses dpgsql 1.0.3's `Decode Numeric As String`.
- dpgsql single connection: transactions run through
  `DpgsqlConnection.runInTransaction` (dpgsql 1.0.3), which keeps other
  callers' commands out of them even without the adapter's lock.
- `union` + `orderByRaw` with bindings emitted them before the union parts'
  bindings; pagination counts of a union kept its limit.
- MySQL `onConflict()` emitted PostgreSQL's `on conflict`; it is compiled as
  `on duplicate key update`.
- Lost connections: dpgsql and MySQL without pool were not detected (every
  later query failed); detection now uses the error codes and the messages
  of each adapter, without matching data such as a CEP.
- Migrations: `foreign()` produced no SQL (PostgreSQL and MySQL),
  `schema.create()` ran an empty query on MySQL, and `dropColumn()`,
  `dropForeign()` and `rename()` produced no SQL on PostgreSQL;
  `deferrable()`/`initiallyDeferred()` are compiled on PostgreSQL.
- Doctrine `Table.addForeignKey()` always threw; `renameColumn()` updates
  indexes, unique constraints and foreign keys.
- `where`/`having` with a `List` value (`Uint8List`, PostgreSQL array, JSON)
  spread it into several bindings for one placeholder.
- `pretend()` returned before an async callback ran (empty log) and ran
  `select`s for real; it now awaits the callback and restores the log.
- `chunkById` reused the same builder between pages and did not detect a
  missing id column.
- PostgreSQL `whereFullText` validates the language (it is inlined in SQL).
- dpgsql and MySQL without pool serialize concurrent callers of the single
  connection, like the other adapters (they failed with "connection is busy").
- postgres_fork: same duplicate-column mapping inside transactions.
- `prepareBindings` no longer modifies the caller's list; lost-connection
  retry loop; `getConfig()`; driver extensions lookup.
- Empty insert SQL, `List` schema config, migration batches and rollback,
  PostgreSQL and MySQL introspection, `ColumnDiff` comparison.

### Performance

- About 17% faster `toSql()` (direct dispatch and `wrap()` fast paths) and no
  per-query column copy in `get()`.

## 3.4.3

- add Postgres whereExists integration test, expand whereExists docs, and include README example for QueryBuilder subquery usage

## 3.4.2

- implemented `insertMany` to execute an optimized "batch insert", generating a single SQL statement

## 3.4.0

- upgrade mysql_dart to 1.2.0 for fix textual BLOB/TEXT columns are decoded as UTF‑8 strings consistently

## 3.3.2

### Added

- **`JoinClause.onRaw(String sql, [String boolean = 'and', List bindings = const []])`** — Allows raw SQL fragments inside `JOIN ... ON` conditions. Use the optional `boolean` to chain with `AND`/`OR` and `bindings` to safely pass parameters that will be appended to the join bindings.

  **Examples**
  ```dart
  // Simple raw predicate (defaults to boolean = 'and' and no bindings)
  db.table('processes')
    .join('listings as l', (JoinClause jc) {
      jc.on('l.process_id', '=', 'processes.id');
      jc.onRaw("l.state IN ('open','running')");
    })
    .get();

  // Raw predicate with OR and parameter bindings
  db.table('tickets as t')
    .join('labels as l', (JoinClause jc) {
      jc.on('l.ticket_id', '=', 't.id');
      jc.onRaw('l.tags @> ARRAY[?]::text[]', 'or', ['urgent']); // adds to join bindings
    })
    .get();
  ```

- **`QueryBuilder.clone()`** — Creates a deep, independent copy of a query builder (including selects, joins, wheres, orders, and bindings). Modifying the clone does not affect the original, which is handy for deriving variations from a base query.

  **Example**
  ```dart
  // 1) Base query for active users
  final baseQuery = db.table('users').where('status', '=', 'active');

  // 2) Independent clones
  final usersCountQuery = baseQuery.clone();
  final firstUserQuery = baseQuery.clone();

  // 3) Different uses
  final totalActiveUsers = await usersCountQuery.count();
  final firstUser = await firstUserQuery.orderBy('created_at').first();

  // Original remains reusable
  final allActiveUsers = await baseQuery.get();
  ```

- **`QueryBuilder.joinRaw(String tableExpression, [List bindings = const [], String type = 'inner', Function(JoinClause)? on])`** — Adds a `JOIN` using a **raw table/Expression** (kept unwrapped), optional parameter `bindings` for that expression, an optional join `type` (default `inner`), and an optional `on` callback to configure `ON` conditions (including `onRaw`).

  **Examples**
  ```dart
  // 1) Join a subquery with bindings and configure ON via callback
  final since = DateTime.now().subtract(const Duration(days: 30));
  db.table('orders')
    .joinRaw(
      '(select * from invoices where created_at >= ?) as i',
      [since],                         // bindings for the tableExpression
      'left',
      (JoinClause jc) {                // ON configuration
        jc.on('i.order_id', '=', 'orders.id');
        jc.onRaw('i.status IN (?, ?)', 'and', ['paid', 'settled']);
      },
    )
    .get();

  // 2) Join a raw expression without ON (e.g., NATURAL or ON TRUE)
  db.table('metrics')
    .joinRaw('generate_series(1, 10) as g')
    .get();
  ```

### Tests

- Expanded Postgres pool v2 coverage: concurrency limits (server‑measured), `SET LOCAL` scoping, `lock_timeout` behavior, connection reuse, and PID churn after `purge()`.

## 3.3.1

- fix bug on PgPool for PostgresV2PDO

## 3.3.0

- add option to decode timestamp without timezone and date as local DateTime and decode timestamp with timezone respecting the timezone defined in the connection for driver_implementation postgres

- update postgres_v3 to  ^3.5.4 With that dependency, upgraded minimum SDK to 3.4
- change mysql_client to mysql_dart ^1.0.0
- change postgres_fork ^2.8.4 to postgres_fork ^2.8.5

```dart
 final manager = Manager();
  manager.addConnection({
    'driver': 'pgsql',
    'driver_implementation': 'postgres_v3', // postgres | dargres | postgres_v3
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
    'pool': true,
    'poolsize': 2,
    'host': 'localhost',
    'port': '5435',
    'database': 'siamweb',
    'username': 'dart',
    'password': 'dart',
    'charset': 'win1252',
    'prefix': '',
    'schema': ['public'],
    // require | disable
    //'sslmode' : 'require',
  });
```

## 3.2.1

- fix bug on format Schema

## 3.2.0

- fix bugs in onOpen callback to configure connection settings
- improvements to README
- implemented connection pool for 'postgres' (v2) driver_implementation

## 3.1.2

- fix bugs in lost connection detection to automatically reconnect. Updated postgres to 3.1.2 to be able to use the onOpen callback to configure connection settings like setting search path

## 3.0.1

- fix bug on query builder count()

## 3.0.0

- implemented support for mysql through the 'mysql_client' package and also implemented support for posgress with the postgres v3 package, now you can choose the driver implementation through ``` 'driver_implementation': 'postgres_v3', ``` in addConnection method

## 2.2.0

- add fromRaw (sub-query as from), joinSub (method to join a query to a sub-query)

## 2.1.2

- remove print from disconnect() in Connection class

## 2.1.1

- small improvement and optimization in postgres PDO implementation

## 2.1.0

- change dependencie postgres to my fork postgres_fork
- add more tests

## 2.0.2

- add support to postgres driver https://github.com/insinfo/postgresql-dart-1.git
- type correction and other improvements

## 2.0.2

- fix bug on set application_name to postgresql < 8.2

## 2.0.1

- fixes critical bug in version 2.0.0 that caused stack overflow, timeout parameters were removed from query execution methods

## 2.0.0

- implemented Connection pool with option to automatically reconnect in case of connection drop
```dart
final manager = Manager();
  manager.addConnection({
    'driver': 'pgsql',
    'host': 'localhost',
    'port': '5432',
    'database': 'database',
    'username': 'username',
    'password': 'password',
    'charset': 'latin1',  
    'schema': ['public'],
    'pool': true, //new
    'poolsize': 2, //new
    'allowreconnect': true, //new   
  });

```

## 1.2.1

- fix parameter type of column orWhere

## 1.2.0

- fix bugs and update dargres to 2.2.4

## 1.1.1

- fix bugs on detects_lost_connections

## 1.1.0

- implemented tryAgainIfCausedByLostConnection

## 1.0.0

- Initial version
