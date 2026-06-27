import 'dart:convert';
import 'dart:io';

import 'package:eloquent/eloquent.dart';

const _allDrivers = <_DriverSpec>[
  _DriverSpec(
    name: 'postgres_fork',
    implementation: 'postgres',
    dependency: 'postgres_fork ^2.8.5',
  ),
  _DriverSpec(
    name: 'postgres',
    implementation: 'postgres_v3',
    dependency: 'postgres ^3.5.4',
  ),
  _DriverSpec(
    name: 'dargres',
    implementation: 'dargres',
    dependency: 'dargres ^3.1.2',
  ),
  _DriverSpec(
    name: 'dpgsql',
    implementation: 'dpgsql',
    dependency: 'dpgsql path ../dpgsql',
  ),
];

Future<void> main(List<String> args) async {
  final config = _BenchmarkConfig.fromEnvironment();
  final selectedDrivers = _selectedDrivers(config.driverFilter);
  final results = <Map<String, Object?>>[];

  for (final driver in selectedDrivers) {
    stdout.writeln('Running ${driver.name} (${driver.implementation})...');
    results.add(await _runDriverBenchmark(driver, config));
  }

  final report = <String, Object?>{
    'environment': config.toJson(),
    'drivers': results,
  };

  stdout.writeln('');
  _printSummary(results);
  stdout.writeln('');
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
}

List<_DriverSpec> _selectedDrivers(String? filter) {
  if (filter == null || filter.trim().isEmpty) {
    return _allDrivers;
  }

  final requested = filter
      .split(',')
      .map((item) => item.trim().toLowerCase())
      .where((item) => item.isNotEmpty)
      .toSet();

  final selected = _allDrivers
      .where((driver) =>
          requested.contains(driver.name.toLowerCase()) ||
          requested.contains(driver.implementation.toLowerCase()))
      .toList();

  if (selected.isEmpty) {
    throw ArgumentError.value(filter, 'PG_BENCH_DRIVERS');
  }

  return selected;
}

Future<Map<String, Object?>> _runDriverBenchmark(
  _DriverSpec driver,
  _BenchmarkConfig config,
) async {
  final manager = Manager();
  final table = _tableName(config.tablePrefix, driver.implementation);
  final connectWatch = Stopwatch()..start();
  late Connection db;

  try {
    manager.addConnection({
      'driver': 'pgsql',
      'driver_implementation': driver.implementation,
      'host': config.host,
      'port': config.port.toString(),
      'database': config.database,
      'username': config.username,
      'password': config.password,
      'charset': config.charset,
      'prefix': '',
      'schema': [config.schema],
      'pool': config.pool,
      'poolsize': config.poolSize,
      'timezone': config.timezone,
      'application_name': 'eloquent-pg-benchmark-${driver.implementation}',
      'statementTimeout': config.statementTimeout,
      'lockTimeout': config.lockTimeout,
      'idleInTransactionSessionTimeout': config.idleInTransactionSessionTimeout,
    });
    manager.setAsGlobal();
    db = await manager.connection();
    connectWatch.stop();

    final setupMs = await _timeMs(() async {
      await db.execute('DROP TABLE IF EXISTS $table');
      await db.execute('''
        CREATE TABLE $table (
          id int primary key,
          name text not null,
          score int not null,
          created_at timestamp not null
        )
      ''');
    });

    await _warmup(db, table, config.warmupIterations);
    await db.execute('TRUNCATE TABLE $table');

    final scalar = await _measureScalarSelects(db, config.iterations);
    final insert = await _measureInserts(db, table, config.iterations);
    final selectById = await _measureSelectById(db, table, config.iterations);
    final transaction = await _measureTransactionInserts(
      db,
      table,
      config.iterations,
      config.transactionIterations,
    );
    final resultSet = await _measureResultSet(
      db,
      table,
      config.resultRows,
    );

    final totalMs =
        scalar.ms + insert.ms + selectById.ms + transaction.ms + resultSet.ms;
    final totalOps = scalar.operations +
        insert.operations +
        selectById.operations +
        transaction.operations +
        resultSet.operations;

    return {
      'driver': driver.name,
      'driver_implementation': driver.implementation,
      'dependency': driver.dependency,
      'pool': config.pool,
      'poolsize': config.poolSize,
      'connect_ms': _roundMs(connectWatch.elapsedMicroseconds),
      'setup_ms': setupMs,
      'scalar_select': scalar.toJson(),
      'insert': insert.toJson(),
      'select_by_id': selectById.toJson(),
      'transaction_insert': transaction.toJson(),
      'result_set': resultSet.toJson(),
      'total_measured_ms': _roundDouble(totalMs),
      'total_ops_per_second': _opsPerSecond(totalOps, totalMs),
    };
  } catch (error, stackTrace) {
    connectWatch.stop();
    return {
      'driver': driver.name,
      'driver_implementation': driver.implementation,
      'dependency': driver.dependency,
      'pool': config.pool,
      'poolsize': config.poolSize,
      'connect_ms': _roundMs(connectWatch.elapsedMicroseconds),
      'error': error.toString(),
      'stack': stackTrace.toString().split('\n').take(8).join('\n'),
    };
  } finally {
    try {
      if (connectWatch.isRunning) {
        connectWatch.stop();
      }
      await db.execute('DROP TABLE IF EXISTS $table');
    } catch (_) {}
    try {
      await manager.getDatabaseManager().purge('default');
    } catch (_) {}
  }
}

