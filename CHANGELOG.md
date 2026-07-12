## Unreleased (branch `performace`)

### Schema diff → ALTER (Phase 7 — Doctrine loop)

- **Live introspection now works.** Fixed three bugs in
  `PostgreSQLSchemaManager` that made `listTableDetails` throw against a real
  database:
  - `listTableColumns` referenced the non-existent `pg_attrdef.adinhcount`
    (`42703`); removed the bogus predicate.
  - `listTableIndexes` bound a table `oid` back as a parameter
    (`operator does not exist: oid = bytea`); now looks columns up by
    `relname`/`nspname` (text params).
  - `i.indkey` (`int2vector`) decoded as raw bytes; now cast to `::text`.
- The introspection → diff → ALTER pipeline is functional end to end:
  `connection.getDoctrineSchemaManager().listTableDetails(...)` →
  `Comparator().compareTables(...)` / `grammar.getChangedDiff(blueprint, sm)` →
  `SchemaPostgresGrammar.compileTableDiff(diff, blueprint)` → executable
  `ALTER TABLE ...` statements (add/drop/rename/retype/nullable/default,
  indexes, FKs, unique constraints).
- Exported the Doctrine schema classes from the package barrel (`Comparator`,
  `Table`, `Column`, `TableDiff`, `ColumnDiff`, `Index`,
  `ForeignKeyConstraint`, `UniqueConstraint`, `AbstractSchemaManager`).
- Added `analysis_options.yaml` (ignores `unnecessary_import`, which the barrel
  re-export pattern trips) so `dart analyze` is clean.
- Tests: `test/doctrine_diff_alter_integration_test.dart` (live introspection,
  empty round-trip diff, change-type/nullability, add/drop columns) validated
  against PostgreSQL 17.

### Added — PostgreSQL query-builder features (Phase 9)

- **JSON / JSONB:**
  - `whereJsonContains(column, value)` / `orWhereJsonContains` /
    `whereJsonDoesntContain` / `orWhereJsonDoesntContain` →
    `("column")::jsonb @> ?` (value is JSON-encoded and bound).
  - `whereJsonLength(column, operator, value)` / `orWhereJsonLength` →
    `jsonb_array_length(("column")::jsonb) <op> ?`.
  - JSON column access via the `->` selector already worked in `wrap()`
    (`where('meta->name', '=', ...)` → `"meta"->>'name'`); now covered by tests.
- **Full-text search:** `whereFullText(columns, value, {language, mode})` /
  `orWhereFullText` → `to_tsvector(lang, col) [|| ...] @@ <tsquery>(lang, ?)`,
  where `mode` is `plain` (default), `phrase`, or `websearch`.
- **`distinctOn(columns)`** → `SELECT DISTINCT ON (columns) ...`.

  These are implemented in `QueryPostgresGrammar`; the base grammar throws
  `UnsupportedError` for the JSON/full-text predicates on dialects without
  support. Validated with unit tests and live PostgreSQL integration tests.

### Tests / CI

- Added `test/regression_bugs_test.dart` — unit regression guards for the bugs
  fixed on this branch: schema DDL (`compileCreate`/`compileAdd`/`compileDrop`/
  `compileDropIfExists`, previously stubbed to `['']`), `compileInsert` empty
  values (stray `}`), `SchemaBuilder._getSchemaName` List/CSV schema config, and
  the `wrap()`/`wrapValue()` fast paths.
- Added `test/mysql_upsert_integration_test.dart` — validates the MySQL
  UPSERT / `INSERT IGNORE` paths against a live MariaDB.
- Added `dart_test.yaml` pinning `concurrency: 1` (matching CI). The DB
  integration suites share fixtures — the three driver-variant PostgreSQL
  suites reuse the same tables — so parallel file execution collides. Tagged the
  integration test files with `@Tags(['integration'])` (`dart test -x integration`
  runs only the isolated unit tests).
- CI (`.github/workflows/dart.yml`) now also triggers on the `performace`
  branch and creates the `dart_test` PostgreSQL database.

### Performance

- **Query compilation hot path** (~17% faster `toSql()` on a medium query in an
  AOT micro-benchmark, SQL output byte-identical):
  - `compileComponents` and `compileWheres` now dispatch via a direct `switch`
    instead of constructing a `'compile' + ucfirst(...)` / `"where" + type`
    method name and looking it up in a `Map<String,Function>` on every
    component/clause (the string-keyed `_methodMap` is kept for compatibility
    and the `default` fallback).
  - `wrap()` skips the per-call `strtolower` full-string copy (case-insensitive
    `" as "` scan) and adds a fast path for non-dotted identifiers, avoiding
    `explode`/`implode` list allocations.
  - `wrapValue()` only runs the quote-doubling replace when a `"` is present.
  - Added `benchmark/query_compile_benchmark.dart`.

### Added

- **End-to-end migrations** — the migration engine now runs against a live
  database (no code generation; migrations are registered explicitly in a
  `Map<String, Migration Function()>`). `Migrator` injects the
  `DatabaseManager` into each migration so `migration.schema` works;
  migration/seeder classes are exported from the package barrel.
- **Seeders** — `Seeder` base class + `SeederRunner`, with the
  `DatabaseManager` injected so seeders reach the query builder via
  `db!.connection(...).table(...)`. Supports nested `call(otherSeeder)`.
