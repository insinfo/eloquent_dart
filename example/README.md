# eloquent examples

Each file in `bin/` runs on its own: it creates the tables it needs (named
`ex_*`), prints what it does and drops them at the end.

| File | Shows |
|---|---|
| [getting_started.dart](bin/getting_started.dart) | Connect, create a table with the schema builder, insert, select, update, delete |
| [query_builder.dart](bin/query_builder.dart) | `db.table()`: joins, aggregates, subqueries, `when`, search, offset and keyset pagination, upsert, `ON CONFLICT ... RETURNING`, chunk |
| [query_builder2.dart](bin/query_builder2.dart) | `db.table2()`: typed results, `insertReturning`, `upsert`, `firstOrCreate`, `updateReturning`/`deleteReturning`, recursive CTE |
| [transactions.dart](bin/transactions.dart) | `transaction`, savepoints, `transactionIfNeeded`, `transactionScope`, unique violations, `createOrFirst`, a `SKIP LOCKED` job queue, `nextValue`, advisory locks |
| [active_record.dart](bin/active_record.dart) | Models, casts, `HasOne`/`HasMany`/`BelongsTo`/`BelongsToMany`, eager loading, scopes, soft deletes, observers |
| [repository.dart](bin/repository.dart) | Data Mapper: `EntityMapper` and `Repository` over plain classes |
| [migrations.dart](bin/migrations.dart) | Migrations registered in a map, a non-transactional migration, seeders, rollback, baseline |
| [large_data.dart](bin/large_data.dart) | `copyInto`, `insertUnnest`, `cursor`, `lazyById`, `chunkById`, query listeners |
| [postgres_features.dart](bin/postgres_features.dart) | jsonb, arrays, full-text search, `DISTINCT ON`, LISTEN/NOTIFY |
| [mysql.dart](bin/mysql.dart) | MySQL/MariaDB: joins, upsert, savepoints, `lazyById` |
| [connection_options.dart](bin/connection_options.dart) | Every setting, the four PostgreSQL drivers, pools, named connections |

## Running

The examples connect with the settings in [lib/config.dart](lib/config.dart):
database `banco_teste`, user and password `dart`, PostgreSQL on
`localhost:5432` and MySQL/MariaDB on `localhost:3306` (the same as the
package's tests). Environment variables override them:

```bash
cd example
dart pub get
dart run bin/getting_started.dart

# another PostgreSQL driver: postgres | postgres_v3 (default) | dargres | dpgsql
PG_DRIVER=dpgsql dart run bin/large_data.dart

# another server
PG_HOST=db.local PG_DATABASE=app PG_USERNAME=app PG_PASSWORD=secret \
  dart run bin/query_builder.dart
```

Variables: `PG_HOST`, `PG_PORT`, `PG_DATABASE`, `PG_USERNAME`,
`PG_PASSWORD`, `PG_DRIVER`, `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_DATABASE`,
`MYSQL_USERNAME`, `MYSQL_PASSWORD`.

## In short

```dart
import 'package:eloquent/eloquent.dart';

Future<void> main() async {
  final manager = Manager();
  manager.addConnection({
    'driver': 'pgsql',
    'driver_implementation': 'postgres_v3', // postgres | dargres | dpgsql
    'host': 'localhost',
    'port': '5432',
    'database': 'banco_teste',
    'username': 'dart',
    'password': 'dart',
    'charset': 'utf8',
    'schema': ['public'],
  });
  final db = await manager.connection();

  final id = await db.table('contacts').insertGetId({'name': 'Ana'});
  final rows = await db
      .table('contacts')
      .select(['id', 'name'])
      .where('id', '=', id)
      .get();
  print(rows);

  await db.disconnect();
}
```