Future<void> _warmup(
  Connection db,
  String table,
  int warmupIterations,
) async {
  for (var i = 0; i < warmupIterations; i++) {
    await db.select('SELECT ?::int AS value', [i], false);
  }
  await db.table(table).insert({
    'id': -1,
    'name': 'warmup',
    'score': 0,
    'created_at': DateTime(2024, 1, 1),
  });
  await db.table(table).where('id', '=', -1).first();
}

Future<_Measurement> _measureScalarSelects(
  Connection db,
  int iterations,
) async {
  var checksum = 0;
  final ms = await _timeMs(() async {
    for (var i = 0; i < iterations; i++) {
      final rows = await db.select('SELECT ?::int AS value', [i], false);
      checksum += rows.first['value'] as int;
    }
  });

  return _Measurement(
    operations: iterations,
    ms: ms,
    checksum: checksum,
  );
}

Future<_Measurement> _measureInserts(
  Connection db,
  String table,
  int iterations,
) async {
  final ms = await _timeMs(() async {
    for (var i = 0; i < iterations; i++) {
      await db.table(table).insert({
        'id': i + 1,
        'name': 'client_$i',
        'score': i,
        'created_at': DateTime(2024, 1, 1, 0, 0, i % 60),
      });
    }
  });

  return _Measurement(operations: iterations, ms: ms);
}

Future<_Measurement> _measureSelectById(
  Connection db,
  String table,
  int iterations,
) async {
  var checksum = 0;
  final ms = await _timeMs(() async {
    for (var i = 0; i < iterations; i++) {
      final row = await db.table(table).where('id', '=', i + 1).first();
      checksum += row?['score'] as int;
    }
  });

  return _Measurement(
    operations: iterations,
    ms: ms,
    checksum: checksum,
  );
}

Future<_Measurement> _measureTransactionInserts(
  Connection db,
  String table,
  int baseId,
  int iterations,
) async {
  final ms = await _timeMs(() async {
    await db.transaction((ctx) async {
      for (var i = 0; i < iterations; i++) {
        await ctx.table(table).insert({
          'id': baseId + i + 1,
          'name': 'tx_client_$i',
          'score': baseId + i,
          'created_at': DateTime(2024, 1, 2, 0, 0, i % 60),
        });
      }
    });
  });

  return _Measurement(operations: iterations, ms: ms);
}

Future<_Measurement> _measureResultSet(
  Connection db,
  String table,
  int rows,
) async {
  var checksum = 0;
  final ms = await _timeMs(() async {
    final result = await db
        .table(table)
        .select(['id', 'score', 'name'])
        .orderBy('id', 'asc')
        .limit(rows)
        .get();

    for (final row in result) {
      checksum += row['score'] as int;
    }
  });

  return _Measurement(
    operations: rows,
    ms: ms,
    checksum: checksum,
  );
}

Future<double> _timeMs(Future<void> Function() callback) async {
  final watch = Stopwatch()..start();
  await callback();
  watch.stop();
  return _roundMs(watch.elapsedMicroseconds);
}

String _tableName(String prefix, String implementation) {
  final suffix = implementation.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
  final table = '${prefix}_$suffix';
  if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(table)) {
    throw ArgumentError.value(table, 'PG_BENCH_TABLE_PREFIX');
  }
  return table;
}

void _printSummary(List<Map<String, Object?>> results) {
  stdout.writeln('| Driver | connect ms | total ms | ops/s | status |');
  stdout.writeln('|---|---:|---:|---:|---|');
  for (final result in results) {
    final error = result['error'];
    if (error != null) {
      stdout.writeln(
        '| ${result['driver']} | ${result['connect_ms']} | - | - | error |',
      );
      continue;
    }

    stdout.writeln(
      '| ${result['driver']} | ${result['connect_ms']} | '
      '${result['total_measured_ms']} | '
      '${result['total_ops_per_second']} | ok |',
    );
  }
}

