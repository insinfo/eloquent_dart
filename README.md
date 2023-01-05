# eloquent
[![CI](https://github.com/insinfo/eloquent_dart/actions/workflows/dart.yml/badge.svg)](https://github.com/insinfo/eloquent_dart/actions/workflows/dart.yml)
[![Pub Package](https://img.shields.io/pub/v/eloquent.svg)](https://pub.dev/packages/eloquent)  

this work is still in an initial state

eloquent 5.2 query builder port from PHP Laravel to dart

https://laravel.com/docs/5.2/queries

for now it only works with PostgreSQL


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
      'schema': ['public'],      
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