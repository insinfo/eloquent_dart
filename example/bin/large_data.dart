// Bulk inserts, streaming large results and query logging.
//
//   dart run bin/large_data.dart
//   PG_DRIVER=dpgsql dart run bin/large_data.dart   # copyInto uses COPY
import 'package:eloquent/eloquent.dart';
import 'package:example_eloquent/config.dart';

Future<void> main() async {
  final manager = postgresManager();
  final db = await manager.connection();
  await db.unprepared('drop table if exists ex_readings; '
      'create table ex_readings (id int primary key, sensor text, value int)');

  // Log every statement (failed ones too) and warn about slow ones
  var statements = 0;
  final stopListening = db.listen((QueryExecuted q) => statements++);
  db.onSlowQuery(const Duration(milliseconds: 500),
      (q) => print('slow (${q.time.inMilliseconds} ms): ${q.toRawSql()}'));

  final rows = [
    for (var i = 1; i <= 20000; i++)
      {'id': i, 'sensor': 's${i % 4}', 'value': i % 100},
  ];

  // COPY ... FROM STDIN on dpgsql, multi-row INSERTs on the other drivers
  var watch = Stopwatch()..start();
  await db.table('ex_readings').copyInto(rows.take(10000));
  print('copyInto: 10000 rows in ${watch.elapsedMilliseconds} ms');

  // insert ... select * from unnest(?::int[], ...): one parameter per column
  watch = Stopwatch()..start();
  await db.table('ex_readings').insertUnnest(rows.skip(10000),
      types: {'id': 'int', 'sensor': 'text', 'value': 'int'});
  print('insertUnnest: 10000 rows in ${watch.elapsedMilliseconds} ms');

  // cursor(): rows are streamed from a server-side cursor; memory stays flat
  var sum = 0;
  await for (final row
      in db.table('ex_readings').where('sensor', '=', 's1').cursor()) {
    sum += row['value'] as int;
  }
  print('cursor sum: $sum');

  // lazyById(): keyset pages (where id > last), on every driver
  var count = 0;
  await for (final _ in db.table('ex_readings').lazyById(5000)) {
    count++;
  }
  print('lazyById rows: $count');

  // chunkById(): a page at a time, also keyset
  await db.table('ex_readings').chunkById(8000, (page) {
    print('chunk: ${page.length} rows, last id ${page.last['id']}');
    return true; // false stops
  });

  stopListening();
  print('statements logged: $statements');

  await db.unprepared('drop table ex_readings');
  await db.disconnect();
}
