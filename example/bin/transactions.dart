// Transactions, nested transactions (SAVEPOINT), transactionIfNeeded, the
// ambient transactionScope, unique violations and locks.
//
//   dart run bin/transactions.dart
import 'package:eloquent/eloquent.dart';
import 'package:example_eloquent/config.dart';

Future<void> main() async {
  // A pool, so the two queue workers below run on separate connections.
  final manager = Manager()
    ..addConnection({...postgresConfig(), 'pool': true, 'poolsize': 4});
  final db = await manager.connection();
  await _createTables(db);

  // transaction() returns the callback's value; ctx is bound to it
  final orderId = await db.transaction<int>((ctx) async {
    final id = await ctx.table('ex_orders').insertGetId({'client': 'Ana'});
    await ctx.table('ex_items').insert({'order_id': id, 'sku': 'A1'});
    return id as int;
  });
  print('order $orderId committed');

  // An exception rolls everything back and is rethrown
  try {
    await db.transaction((ctx) async {
      await ctx.table('ex_orders').insert({'client': 'never saved'});
      throw StateError('payment refused');
    });
  } on StateError catch (e) {
    print('rolled back: ${e.message}');
  }

  // transaction() inside a transaction is a SAVEPOINT: only its part is undone
  await db.transaction((ctx) async {
    final id = await ctx.table('ex_orders').insertGetId({'client': 'Bruno'});
    try {
      await ctx.transaction((nested) async {
        await nested.table('ex_items').insert({'order_id': id, 'sku': 'B1'});
        throw Exception('item out of stock'); // ROLLBACK TO SAVEPOINT
      });
    } catch (_) {
      // the order goes on without the item
    }
    print('level inside: ${ctx.transactionLevel()}');
  });

  // transactionIfNeeded joins the caller's transaction or opens one
  await addItem(db, 1, 'C1'); // its own transaction
  await db.transaction((ctx) => addItem(ctx, 1, 'C2')); // the caller's

  // transactionScope: code that uses `db` (not ctx) joins the transaction
  await db.transactionScope((ctx) async {
    await _repositoryThatUsesDb(db);
    print('in scope: ${db.isInTransaction}');
    // Runs on another pooled connection and survives a rollback of the scope
    await db.outsideTransaction(
        () => db.table('ex_orders').insert({'client': 'audit log'}));
  });

  // Unique violations become UniqueConstraintViolationException
  try {
    await db.table('ex_tags').insert({'slug': 'dart'});
    await db.table('ex_tags').insert({'slug': 'dart'});
  } on UniqueConstraintViolationException catch (e) {
    print('duplicate: constraint ${e.constraint}');
  }

  // createOrFirst: insert, or return the row the unique index already has
  final tag = await db
      .table('ex_tags')
      .createOrFirst({'slug': 'dart'}, {'name': 'Dart'});
  print('createOrFirst: $tag');

  // Job queue: each worker takes a pending job no other worker holds
  await Future.wait([_worker(db, 'w1'), _worker(db, 'w2')]);
  final byWorker = await db
      .table('ex_jobs')
      .selectRaw('worker, count(*) as jobs')
      .groupBy('worker')
      .orderBy('worker')
      .get();
  print('jobs per worker: $byWorker');

  // A number per order, max + 1 under an advisory lock
  final numbered = await db.table('ex_orders').insertGetId({'client': 'Eva'});
  await db.transaction((ctx) async {
    for (final sku in ['D1', 'D2', 'D3']) {
      final line = await ctx
          .table('ex_items')
          .where('order_id', '=', numbered)
          .nextValue('line');
      await ctx
          .table('ex_items')
          .insert({'order_id': numbered, 'sku': sku, 'line': line});
    }
  });
  final lines = await db
      .table('ex_items')
      .where('order_id', '=', numbered)
      .orderBy('line')
      .pluck('line');
  print('lines: $lines');

  // Serialize a piece of code across connections: pg_advisory_xact_lock
  await db.transaction((ctx) async {
    await ctx.advisoryLock('monthly-closing');
    // ... one transaction at a time runs here, until commit
  });

  await _dropTables(db);
  await db.disconnect();
}

/// Works alone or as part of a larger transaction.
Future<void> addItem(Connection connection, int orderId, String sku) {
  return connection.transactionIfNeeded((ctx) async {
    await ctx.table('ex_items').insert({'order_id': orderId, 'sku': sku});
  });
}

Future<void> _repositoryThatUsesDb(Connection db) async {
  await db.table('ex_orders').insert({'client': 'from a repository'});
}

Future<void> _worker(Connection db, String name) async {
  while (true) {
    final took = await db.transaction<bool>((ctx) async {
      final job = await ctx
          .table('ex_jobs')
          .where('status', '=', 'pending')
          .orderBy('id')
          .lockForUpdate(skipLocked: true)
          .first();
      if (job == null) return false;
      await Future.delayed(const Duration(milliseconds: 50)); // the work
      await ctx
          .table('ex_jobs')
          .where('id', '=', job['id'])
          .update({'status': 'done', 'worker': name});
      return true;
    });
    if (!took) break;
  }
}

Future<void> _createTables(Connection db) async {
  await _dropTables(db);
  await db.unprepared('''
    create table ex_orders (id serial primary key, client varchar(40));
    create table ex_items (order_id int, sku varchar(10), line int);
    create table ex_tags (id serial primary key, slug varchar(20) unique,
                          name varchar(40));
    create table ex_jobs (id serial primary key, status varchar(10),
                          worker varchar(10));
    insert into ex_jobs (status) select 'pending' from generate_series(1, 6);
  ''');
}

Future<void> _dropTables(Connection db) =>
    db.unprepared('drop table if exists ex_orders, ex_items, ex_tags, ex_jobs');