- **Scaffolding CLI** (`bin/eloquent.dart`, `executables: eloquent`):
  `make:migration <name> [--create=<t> | --table=<t>] [--path=]` and
  `make:seeder <ClassName> [--path=]`. File generation only (no code
  generation); running migrations/seeding is driven from the app's explicit
  registry. Fixed the migration stubs to `await` the async `schema` getter.
- **Working schema DDL for PostgreSQL** — implemented the previously-stubbed
  `compileCreate` (CREATE TABLE, with `bigserial primary key` for
  `increments`), `compileAdd` (ALTER TABLE ADD COLUMN), `compileDrop` and
  `compileDropIfExists`.

### Fixed

- `SchemaBuilder` failed when the connection `schema` config was a `List`
  (search path) — `_getSchemaName` now normalizes String/List/CSV to the first
  schema name (previously threw `type 'List<String>' is not a subtype of String?`).
- `DatabaseMigrationRepository.getMigrations(steps)` now selects by *batch*
  (Laravel semantics: one rollback step reverts the whole last batch) instead
  of by row count.
- `DatabaseMigrationRepository._getConnection` no longer dereferences a null
  connection name (falls back to the resolver's default connection).

### Added

- **Direct driver access (`db.driver()` / `queryBuilder.driver()`)** — a typed
  `DriverAccess?` escape hatch beside the query builder for capabilities the SQL
  abstraction cannot express. Returns `null` when unsupported. `dpgsql`
  implementation (`DpgsqlDriverAccess`) provides:
  - `copyInRows(table, columns, rows)` / `copyInRaw(sql, byteStream)` — bulk
    `COPY ... FROM STDIN` (text/raw); far faster than row-by-row inserts.
  - `copyOutText(sql)` — `COPY ... TO STDOUT`.
  - `notify(channel, [payload])` / `listen(channel)` — `LISTEN`/`NOTIFY`.
  - `withRawConnection(action)` — run against the native `DpgsqlConnection`
    (pipelining, batch, large objects, …).
  - `DriverAccess.formatCopyTextRow(...)` — COPY text-format escaping helper.
  Plumbed through `PDOExecutionContext.driverAccess()` and `Connection.driver()`.
- **Server-side streaming / cursor** — `QueryBuilder.cursor([fetchSize])`
  (and its alias `lazy()`) returns a `Stream<Map<String, dynamic>>` backed by
  an incremental reader, keeping memory roughly constant for very large result
  sets (unlike `chunk`/`each`, which page with LIMIT/OFFSET and materialize
  each page). Plumbed through `ConnectionInterface.cursor(...)`,
  `Connection.cursor(...)` and `PDOExecutionContext.queryStream(...)`.
  Implemented for the `dpgsql` adapter (via `executeReader`); other adapters
  throw `UnsupportedError`.

- **`QueryBuilder.upsert(values, uniqueBy, [update])`** — atomic UPSERT.
  PostgreSQL: `INSERT ... ON CONFLICT (uniqueBy) DO UPDATE SET ...`;
  MySQL: `INSERT ... ON DUPLICATE KEY UPDATE ...`. When `update` is omitted,
  all non-`uniqueBy` columns are updated from the would-be-inserted row.
- **`QueryBuilder.insertOrIgnore(values)`** — PostgreSQL `ON CONFLICT DO NOTHING`
  / MySQL `INSERT IGNORE`. Returns the number of rows actually inserted.
- **Low-level fluent conflict API** — `onConflict([columns], [constraint])`,
  `doUpdate(values, [whereRaw])`, `doNothing()`, and `returning([columns])`
  applied to `insert(...)`. Enables lock-free sequence patterns such as:

  ```dart
  final rows = await db.table('processos_sequences')
    .onConflict(['ano'])
    .doUpdate({'last_id': db.raw('processos_sequences.last_id + 1')})
    .returning(['last_id'])
    .insert({'ano': 2026, 'last_id': 1});
  final seq = rows.first['last_id']; // equivalent to PL/pgSQL "RETURNING ... INTO"
  ```

### Fixed

- `QueryPostgresGrammar.compileInsert` emitted a stray `}` for empty inserts
  (`insert into <table>} DEFAULT VALUES`).
- `DargresPDO` now compiles against `dargres` 4.0.0 (immutable `TimeZoneSettings`;
  `PostgreSqlPool` no longer implements `ConnectionInterface`).

### Docs

- Added `docs/PERFORMANCE_REWRITE_PLAN.md` — phased roadmap for the
  performance-focused rewrite.

## 4.0.0

### Breaking changes

- Replaced the public custom `InvalidArgumentException` with Dart's native `ArgumentError`.
- Removed `InvalidArgumentException` from the public API exports in `eloquent.dart`.
- Deleted `lib/src/exceptions/invalid_argument_exception.dart`.
- Updated `QueryBuilder`, `DatabaseManager`, `ConnectionFactory`, and `Container` to throw `ArgumentError`, `ArgumentError.value`, or `ArgumentError.notNull` for invalid arguments.
- External code that previously used `catch (InvalidArgumentException)` should now use `catch (ArgumentError)`.

### Notes

- Internal Doctrine/DBAL compatibility classes named `InvalidArgumentException` remain scoped to `lib/src/doctrine` and are not the removed public Eloquent exception.

### Tests

- Updated QueryBuilder tests to expect `ArgumentError`.
- Verified with `dart analyze lib test\query_builder_where_comparison_test.dart`.
- Verified with `dart test test\query_builder_where_comparison_test.dart test\pg_query_qrammar_test.dart test\query_builder_cte_test.dart`.

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
