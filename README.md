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

## Lightweight ORM (Repository, no code generation)

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

## PostgreSQL DateTime bindings

Eloquent normalizes query bindings before the PDO driver receives them. For `DateTime` values, `Connection.prepareBindings()` formats the value with the PostgreSQL grammar date format (`yyyy-MM-dd HH:mm:ss`). This matches the Laravel/PDO style used by the existing PostgreSQL adapters.

`lib/src/pdo/postgres/postgres_pdo.dart` does not perform this conversion itself. It receives the already prepared bindings and passes them to `postgresql-fork` as substitution values.

This distinction matters for `timestamp without time zone`: application code usually expects a civil/local timestamp to round-trip as the same wall-clock time. For example, `2026-06-27 00:43:00` should not become `2026-06-27 03:43:00` just because the driver encoded a Dart `DateTime` through UTC binary timestamp semantics.

When using:

```dart
manager.addConnection({
  'driver': 'pgsql',
  'driver_implementation': 'dpgsql',
  'timezone': 'America/Sao_Paulo',
});
```

the `dpgsql` adapter preserves the same compatibility rule: untyped `DateTime` query builder bindings are sent as PostgreSQL-inferred text/unknown values, so the target column decides whether the value is `timestamp`, `timestamptz`, or `date`. This avoids timezone shifts in systems that store local timestamps in `timestamp without time zone` columns.

The `timezone` setting still configures the PostgreSQL session timezone. Decode flags such as `forceDecodeTimestampAsUTC`, `forceDecodeTimestamptzAsUTC`, and `forceDecodeDateAsUTC` control how returned values are materialized in Dart; they are separate from the query-builder binding normalization described above.

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