double _opsPerSecond(int operations, double ms) {
  if (ms <= 0) {
    return 0;
  }
  return _roundDouble(operations * 1000 / ms);
}

double _roundMs(int microseconds) => _roundDouble(microseconds / 1000);

double _roundDouble(num value) => double.parse(value.toStringAsFixed(3));

String? _envOptional(String name) {
  final value = Platform.environment[name];
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}

String _envString(String name, String defaultValue) =>
    _envOptional(name) ?? defaultValue;

int _envInt(String name, int defaultValue) {
  final value = _envOptional(name);
  if (value == null) {
    return defaultValue;
  }
  return int.parse(value);
}

bool _envBool(String name, bool defaultValue) {
  final value = _envOptional(name);
  if (value == null) {
    return defaultValue;
  }
  return value == '1' || value.toLowerCase() == 'true';
}

class _DriverSpec {
  const _DriverSpec({
    required this.name,
    required this.implementation,
    required this.dependency,
  });

  final String name;
  final String implementation;
  final String dependency;
}

class _BenchmarkConfig {
  const _BenchmarkConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
    required this.charset,
    required this.schema,
    required this.timezone,
    required this.pool,
    required this.poolSize,
    required this.iterations,
    required this.warmupIterations,
    required this.transactionIterations,
    required this.resultRows,
    required this.tablePrefix,
    required this.statementTimeout,
    required this.lockTimeout,
    required this.idleInTransactionSessionTimeout,
    required this.driverFilter,
  });

  factory _BenchmarkConfig.fromEnvironment() {
    return _BenchmarkConfig(
      host: _envString('PGHOST', 'localhost'),
      port: _envInt('PGPORT', 5432),
      database: _envString('PGDATABASE', 'banco_teste'),
      username: _envString('PGUSER', 'dart'),
      password: _envString('PGPASSWORD', 'dart'),
      charset: _envString('PGCLIENTENCODING', 'utf8'),
      schema: _envString('PGSCHEMA', 'public'),
      timezone: _envString('PGTIMEZONE', 'UTC'),
      pool: _envBool('PG_BENCH_POOL', false),
      poolSize: _envInt('PG_BENCH_POOL_SIZE', 2),
      iterations: _envInt('PG_BENCH_ITERATIONS', 200),
      warmupIterations: _envInt('PG_BENCH_WARMUP', 20),
      transactionIterations: _envInt('PG_BENCH_TX_ITERATIONS', 50),
      resultRows: _envInt('PG_BENCH_RESULT_ROWS', 200),
      tablePrefix: _envString('PG_BENCH_TABLE_PREFIX', 'eloquent_pg_bench'),
      statementTimeout: _envString('PG_BENCH_STATEMENT_TIMEOUT', '30s'),
      lockTimeout: _envString('PG_BENCH_LOCK_TIMEOUT', '10s'),
      idleInTransactionSessionTimeout:
          _envString('PG_BENCH_IDLE_TX_TIMEOUT', '30s'),
      driverFilter: _envOptional('PG_BENCH_DRIVERS'),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'host': host,
      'port': port,
      'database': database,
      'username': username,
      'charset': charset,
      'schema': schema,
      'timezone': timezone,
      'pool': pool,
      'poolsize': poolSize,
      'iterations': iterations,
      'warmup_iterations': warmupIterations,
      'transaction_iterations': transactionIterations,
      'result_rows': resultRows,
      'table_prefix': tablePrefix,
      'driver_filter': driverFilter,
    };
  }

  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
  final String charset;
  final String schema;
  final String timezone;
  final bool pool;
  final int poolSize;
  final int iterations;
  final int warmupIterations;
  final int transactionIterations;
  final int resultRows;
  final String tablePrefix;
  final String statementTimeout;
  final String lockTimeout;
  final String idleInTransactionSessionTimeout;
  final String? driverFilter;
}

class _Measurement {
  const _Measurement({
    required this.operations,
    required this.ms,
    this.checksum,
  });

  final int operations;
  final double ms;
  final int? checksum;

  double get opsPerSecond => _opsPerSecond(operations, ms);

  Map<String, Object?> toJson() {
    return {
      'operations': operations,
      'ms': ms,
      'ops_per_second': opsPerSecond,
      if (checksum != null) 'checksum': checksum,
    };
  }
}
