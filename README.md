# eloquent
[![CI](https://github.com/insinfo/eloquent_dart/actions/workflows/dart.yml/badge.svg)](https://github.com/insinfo/eloquent_dart/actions/workflows/dart.yml)
[![Pub Package](https://img.shields.io/pub/v/eloquent.svg)](https://pub.dev/packages/eloquent)  


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

## Creating a connection executing insert/update/delete
```dart
   
    await db.table('temp_location')
        .insert({'id': 1, 'city': 'Rio de Janeiro', 'street': 'Rua R'});

    await db.table('temp_location')
        .where('id', '=', 1).update({'city': 'Teresopolis'});

    await db.table('temp_location')
        .where('id', '=', 1).delete();

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