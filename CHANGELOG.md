## 1.0.0

- Initial version

## 1.1.0

- implemented tryAgainIfCausedByLostConnection

## 1.1.1

- fix bugs on detects_lost_connections

## 1.2.0

- fix bugs and update dargres to 2.2.4

## 1.2.1

- fix parameter type of column orWhere

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

## 2.0.1

- fixes critical bug in version 2.0.0 that caused stack overflow, timeout parameters were removed from query execution methods


## 2.0.2

- fix bug on set application_name to postgresql < 8.2  

## 2.0.2

- add support to postgres driver https://github.com/insinfo/postgresql-dart-1.git
- type correction and other improvements

## 2.1.0

- change dependencie postgres to my fork postgres_fork
- add more tests

## 2.1.1

- small improvement and optimization in postgres PDO implementation

## 2.1.2

- remove print from disconnect() in Connection class

## 2.2.0

- add fromRaw (sub-query as from), joinSub (method to join a query to a sub-query)

## 3.0.0

- implemented support for mysql through the 'mysql_client' package and also implemented support for posgress with the postgres v3 package, now you can choose the driver implementation through ``` 'driver_implementation': 'postgres_v3', ``` in addConnection method

## 3.0.1

- fix bug on query builder count() 

## 3.1.2

- fix bugs in lost connection detection to automatically reconnect. Updated postgres to 3.1.2 to be able to use the onOpen callback to configure connection settings like setting search path

## 3.2.0

- fix bugs in onOpen callback to configure connection settings
- improvements to README
- implemented connection pool for 'postgres' (v2) driver_implementation

## 3.2.1

- fix bug on format Schema

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

## 3.3.1

- fix bug on PgPool for PostgresV2PDO

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


## 3.4.0

- upgrade mysql_dart to 1.2.0 for fix textual BLOB/TEXT columns are decoded as UTF‑8 strings consistently 

## 3.4.2

- implemented `insertMany` to execute an optimized "batch insert", generating a single SQL statement