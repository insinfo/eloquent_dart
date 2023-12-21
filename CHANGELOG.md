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