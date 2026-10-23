// Connection settings shared by the examples in bin/.
//
// The defaults match the package's integration tests: database `banco_teste`,
// user and password `dart`, PostgreSQL on 5432 and MySQL/MariaDB on 3306.
// Environment variables override them:
//
//   PG_HOST, PG_PORT, PG_DATABASE, PG_USERNAME, PG_PASSWORD
//   PG_DRIVER    postgres | postgres_v3 (default) | dargres | dpgsql
//   MYSQL_HOST, MYSQL_PORT, MYSQL_DATABASE, MYSQL_USERNAME, MYSQL_PASSWORD
import 'dart:io';

import 'package:eloquent/eloquent.dart';

String _env(String name, String fallback) =>
    Platform.environment[name] ?? fallback;

/// PostgreSQL settings; [driver] overrides `PG_DRIVER`.
Map<String, dynamic> postgresConfig({String? driver}) => {
      'driver': 'pgsql',
      'driver_implementation': driver ?? _env('PG_DRIVER', 'postgres_v3'),
      'host': _env('PG_HOST', 'localhost'),
      'port': _env('PG_PORT', '5432'),
      'database': _env('PG_DATABASE', 'banco_teste'),
      'username': _env('PG_USERNAME', 'dart'),
      'password': _env('PG_PASSWORD', 'dart'),
      'charset': 'utf8',
      'prefix': '',
      'schema': ['public'],
    };

/// MySQL/MariaDB settings.
Map<String, dynamic> mysqlConfig() => {
      'driver': 'mysql',
      'host': _env('MYSQL_HOST', 'localhost'),
      'port': _env('MYSQL_PORT', '3306'),
      'database': _env('MYSQL_DATABASE', 'banco_teste'),
      'username': _env('MYSQL_USERNAME', 'dart'),
      'password': _env('MYSQL_PASSWORD', 'dart'),
    };

/// A [Manager] with [postgresConfig] as its default connection.
Manager postgresManager({String? driver}) =>
    Manager()..addConnection(postgresConfig(driver: driver));
