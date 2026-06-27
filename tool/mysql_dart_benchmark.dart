import 'dart:io';

import 'package:eloquent/eloquent.dart';

Future<void> main() async {
  final iterations =
      int.tryParse(Platform.environment['MYSQL_BENCH_ITERATIONS'] ?? '') ?? 200;
  final transactionIterations =
      int.tryParse(Platform.environment['MYSQL_BENCH_TX_ITERATIONS'] ?? '') ??
          50;
  final table = Platform.environment['MYSQL_BENCH_TABLE'] ??
      'eloquent_mysql_dart_benchmark';

  if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(table)) {
    throw ArgumentError.value(table, 'MYSQL_BENCH_TABLE');
  }

  final config = {
    'driver': 'mysql',
    'host': Platform.environment['MYSQL_HOST'] ?? 'localhost',
    'port': Platform.environment['MYSQL_PORT'] ?? '3306',
    'database': Platform.environment['MYSQL_DATABASE'] ?? 'banco_teste',
    'username': Platform.environment['MYSQL_USERNAME'] ?? 'dart',
    'password': Platform.environment['MYSQL_PASSWORD'] ?? 'dart',
  };
  final charset = Platform.environment['MYSQL_CHARSET'];
  if (charset != null && charset.isNotEmpty) {
    config['charset'] = charset;
  }

  final manager = Manager();
  manager.addConnection(config);
  manager.setAsGlobal();

  late final Connection db;
  db = await manager.connection();

  try {
    final setup = Stopwatch()..start();
    await db.execute('DROP TABLE IF EXISTS `$table`');
    await db.execute('''
      CREATE TABLE `$table` (
        id int NOT NULL AUTO_INCREMENT,
        name varchar(120) NOT NULL,
        score int NOT NULL,
        created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id)
      )
    ''');
    setup.stop();

    await db.table(table).insert({'name': 'warmup', 'score': 0});
    await db.table(table).where('id', '=', 1).first();
    await db.execute('TRUNCATE TABLE `$table`');

    final insertWatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      await db.table(table).insert({'name': 'client_$i', 'score': i});
    }
    insertWatch.stop();

    final selectWatch = Stopwatch()..start();
    for (var i = 1; i <= iterations; i++) {
      final row = await db.table(table).where('id', '=', i).first();
      if (row == null || row['id'] != i) {
        throw StateError('Unexpected row for id $i: $row');
      }
    }
    selectWatch.stop();

    final transactionWatch = Stopwatch()..start();
    await db.transaction((ctx) async {
      for (var i = 0; i < transactionIterations; i++) {
        await ctx.table(table).insert({
          'name': 'tx_client_$i',
          'score': iterations + i,
        });
      }
    });
    transactionWatch.stop();

    final count = await db.table(table).count();
    final totalOperations = iterations * 2 + transactionIterations;
    final totalMs = insertWatch.elapsedMilliseconds +
        selectWatch.elapsedMilliseconds +
        transactionWatch.elapsedMilliseconds;

    print('mysql_dart benchmark');
    print('host=${Platform.environment['MYSQL_HOST'] ?? 'localhost'} '
        'database=${Platform.environment['MYSQL_DATABASE'] ?? 'banco_teste'} '
        'iterations=$iterations tx_iterations=$transactionIterations');
    print('setup_ms=${setup.elapsedMilliseconds}');
    print('insert_${iterations}_ms=${insertWatch.elapsedMilliseconds}');
    print('select_by_id_${iterations}_ms=${selectWatch.elapsedMilliseconds}');
    print(
        'transaction_insert_${transactionIterations}_ms=${transactionWatch.elapsedMilliseconds}');
    print('total_measured_ms=$totalMs');
    print(
        'ops_per_second=${(totalOperations * 1000 / totalMs).toStringAsFixed(2)}');
    print('row_count=$count');
  } finally {
    await db.execute('DROP TABLE IF EXISTS `$table`');
    await manager.getDatabaseManager().purge('default');
  }
}
